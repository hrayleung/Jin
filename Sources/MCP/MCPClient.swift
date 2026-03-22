import Collections
import Foundation
import MCP

#if canImport(System)
    import System
#else
    @preconcurrency import SystemPackage
#endif

/// MCP server lifecycle management.
///
/// Environment setup and command parsing are in `MCPClientEnvironment.swift`.
/// Supporting types (MCPToolInfo, MCPToolCallResult, error types, diagnostics) are in `MCPClientTypes.swift`.
actor MCPClient {
    let config: MCPServerConfig

    private let handshakeTimeoutSeconds: Double = 180
    private let requestTimeoutSeconds: Double = 60
    private let toolCallTimeoutSeconds: Double = 180

    static let defaultPathEntries: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    private let logTailLimitBytes = 32 * 1024

    // stdio lifecycle state
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stderrReadTask: Task<Void, Never>?
    var stderrTail = Data()
    var launchDiagnostics: LaunchDiagnostics?
    private var lastProcessExit: MCPClientError?

    // shared MCP SDK state
    private var client: MCP.Client?
    private var stdioTransport: MCP.StdioTransport?
    private var httpTransport: MCP.HTTPClientTransport?
    var httpDiagnostics: HTTPDiagnostics?

    init(config: MCPServerConfig) {
        self.config = config
    }

    func stop() async {
        await client?.disconnect()
        client = nil
        stdioTransport = nil
        httpTransport = nil
        httpDiagnostics = nil

        stderrReadTask?.cancel()
        stderrReadTask = nil

        stdinPipe?.fileHandleForWriting.closeFile()
        stdinPipe = nil
        stdoutPipe?.fileHandleForReading.closeFile()
        stdoutPipe = nil
        stderrPipe?.fileHandleForReading.closeFile()
        stderrPipe = nil

        process?.terminate()
        process = nil
    }

    // MARK: - Public API

    func listTools() async throws -> [MCPToolInfo] {
        try await startIfNeeded()
        guard let client else { throw MCPClientError.notRunning }

        var tools: [MCPToolInfo] = []
        var cursor: String?

        repeat {
            do {
                let cursorSnapshot = cursor
                let page = try await withTimeout(method: "tools/list", seconds: requestTimeoutSeconds) {
                    try await client.listTools(cursor: cursorSnapshot)
                }

                tools.append(contentsOf: page.tools.map { tool in
                    MCPToolInfo(
                        name: tool.name,
                        description: tool.description ?? "",
                        inputSchema: decodeParameterSchema(tool.inputSchema)
                            ?? ParameterSchema(properties: [:], required: [])
                    )
                })

                cursor = page.nextCursor
            } catch {
                throw enrich(error, method: "tools/list")
            }
        } while cursor != nil

        return tools
    }

    func callTool(name: String, arguments: [String: AnyCodable]) async throws -> MCPToolCallResult {
        try await startIfNeeded()
        guard let client else { throw MCPClientError.notRunning }

        let args = try decodeArguments(arguments)

        do {
            let result = try await withTimeout(method: "tools/call", seconds: toolCallTimeoutSeconds) {
                try await client.callTool(name: name, arguments: args)
            }

            let text = result.content.compactMap { item -> String? in
                if case .text(let text) = item { return text }
                return nil
            }.joined(separator: "\n")

            return MCPToolCallResult(text: text, isError: result.isError ?? false)
        } catch {
            throw enrich(error, method: "tools/call")
        }
    }

    // MARK: - Startup

    private func startIfNeeded() async throws {
        if let lastProcessExit {
            // Prefer a clear process-exit error over opaque downstream transport failures.
            self.lastProcessExit = nil
            throw lastProcessExit
        }

        if client != nil { return }

        let client = MCP.Client(name: "Jin", version: "0.1.0")
        self.client = client

        do {
            switch config.transport {
            case .stdio(let stdio):
                try startProcess(stdio: stdio)
                try await connectStdioClient(client: client)
            case .http(let http):
                try await connectHTTPClient(client: client, http: http)
            }
        } catch {
            let enriched = enrich(error, method: "initialize")
            await stop()
            throw enriched
        }
    }

    private func connectStdioClient(client: MCP.Client) async throws {
        guard let stdinPipe, let stdoutPipe else { throw MCPClientError.notRunning }

        let inputFD = FileDescriptor(rawValue: stdoutPipe.fileHandleForReading.fileDescriptor)
        let outputFD = FileDescriptor(rawValue: stdinPipe.fileHandleForWriting.fileDescriptor)

        let transport = MCP.StdioTransport(input: inputFD, output: outputFD)
        self.stdioTransport = transport

        _ = try await withTimeout(method: "initialize", seconds: handshakeTimeoutSeconds) {
            try await client.connect(transport: transport)
        }
    }

    private func connectHTTPClient(client: MCP.Client, http: MCPHTTPTransportConfig) async throws {
        let headers = http.resolvedHeaders()
        httpDiagnostics = HTTPDiagnostics(endpoint: http.endpoint.absoluteString, headerNames: headers.keys.sorted())

        let configuration = httpClientTransportConfiguration()
        let transport = MCP.HTTPClientTransport(
            endpoint: http.endpoint,
            configuration: configuration,
            streaming: http.streaming,
            requestModifier: { request in
                var modified = request
                for (key, value) in headers {
                    modified.setValue(value, forHTTPHeaderField: key)
                }
                return modified
            }
        )

        httpTransport = transport

        _ = try await withTimeout(method: "initialize", seconds: handshakeTimeoutSeconds) {
            try await client.connect(transport: transport)
        }
    }

    private func httpClientTransportConfiguration() -> URLSessionConfiguration {
        URLSessionConfiguration.default
    }

    // MARK: - Process lifecycle (stdio)

    private func startProcess(stdio: MCPStdioTransportConfig) throws {
        guard process == nil else { return }

        stderrTail.removeAll(keepingCapacity: true)
        launchDiagnostics = nil
        lastProcessExit = nil

        let (command, args) = try parseCommandAndArgs(stdio: stdio)
        let workingDirectory = try workingDirectoryForProcess(command: command)
        let env = try makeProcessEnvironment(stdio: stdio, command: command)

        guard let executableURL = resolveExecutableURL(command: command, environment: env, workingDirectory: workingDirectory) else {
            throw MCPClientError.executableNotFound(command: command)
        }

        launchDiagnostics = LaunchDiagnostics(
            executablePath: executableURL.path,
            args: args,
            workingDirectory: workingDirectory.path,
            nodeEnvironment: nodeEnvironmentDiagnostics(from: env)
        )

        let process = Process()
        process.executableURL = executableURL
        process.arguments = args
        process.environment = env
        process.currentDirectoryURL = workingDirectory

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            Task { [weak self] in
                guard let self else { return }
                await self.handleProcessExit(status: status)
            }
        }

        do {
            try process.run()
        } catch {
            throw MCPClientError.processLaunchFailed(command: command, underlying: error)
        }

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        let stderrHandle = stderrPipe.fileHandleForReading
        stderrReadTask?.cancel()
        stderrReadTask = Task.detached(priority: .utility) { [weak self] in
            do {
                while !Task.isCancelled, let chunk = try stderrHandle.read(upToCount: 16 * 1024), !chunk.isEmpty {
                    guard let self else { return }
                    await self.handleStderrData(chunk)
                }
            } catch is CancellationError {
            } catch {
                // Ignore; stderr is best-effort diagnostics only.
            }
        }
    }

    private func handleProcessExit(status: Int32) async {
        let stderr = diagnosticsTailString(from: stderrTail)

        stderrReadTask?.cancel()
        stderrReadTask = nil

        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        process = nil

        await client?.disconnect()
        client = nil
        stdioTransport = nil
        httpTransport = nil

        lastProcessExit = .processExited(status: status, stderr: stderr, diagnostics: launchDiagnostics)
    }

    private func handleStderrData(_ data: Data) async {
        stderrTail.append(data)
        if stderrTail.count > logTailLimitBytes {
            stderrTail.removeSubrange(0..<(stderrTail.count - logTailLimitBytes))
        }
    }

    // MARK: - Encoding / decoding helpers

    private func decodeArguments(_ arguments: [String: AnyCodable]) throws -> [String: MCP.Value]? {
        guard !arguments.isEmpty else { return nil }
        let data = try JSONEncoder().encode(arguments)
        return try JSONDecoder().decode([String: MCP.Value].self, from: data)
    }

    private func decodeParameterSchema(_ value: MCP.Value) -> ParameterSchema? {
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(ParameterSchema.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Diagnostics & robustness

    func diagnosticsTailString(from data: Data) -> String? {
        let trimmed = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func currentDiagnosticsSnapshot() -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            stderr: diagnosticsTailString(from: stderrTail),
            launch: launchDiagnostics,
            http: httpDiagnostics
        )
    }

    private func enrich(_ error: Error, method: String) -> Error {
        if let error = error as? MCPClientError { return error }
        if let lastProcessExit { return lastProcessExit }

        let snapshot = currentDiagnosticsSnapshot()
        return MCPClientError.requestFailed(
            method: method,
            transport: config.transport.kind,
            underlying: error,
            stderr: snapshot.stderr,
            diagnostics: snapshot.launch,
            httpDiagnostics: snapshot.http
        )
    }

    private func withTimeout<T>(
        method: String,
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        guard seconds > 0 else { return try await operation() }

        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                let snapshot = await self.currentDiagnosticsSnapshot()
                throw MCPClientError.requestTimedOut(
                    method: method,
                    seconds: seconds,
                    transport: self.config.transport.kind,
                    stderr: snapshot.stderr,
                    diagnostics: snapshot.launch,
                    httpDiagnostics: snapshot.http
                )
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
