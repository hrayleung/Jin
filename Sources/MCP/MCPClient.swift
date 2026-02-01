import Foundation

actor MCPClient {
    private let config: MCPServerConfig
    private let protocolVersion = "2024-11-05"

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?

    private var framer = MCPMessageFramer()
    private var nextRequestID: Int = 1
    private var pendingRequests: [Int: CheckedContinuation<Any, Error>] = [:]

    private var isInitialized = false

    init(config: MCPServerConfig) {
        self.config = config
    }

    func startIfNeeded() async throws {
        if isInitialized { return }
        try startProcess()
        try await initializeHandshake()
        isInitialized = true
    }

    func stop() {
        stdoutHandle?.readabilityHandler = nil
        stdoutHandle = nil

        stdinHandle?.closeFile()
        stdinHandle = nil

        process?.terminate()
        process = nil

        failAllPending(with: MCPError.notRunning)
        isInitialized = false
    }

    // MARK: - Public API

    func listTools() async throws -> [MCPToolInfo] {
        try await startIfNeeded()

        var tools: [MCPToolInfo] = []
        var cursor: String?

        repeat {
            var params: [String: Any] = [:]
            if let cursor {
                params["cursor"] = cursor
            }

            let result = try await sendRequest(method: "tools/list", params: params.isEmpty ? nil : params)

            guard let dict = result as? [String: Any] else {
                throw MCPError.invalidResponse
            }

            if let toolDicts = dict["tools"] as? [[String: Any]] {
                tools.append(contentsOf: toolDicts.compactMap(parseToolInfo))
            }

            cursor = dict["nextCursor"] as? String
        } while cursor != nil

        return tools
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolCallResult {
        try await startIfNeeded()

        let result = try await sendRequest(
            method: "tools/call",
            params: [
                "name": name,
                "arguments": arguments
            ]
        )

        guard let dict = result as? [String: Any] else {
            throw MCPError.invalidResponse
        }

        let isError = dict["isError"] as? Bool ?? false
        let content = (dict["content"] as? [[String: Any]]) ?? []

        let text = content.compactMap { item in
            guard (item["type"] as? String) == "text" else { return nil }
            return item["text"] as? String
        }.joined(separator: "\n")

        return MCPToolCallResult(text: text, isError: isError)
    }

    // MARK: - Process lifecycle

    private func startProcess() throws {
        guard process == nil else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [config.command] + config.args

        var env = ProcessInfo.processInfo.environment
        for (key, value) in config.env {
            env[key] = value
        }
        process.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            Task { await self.handleProcessExit(status: proc.terminationStatus) }
        }

        try process.run()

        self.process = process
        stdinHandle = stdinPipe.fileHandleForWriting

        let stdoutHandle = stdoutPipe.fileHandleForReading
        self.stdoutHandle = stdoutHandle
        stdoutHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let self else { return }
            Task { await self.handleStdoutData(data) }
        }
    }

    private func handleProcessExit(status: Int32) {
        stdoutHandle?.readabilityHandler = nil
        stdoutHandle = nil
        stdinHandle = nil
        process = nil
        isInitialized = false

        failAllPending(with: MCPError.processExited(status: status))
    }

    // MARK: - JSON-RPC

    private func initializeHandshake() async throws {
        let result = try await sendRequest(
            method: "initialize",
            params: [
                "protocolVersion": protocolVersion,
                "capabilities": [:],
                "clientInfo": [
                    "name": "Jin",
                    "version": "0.1.0"
                ]
            ]
        )

        guard (result as? [String: Any]) != nil else {
            throw MCPError.invalidResponse
        }

        try sendNotification(method: "notifications/initialized", params: nil)
    }

    private func sendRequest(method: String, params: [String: Any]?) async throws -> Any {
        guard stdinHandle != nil else { throw MCPError.notRunning }

        let id = nextRequestID
        nextRequestID += 1

        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method
        ]
        if let params {
            payload["params"] = params
        }

        let data = try JSONSerialization.data(withJSONObject: payload)
        try writeFramedMessage(data)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
        }
    }

    private func sendNotification(method: String, params: [String: Any]?) throws {
        guard stdinHandle != nil else { throw MCPError.notRunning }

        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method
        ]
        if let params {
            payload["params"] = params
        }

        let data = try JSONSerialization.data(withJSONObject: payload)
        try writeFramedMessage(data)
    }

    private func writeFramedMessage(_ json: Data) throws {
        guard let stdinHandle else { throw MCPError.notRunning }
        stdinHandle.write(MCPMessageFramer.frame(json))
    }

    private func handleStdoutData(_ data: Data) async {
        framer.append(data)

        while true {
            do {
                guard let message = try framer.nextMessage() else { break }
                handleMessage(message)
            } catch {
                failAllPending(with: error)
                break
            }
        }
    }

    private func handleMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        guard let id = json["id"] as? Int else {
            // Notification from server; ignored for now.
            return
        }

        guard let continuation = pendingRequests.removeValue(forKey: id) else {
            return
        }

        if let error = json["error"] as? [String: Any] {
            let code = error["code"] as? Int
            let message = error["message"] as? String ?? "Unknown MCP error"
            continuation.resume(throwing: MCPError.rpcError(code: code, message: message))
            return
        }

        continuation.resume(returning: json["result"] as Any)
    }

    private func failAllPending(with error: Error) {
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: error)
        }
        pendingRequests.removeAll()
    }

    // MARK: - Parsing

    private func parseToolInfo(_ dict: [String: Any]) -> MCPToolInfo? {
        guard let name = dict["name"] as? String else { return nil }
        let description = (dict["description"] as? String) ?? ""
        let inputSchema = dict["inputSchema"] as? [String: Any] ?? [:]

        let schemaData = (try? JSONSerialization.data(withJSONObject: inputSchema)) ?? Data()
        let schema = (try? JSONDecoder().decode(ParameterSchema.self, from: schemaData))
            ?? ParameterSchema(properties: [:], required: [])

        return MCPToolInfo(name: name, description: description, inputSchema: schema)
    }
}

struct MCPToolInfo: Sendable {
    let name: String
    let description: String
    let inputSchema: ParameterSchema
}

struct MCPToolCallResult: Sendable {
    let text: String
    let isError: Bool
}

enum MCPError: Error, LocalizedError {
    case notRunning
    case processExited(status: Int32)
    case invalidResponse
    case rpcError(code: Int?, message: String)

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return "MCP server is not running."
        case .processExited(let status):
            return "MCP server process exited (status: \(status))."
        case .invalidResponse:
            return "Invalid response from MCP server."
        case .rpcError(let code, let message):
            if let code {
                return "MCP error (\(code)): \(message)"
            }
            return "MCP error: \(message)"
        }
    }
}

