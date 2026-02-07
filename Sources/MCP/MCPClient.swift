import Foundation
import MCP

#if canImport(System)
    import System
#else
    @preconcurrency import SystemPackage
#endif

actor MCPClient {
    private let config: MCPServerConfig

    private let handshakeTimeoutSeconds: Double = 180
    private let requestTimeoutSeconds: Double = 60
    private let toolCallTimeoutSeconds: Double = 180

    private static let defaultPathEntries: [String] = [
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
    private var stderrTail = Data()
    private var launchDiagnostics: LaunchDiagnostics?
    private var lastProcessExit: MCPClientError?

    // shared MCP SDK state
    private var client: MCP.Client?
    private var stdioTransport: MCP.StdioTransport?
    private var httpTransport: MCP.HTTPClientTransport?
    private var httpDiagnostics: HTTPDiagnostics?

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

        let transport = MCP.HTTPClientTransport(
            endpoint: http.endpoint,
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
            guard let self else { return }
            Task { await self.handleProcessExit(status: proc.terminationStatus) }
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

    // MARK: - Command parsing & environment (stdio)

    private func parseCommandAndArgs(stdio: MCPStdioTransportConfig) throws -> (command: String, args: [String]) {
        let trimmedCommandLine = stdio.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommandLine.isEmpty else {
            throw MCPClientError.invalidCommand
        }

        let tokens: [String]
        do {
            tokens = try CommandLineTokenizer.tokenize(trimmedCommandLine)
        } catch {
            throw MCPClientError.invalidCommand
        }

        guard let command = tokens.first else {
            throw MCPClientError.invalidCommand
        }

        var args = Array(tokens.dropFirst())
        if !stdio.args.isEmpty {
            args.append(contentsOf: stdio.args)
        }

        return (command, args)
    }

    private func makeProcessEnvironment(stdio: MCPStdioTransportConfig, command: String) throws -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        for (key, value) in stdio.env {
            env[key] = value
        }

        env["PATH"] = mergedPath(existing: env["PATH"])
        try applyNodeIsolationIfNeeded(stdio: stdio, command: command, environment: &env)
        return env
    }

    private func mergedPath(existing: String?) -> String {
        let existingComponents = (existing ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)

        var seen = Set<String>()
        var merged: [String] = []

        func append(_ entry: String) {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return }
            merged.append(trimmed)
            seen.insert(trimmed)
        }

        for entry in existingComponents {
            append(entry)
        }

        for entry in Self.defaultPathEntries {
            append(entry)
        }

        for entry in additionalPathEntries() {
            append(entry)
        }

        return merged.joined(separator: ":")
    }

    private func applyNodeIsolationIfNeeded(
        stdio: MCPStdioTransportConfig,
        command: String,
        environment: inout [String: String]
    ) throws {
        let base = (command as NSString).lastPathComponent.lowercased()
        let isNodeLauncher = ["npx", "npm", "pnpm", "yarn", "bunx", "bun"].contains(base)
        guard isNodeLauncher else { return }

        let root = try nodeIsolationRoot()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let npmCache = root.appendingPathComponent("npm-cache", isDirectory: true)
        let npmPrefix = root.appendingPathComponent("npm-prefix", isDirectory: true)
        let npmrc = home.appendingPathComponent(".npmrc", isDirectory: false)

        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: npmCache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: npmPrefix, withIntermediateDirectories: true)

        if stdio.env["HOME"] == nil {
            environment["HOME"] = home.path
        }

        if stdio.env["NPM_CONFIG_USERCONFIG"] == nil && stdio.env["npm_config_userconfig"] == nil {
            let inherited = safeNpmrcEntriesToInherit(from: environment)
            try ensureIsolatedNpmrc(at: npmrc, npmPrefix: npmPrefix, npmCache: npmCache, inherited: inherited)

            environment["NPM_CONFIG_USERCONFIG"] = npmrc.path
            environment["npm_config_userconfig"] = npmrc.path
        }

        if stdio.env["NPM_CONFIG_CACHE"] == nil && stdio.env["npm_config_cache"] == nil {
            environment["NPM_CONFIG_CACHE"] = npmCache.path
            environment["npm_config_cache"] = npmCache.path
        }

        if stdio.env["NPM_CONFIG_PREFIX"] == nil && stdio.env["npm_config_prefix"] == nil {
            environment["NPM_CONFIG_PREFIX"] = npmPrefix.path
            environment["npm_config_prefix"] = npmPrefix.path
        }
    }

    private func safeNpmrcEntriesToInherit(from environment: [String: String]) -> [String: String] {
        guard let url = userNpmrcURL(from: environment) else { return [:] }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return NPMRCUtils.safeEntriesToInherit(from: contents)
    }

    private func userNpmrcURL(from environment: [String: String]) -> URL? {
        if let path = environment["NPM_CONFIG_USERCONFIG"] ?? environment["npm_config_userconfig"] {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let expanded = (trimmed as NSString).expandingTildeInPath
                return URL(fileURLWithPath: expanded)
            }
        }

        let fallback = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".npmrc")
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    private func ensureIsolatedNpmrc(
        at url: URL,
        npmPrefix: URL,
        npmCache: URL,
        inherited: [String: String]
    ) throws {
        let desiredAssignments: [String: String] = [
            "prefix": npmPrefix.path,
            "cache": npmCache.path,
            "fund": "false",
            "update-notifier": "false",
            "progress": "false",
        ]

        let existingContents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let existingAssignments = NPMRCUtils.parseAssignments(from: existingContents)

        var linesToAppend: [String] = []

        for (key, value) in desiredAssignments {
            if existingAssignments[key] != value {
                linesToAppend.append("\(key)=\(value)")
            }
        }

        for (key, value) in inherited.sorted(by: { $0.key < $1.key }) {
            if existingAssignments[key] == nil {
                linesToAppend.append("\(key)=\(value)")
            }
        }

        guard !linesToAppend.isEmpty else { return }

        var newContents = existingContents
        if newContents.isEmpty {
            newContents = "# Generated by Jin (MCP node isolation)\n"
        } else if !newContents.hasSuffix("\n") {
            newContents.append("\n")
        }

        newContents.append(linesToAppend.joined(separator: "\n"))
        newContents.append("\n")

        do {
            try newContents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw MCPClientError.environmentSetupFailed(message: "Failed to write \(url.path): \(error.localizedDescription)")
        }
    }

    private func nodeIsolationRoot() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw MCPClientError.environmentSetupFailed(message: "Unable to locate Application Support directory.")
        }

        let safeID = sanitizePathComponent(config.id)
        let root = base
            .appendingPathComponent("Jin", isDirectory: true)
            .appendingPathComponent("MCP", isDirectory: true)
            .appendingPathComponent("node", isDirectory: true)
            .appendingPathComponent(safeID, isDirectory: true)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func sanitizePathComponent(_ string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return UUID().uuidString }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        var result = ""
        result.reserveCapacity(trimmed.count)
        for scalar in trimmed.unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else {
                result.append("_")
            }
        }

        return result.isEmpty ? UUID().uuidString : result
    }

    private func nodeEnvironmentDiagnostics(from environment: [String: String]) -> NodeEnvironmentDiagnostics? {
        guard let npmUserConfig = environment["NPM_CONFIG_USERCONFIG"] ?? environment["npm_config_userconfig"] else {
            return nil
        }

        let home = environment["HOME"]
        let npmCache = environment["NPM_CONFIG_CACHE"] ?? environment["npm_config_cache"]
        let npmPrefix = environment["NPM_CONFIG_PREFIX"] ?? environment["npm_config_prefix"]
        return NodeEnvironmentDiagnostics(home: home, npmUserConfig: npmUserConfig, npmCache: npmCache, npmPrefix: npmPrefix)
    }

    private func resolveExecutableURL(command: String, environment: [String: String], workingDirectory: URL) -> URL? {
        let expanded = (command as NSString).expandingTildeInPath

        if expanded.contains("/") {
            let path: String
            if expanded.hasPrefix("/") {
                path = expanded
            } else {
                path = workingDirectory
                    .appendingPathComponent(expanded)
                    .path
            }

            guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }

        let pathValue = environment["PATH"] ?? ""
        for dir in pathValue.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = "\(dir)/\(expanded)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        return nil
    }

    private func defaultWorkingDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    private func workingDirectoryForProcess(command: String) throws -> URL {
        let base = (command as NSString).lastPathComponent.lowercased()
        let isNodeLauncher = ["npx", "npm", "pnpm", "yarn", "bunx", "bun"].contains(base)
        guard isNodeLauncher else { return defaultWorkingDirectory() }

        // Avoid treating the user's ~/.npmrc as a project-level .npmrc by running in a clean directory.
        return try nodeIsolationRoot()
    }

    // MARK: - Diagnostics & robustness

    private func additionalPathEntries() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser

        var candidates: [String] = [
            home.appendingPathComponent(".volta/bin").path,
            home.appendingPathComponent(".asdf/shims").path,
            home.appendingPathComponent(".mise/shims").path,
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent("bin").path,
        ]

        candidates.append(contentsOf: nvmBinPaths(home: home))
        candidates.append(contentsOf: fnmBinPaths(home: home))

        return candidates.filter(isExistingDirectory)
    }

    private func nvmBinPaths(home: URL) -> [String] {
        let root = home.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return items.map { $0.appendingPathComponent("bin", isDirectory: true).path }
    }

    private func fnmBinPaths(home: URL) -> [String] {
        let root = home.appendingPathComponent(".fnm/node-versions", isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return items.map { $0.appendingPathComponent("installation/bin", isDirectory: true).path }
    }

    private func isExistingDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func diagnosticsTailString(from data: Data) -> String? {
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

struct MCPToolInfo: Identifiable, Sendable {
    let name: String
    let description: String
    let inputSchema: ParameterSchema

    var id: String { name }
}

struct MCPToolCallResult: Sendable {
    let text: String
    let isError: Bool
}

private struct DiagnosticsSnapshot: Sendable {
    let stderr: String?
    let launch: LaunchDiagnostics?
    let http: HTTPDiagnostics?
}

private enum MCPClientError: Error, LocalizedError {
    case notRunning
    case executableNotFound(command: String)
    case invalidCommand
    case environmentSetupFailed(message: String)
    case processLaunchFailed(command: String, underlying: Error)
    case processExited(status: Int32, stderr: String?, diagnostics: LaunchDiagnostics?)
    case requestTimedOut(
        method: String,
        seconds: Double,
        transport: MCPTransportKind,
        stderr: String?,
        diagnostics: LaunchDiagnostics?,
        httpDiagnostics: HTTPDiagnostics?
    )
    case requestFailed(
        method: String,
        transport: MCPTransportKind,
        underlying: Error,
        stderr: String?,
        diagnostics: LaunchDiagnostics?,
        httpDiagnostics: HTTPDiagnostics?
    )

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return "MCP server is not running."
        case .executableNotFound(let command):
            return "MCP server executable not found: \(command). If you installed it via Homebrew, make sure /opt/homebrew/bin is in PATH, or set a full path in Command."
        case .invalidCommand:
            return "Invalid MCP server command. Use the Command + Arguments fields (or paste a full command line into Command)."
        case .environmentSetupFailed(let message):
            return "Failed to set up MCP server environment.\n\n\(message)"
        case .processLaunchFailed(let command, let underlying):
            return "Failed to start MCP server (\(command)): \(underlying.localizedDescription)"
        case .processExited(let status, let stderr, let diagnostics):
            var message = "MCP server process exited (status: \(status))."
            if let diagnostics {
                message += "\n\n\(diagnostics.formatted())"
            }
            if let stderr, !stderr.isEmpty {
                message += "\n\nstderr:\n\(stderr)"
            }
            return message
        case .requestTimedOut(let method, let seconds, let transport, let stderr, let diagnostics, let httpDiagnostics):
            var message = "MCP request timed out (\(method), \(transport.rawValue)) after \(Int(seconds))s."

            if let diagnostics {
                message += "\n\n\(diagnostics.formatted())"
            }

            if let httpDiagnostics {
                message += "\n\n\(httpDiagnostics.formatted())"
            }

            if let stderr, !stderr.isEmpty {
                message += "\n\nstderr:\n\(stderr)"
            }

            if method == "initialize" {
                switch transport {
                case .stdio:
                    message += "\n\nTip: If this server works in another client, compare the exact command line + env. Jin runs the command directly (no login shell), so tools installed via nvm/asdf/fnm may require using a wrapper script or running via /bin/zsh -lc."
                    message += "\n\nIf you're using npx and it hangs without output, check your ~/.npmrc (e.g. custom prefix=) and consider setting HOME or NPM_CONFIG_USERCONFIG in the server env vars to isolate npm state."
                case .http:
                    message += "\n\nTip: Verify endpoint URL, auth headers/token, and whether the server expects streamable HTTP with SSE enabled."
                }
            }

            return message
        case .requestFailed(let method, let transport, let underlying, let stderr, let diagnostics, let httpDiagnostics):
            var message = "MCP request failed (\(method), \(transport.rawValue)): \(underlying.localizedDescription)"

            if let diagnostics {
                message += "\n\n\(diagnostics.formatted())"
            }

            if let httpDiagnostics {
                message += "\n\n\(httpDiagnostics.formatted())"
            }

            if let stderr, !stderr.isEmpty {
                message += "\n\nstderr:\n\(stderr)"
            }

            return message
        }
    }
}

private struct LaunchDiagnostics: Sendable {
    let executablePath: String
    let args: [String]
    let workingDirectory: String
    let nodeEnvironment: NodeEnvironmentDiagnostics?

    func formatted() -> String {
        var lines: [String] = []
        lines.append("Command:")
        lines.append("\(executablePath) \(CommandLineTokenizer.render(args))")
        lines.append("Working directory:")
        lines.append(workingDirectory)

        if let nodeEnvironment {
            lines.append("Node environment:")
            if let home = nodeEnvironment.home { lines.append("HOME=\(home)") }
            lines.append("NPM_CONFIG_USERCONFIG=\(nodeEnvironment.npmUserConfig)")
            if let cache = nodeEnvironment.npmCache { lines.append("NPM_CONFIG_CACHE=\(cache)") }
            if let prefix = nodeEnvironment.npmPrefix { lines.append("NPM_CONFIG_PREFIX=\(prefix)") }
        }

        return lines.joined(separator: "\n")
    }
}

private struct NodeEnvironmentDiagnostics: Sendable {
    let home: String?
    let npmUserConfig: String
    let npmCache: String?
    let npmPrefix: String?
}

private struct HTTPDiagnostics: Sendable {
    let endpoint: String
    let headerNames: [String]

    func formatted() -> String {
        var lines: [String] = []
        lines.append("HTTP endpoint:")
        lines.append(endpoint)
        if !headerNames.isEmpty {
            lines.append("HTTP headers:")
            lines.append(headerNames.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}
