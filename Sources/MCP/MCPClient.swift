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
    private let stderrCollector: MCPStderrCollector
    var launchDiagnostics: LaunchDiagnostics?
    private var lastProcessExit: MCPClientError?
    /// Set when `stop()` asked to tear the child down. The termination handler
    /// must not report that SIGTERM as the original handshake failure.
    private var stopRequested = false

    // shared MCP SDK state
    private var client: MCP.Client?
    private var stdioTransport: MCP.StdioTransport?
    private var httpTransport: MCP.HTTPClientTransport?
    var httpDiagnostics: HTTPDiagnostics?

    init(config: MCPServerConfig) {
        self.config = config
        self.stderrCollector = MCPStderrCollector(limitBytes: logTailLimitBytes)
    }

    func stop() async {
        // Kill the child first. `disconnect()` hops onto the SDK's actor, which can be
        // saturated when its receive loop is spinning on a half-open stream; with the
        // old disconnect-first order that could strand the process we were trying to
        // reap.
        stopRequested = true
        process?.terminate()
        process = nil

        await finishStderrCollection(timeoutNanoseconds: 400_000_000)
        syncStderrSnapshot()
        stderrReadTask?.cancel()
        stderrReadTask = nil

        // Fire and forget. `disconnect()` is best-effort SDK bookkeeping — the child is
        // already dead and nothing downstream needs it to finish — but it hops onto the
        // SDK's actor, which can be saturated when its receive loop is spinning on a
        // half-open stream. Awaiting it (even inside a task group with a timeout, which
        // still waits for every child before leaving scope) would let one wedged server
        // block the MCPHub actor and with it every other server's calls.
        if let client {
            Task { await client.disconnect() }
        }
        client = nil
        stdioTransport = nil
        httpTransport = nil
        httpDiagnostics = nil

        stdinPipe?.fileHandleForWriting.closeFile()
        stdinPipe = nil
        stdoutPipe?.fileHandleForReading.closeFile()
        stdoutPipe = nil
        // stderr read end is closed in `finishStderrCollection` so the reader
        // cannot block `stop()`. Do not close it again.
        stderrPipe = nil
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
                let (pageTools, nextCursor) = try await withTimeout(method: "tools/list", seconds: requestTimeoutSeconds) {
                    try await client.listTools(cursor: cursorSnapshot)
                }

                tools.append(contentsOf: pageTools.map { tool in
                    MCPToolInfo(
                        name: tool.name,
                        description: tool.description ?? "",
                        inputSchema: decodeParameterSchema(tool.inputSchema)
                            ?? ParameterSchema(properties: [:], required: []),
                        title: tool.title
                    )
                })

                cursor = nextCursor
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
            // The SDK's async convenience drops `structuredContent` from the
            // result (MCP Spec 2025-11-25). A future change can switch to the
            // `send()` / `RequestContext` path to surface structured JSON.
            let (content, isError): ([MCP.Tool.Content], Bool?) = try await withTimeout(
                method: "tools/call",
                seconds: toolCallTimeoutSeconds
            ) {
                try await client.callTool(name: name, arguments: args)
            }

            let text = content.compactMap(Self.line(for:)).joined(separator: "\n")

            return MCPToolCallResult(text: text, isError: isError ?? false)
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

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let client = MCP.Client(name: "Jin", version: version, title: "Jin")
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
            let mapped = MCPOAuthCoordinator.mapError(error)
            // Snapshot the real handshake error before `stop()` sends SIGTERM.
            // Otherwise the termination handler races in and the user only sees
            // "process exited (status: 15)".
            let preserved = enrich(mapped, method: "initialize")
            await stop()
            if mapped is MCPOAuthError {
                throw mapped
            }
            throw preserved
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
        var headers = http.resolvedHeaders()
        let authorizer: (any HTTPClientAuthorizer)?
        if case .oauth = http.authentication {
            authorizer = MCPOAuthCoordinator.authorizer(for: http.endpoint, legacyServerID: config.id)
            if let existing = authorizer?.authorizationHeader(for: http.endpoint) {
                headers["Authorization"] = existing
            }
        } else {
            authorizer = nil
        }
        httpDiagnostics = HTTPDiagnostics(endpoint: http.endpoint.absoluteString, headerNames: headers.keys.sorted())

        let configuration = httpClientTransportConfiguration()
        let transport = MCP.HTTPClientTransport(
            endpoint: http.endpoint,
            configuration: configuration,
            streaming: http.streaming,
            authorizer: authorizer,
            requestModifier: { request in
                var modified = request
                for (key, value) in headers {
                    // When an OAuth authorizer is active, let the SDK manage
                    // the Authorization header so refreshed tokens take effect.
                    if key.lowercased() == "authorization" && authorizer != nil {
                        continue
                    }
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
        stderrCollector.reset()
        launchDiagnostics = nil
        lastProcessExit = nil
        stopRequested = false

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
            MCPProcessRegistry.shared.unregister(proc)
            let status = proc.terminationStatus
            let reason = MCPProcessExitReason(proc.terminationReason)
            Task { [weak self] in
                guard let self else { return }
                await self.handleProcessExit(status: status, reason: reason)
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
        // Registered so app termination can reap the child synchronously;
        // the terminationHandler above unregisters on any exit.
        MCPProcessRegistry.shared.register(process)

        let stderrHandle = stderrPipe.fileHandleForReading
        stderrReadTask?.cancel()
        let collector = stderrCollector
        stderrReadTask = Task.detached(priority: .utility) {
            do {
                while !Task.isCancelled, let chunk = try stderrHandle.read(upToCount: 16 * 1024), !chunk.isEmpty {
                    collector.append(chunk)
                }
            } catch is CancellationError {
            } catch {
                // Ignore; stderr is best-effort diagnostics only.
            }
        }
    }

    private func handleProcessExit(status: Int32, reason: MCPProcessExitReason) async {
        let shouldRecordExit = !stopRequested
        await finishStderrCollection(timeoutNanoseconds: 400_000_000)
        stderrTail = stderrCollector.snapshot()
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

        guard shouldRecordExit else { return }
        lastProcessExit = .processExited(
            status: status,
            reason: reason,
            stderr: stderr,
            diagnostics: launchDiagnostics
        )
    }

    /// Harvest remaining stderr after the child dies or `stop()` is asked.
    ///
    /// Closing the read end unblocks `FileHandle.read` if the child ignored
    /// SIGTERM or a grandchild still holds the write end. The wait itself must
    /// not join `task.value` inside a task group: leaving the group waits for
    /// every child, and `task.value` is not aborted by `cancelAll()`.
    private func finishStderrCollection(timeoutNanoseconds: UInt64) async {
        stderrPipe?.fileHandleForReading.closeFile()

        guard let task = stderrReadTask else { return }
        await MCPTaskWait.firstCompletion(timeoutNanoseconds: timeoutNanoseconds) {
            await task.value
        }
    }

    private func syncStderrSnapshot() {
        stderrTail = stderrCollector.snapshot()
    }

    // MARK: - Tool result content

    /// Renders one tool-result content item.
    ///
    /// Only `.text` used to survive, so an embedded resource's text was thrown away
    /// and an image or audio clip vanished without a trace — the model could not even
    /// tell that something had come back. Inline resource text is recovered as real
    /// content; binary payloads get a placeholder so the loss is at least visible.
    /// (Surfacing the bytes themselves needs a newer SDK and is a separate change.)
    static func line(for content: MCP.Tool.Content) -> String? {
        switch content {
        case .text(let text, _, _):
            return text
        case .image(let data, let mimeType, _, _):
            return "[image returned — \(mimeType), \(formattedByteCount(base64Length: data.count)); not shown]"
        case .audio(let data, let mimeType, _, _):
            return "[audio returned — \(mimeType), \(formattedByteCount(base64Length: data.count)); not shown]"
        case .resource(let resource, _, _):
            if let text = resource.text, !text.isEmpty { return text }
            let mimeType = resource.mimeType ?? "unknown"
            return "[resource \(resource.uri) — \(mimeType)]"
        case .resourceLink(let uri, let name, _, _, let mimeType, _):
            let type = mimeType ?? "unknown"
            return "[resource link \(name) — \(uri), \(type)]"
        @unknown default:
            return nil
        }
    }

    /// Approximates the decoded size of a base64 payload. Deliberately not
    /// `ByteCountFormatter`: this string reaches the model, so it must not vary with
    /// locale or OS version.
    static func formattedByteCount(base64Length: Int) -> String {
        let bytes = Double(base64Length) * 3.0 / 4.0
        if bytes < 1024 { return "\(Int(bytes)) B" }
        if bytes < 1024 * 1024 { return String(format: "%.0f KB", bytes / 1024) }
        return String(format: "%.1f MB", bytes / (1024 * 1024))
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
        syncStderrSnapshot()
        return DiagnosticsSnapshot(
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

/// Completes when `operation` finishes or `timeoutNanoseconds` elapses,
/// whichever comes first. The timeout path does not join `operation`, so a
/// stuck `FileHandle.read` cannot hang `stop()`.
enum MCPTaskWait {
    static func firstCompletion(
        timeoutNanoseconds: UInt64,
        operation: @escaping @Sendable () async -> Void
    ) async {
        let timeout = Task {
            try await Task.sleep(nanoseconds: timeoutNanoseconds)
        }
        let done = Task {
            await operation()
            timeout.cancel()
        }
        _ = await timeout.result
        done.cancel()
    }
}

/// Lock-backed stderr tail so the reader never hops onto `MCPClient`.
/// Awaiting the reader from the actor would otherwise deadlock.
final class MCPStderrCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let limitBytes: Int

    init(limitBytes: Int) {
        self.limitBytes = limitBytes
    }

    func reset() {
        lock.lock()
        data.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        if data.count > limitBytes {
            data.removeSubrange(0..<(data.count - limitBytes))
        }
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
