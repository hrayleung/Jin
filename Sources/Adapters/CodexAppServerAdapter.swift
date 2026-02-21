import Foundation

/// Codex App Server provider adapter (JSON-RPC over WebSocket).
///
/// This adapter is intentionally configured for server-side built-in tools only.
/// Client-side callback requests (`item/tool/call`, `item/tool/requestUserInput`, approvals)
/// are rejected with a JSON-RPC error response.
actor CodexAppServerAdapter: LLMProviderAdapter {
    struct AccountStatus: Sendable {
        let isAuthenticated: Bool
        let requiresOpenAIAuth: Bool
        let authMode: String?
        let accountType: String?
        let displayName: String?
        let email: String?
    }

    struct ChatGPTLoginChallenge: Sendable {
        let loginID: String
        let authURL: URL
    }

    struct RateLimitStatus: Sendable {
        let name: String
        let usedPercentage: Double?
        let windowMinutes: Int?
        let resetsAt: Date?
    }

    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .vision, .reasoning]

    private let apiKey: String
    private let networkManager: NetworkManager

    init(
        providerConfig: ProviderConfig,
        apiKey: String,
        networkManager: NetworkManager = NetworkManager()
    ) {
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager
    }

    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        _ = streaming // Codex app-server is event-driven; treat all requests as streaming.
        _ = tools // This provider intentionally does not pass client-side tool definitions.

        let endpoint = try resolvedEndpointURL()
        let prompt = makePrompt(from: messages)
        let threadStartParams = makeThreadStartParams(modelID: modelID, controls: controls)

        return AsyncThrowingStream { continuation in
            Task {
                let client = CodexWebSocketRPCClient(url: endpoint)
                let state = CodexStreamState()

                do {
                    try await client.connect()
                    defer {
                        Task { await client.close() }
                    }

                    try await initializeSession(with: client)
                    try await authenticateSession(client)

                    let threadStartResult = try await client.request(
                        method: "thread/start",
                        params: threadStartParams
                    ) { envelope in
                        try await self.handleInterleavedEnvelope(
                            envelope,
                            with: client,
                            continuation: continuation,
                            state: state
                        )
                    }

                    guard let threadID = threadStartResult.objectValue?
                        .string(at: ["thread", "id"]),
                          !threadID.isEmpty else {
                        throw LLMError.decodingError(message: "Codex thread/start did not return thread.id.")
                    }

                    let turnStartParams = makeTurnStartParams(
                        threadID: threadID,
                        prompt: prompt,
                        controls: controls,
                        modelID: modelID
                    )

                    let turnStartResult = try await client.request(
                        method: "turn/start",
                        params: turnStartParams
                    ) { envelope in
                        try await self.handleInterleavedEnvelope(
                            envelope,
                            with: client,
                            continuation: continuation,
                            state: state
                        )
                    }

                    if !state.didEmitMessageStart {
                        let turnID = turnStartResult.objectValue?
                            .string(at: ["turn", "id"])
                            ?? UUID().uuidString
                        state.activeTurnID = turnID
                        continuation.yield(.messageStart(id: turnID))
                        state.didEmitMessageStart = true
                    }

                    while !state.didCompleteTurn {
                        let envelope = try await client.receiveEnvelope()
                        try await handleInterleavedEnvelope(
                            envelope,
                            with: client,
                            continuation: continuation,
                            state: state
                        )
                    }

                    if !state.didEmitMessageEnd {
                        continuation.yield(.messageEnd(usage: state.latestUsage))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            return try await withInitializedClient { client in
                if !trimmed.isEmpty {
                    try await authenticateWithAPIKey(trimmed, client: client)
                    return true
                }

                let status = try await readAccountStatus(using: client, refreshToken: false)
                return status.isAuthenticated
            }
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        try await withInitializedClient { client in
            try await authenticateSession(client)

            var allModels: [ModelInfo] = []
            var cursor: String?

            repeat {
                var params: [String: Any] = [:]
                if let cursor, !cursor.isEmpty {
                    params["cursor"] = cursor
                }

                let result = try await requestWithServerRequestHandling(
                    client: client,
                    method: "model/list",
                    params: params
                )
                guard let object = result.objectValue else {
                    throw LLMError.decodingError(message: "Codex model/list returned unexpected payload.")
                }

                if let data = object.array(at: ["data"]) {
                    for item in data {
                        guard let modelObject = item.objectValue else { continue }
                        let modelID = modelObject.string(at: ["id"]) ?? modelObject.string(at: ["model"]) ?? ""
                        guard !modelID.isEmpty else { continue }

                        let displayName = modelObject.string(at: ["displayName"])
                            ?? modelObject.string(at: ["model"])
                            ?? modelID

                        var caps: ModelCapability = [.streaming]
                        if modelObject.contains(inArray: "image", at: ["inputModalities"]) {
                            caps.insert(.vision)
                        }

                        let supportedEfforts = modelObject.array(at: ["supportedReasoningEfforts"]) ?? []
                        var reasoningConfig: ModelReasoningConfig?
                        if !supportedEfforts.isEmpty {
                            caps.insert(.reasoning)
                            let effort = parseReasoningEffort(modelObject.string(at: ["defaultReasoningEffort"])) ?? .medium
                            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: effort)
                        }

                        allModels.append(
                            ModelInfo(
                                id: modelID,
                                name: displayName,
                                capabilities: caps,
                                contextWindow: 256_000,
                                reasoningConfig: reasoningConfig
                            )
                        )
                    }
                }

                cursor = object.string(at: ["nextCursor"])
            } while cursor != nil

            if allModels.isEmpty {
                return [
                    ModelInfo(
                        id: "gpt-5.1-codex",
                        name: "GPT-5.1 Codex",
                        capabilities: [.streaming, .reasoning],
                        contextWindow: 256_000,
                        reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                    )
                ]
            }

            return allModels.sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }

    func readAccountStatus(refreshToken: Bool = false) async throws -> AccountStatus {
        try await withInitializedClient { client in
            try await readAccountStatus(using: client, refreshToken: refreshToken)
        }
    }

    func readPrimaryRateLimit() async throws -> RateLimitStatus? {
        try await withInitializedClient { client in
            try await authenticateSession(client)

            let result = try await requestWithServerRequestHandling(
                client: client,
                method: "account/rateLimits/read",
                params: nil
            )

            return parsePrimaryRateLimit(from: result)
        }
    }

    func startChatGPTLogin() async throws -> ChatGPTLoginChallenge {
        try await withInitializedClient { client in
            let result = try await requestWithServerRequestHandling(
                client: client,
                method: "account/login/start",
                params: ["type": "chatgpt"]
            )

            guard let object = result.objectValue else {
                throw LLMError.decodingError(message: "Codex account/login/start returned unexpected payload.")
            }

            guard let loginID = object.string(at: ["loginId"]), !loginID.isEmpty else {
                throw LLMError.decodingError(message: "Codex account/login/start did not return loginId.")
            }
            guard let authURLString = object.string(at: ["authUrl"]),
                  let authURL = URL(string: authURLString) else {
                throw LLMError.decodingError(message: "Codex account/login/start did not return a valid authUrl.")
            }

            return ChatGPTLoginChallenge(loginID: loginID, authURL: authURL)
        }
    }

    func cancelChatGPTLogin(loginID: String) async throws {
        let trimmed = loginID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        _ = try await withInitializedClient { client in
            try await requestWithServerRequestHandling(
                client: client,
                method: "account/login/cancel",
                params: ["loginId": trimmed]
            )
        }
    }

    func waitForChatGPTLoginCompletion(
        loginID: String,
        timeoutSeconds: Int = 180
    ) async throws -> AccountStatus {
        let trimmed = loginID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LLMError.invalidRequest(message: "Codex loginId is empty.")
        }

        return try await withInitializedClient { client in
            let timeout = max(timeoutSeconds, 1)
            let deadline = Date().addingTimeInterval(TimeInterval(timeout))

            while Date() < deadline {
                try Task.checkCancellation()
                let status = try await readAccountStatus(using: client, refreshToken: true)
                if status.isAuthenticated {
                    return status
                }

                try await Task.sleep(nanoseconds: 1_000_000_000)
            }

            _ = try? await requestWithServerRequestHandling(
                client: client,
                method: "account/login/cancel",
                params: ["loginId": trimmed]
            )
            throw LLMError.authenticationFailed(message: "Timed out waiting for ChatGPT login. Please try again.")
        }
    }

    func logoutAccount() async throws {
        _ = try await withInitializedClient { client in
            try await requestWithServerRequestHandling(
                client: client,
                method: "account/logout",
                params: nil
            )
        }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        _ = tools
        return [[String: Any]]()
    }

    // MARK: - Account/auth helpers

    private func withInitializedClient<T>(
        _ body: (CodexWebSocketRPCClient) async throws -> T
    ) async throws -> T {
        let endpoint = try resolvedEndpointURL()
        let client = CodexWebSocketRPCClient(url: endpoint)
        try await client.connect()
        defer {
            Task { await client.close() }
        }
        try await initializeSession(with: client)
        return try await body(client)
    }

    private func initializeSession(with client: CodexWebSocketRPCClient) async throws {
        _ = try await requestWithServerRequestHandling(
            client: client,
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "Jin",
                    "version": "0.1.0"
                ],
                "capabilities": NSNull()
            ]
        )
        try await client.notify(method: "initialized", params: nil)
    }

    private func requestWithServerRequestHandling(
        client: CodexWebSocketRPCClient,
        method: String,
        params: [String: Any]?
    ) async throws -> JSONValue {
        try await client.request(method: method, params: params) { envelope in
            guard let requestID = envelope.id,
                  let requestMethod = envelope.method else {
                return
            }

            try await self.handleServerRequest(
                id: requestID,
                method: requestMethod,
                with: client
            )
        }
    }

    private func authenticateSession(_ client: CodexWebSocketRPCClient) async throws {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAPIKey.isEmpty {
            try await authenticateWithAPIKey(trimmedAPIKey, client: client)
            return
        }

        let status = try await readAccountStatus(using: client, refreshToken: false)
        guard status.isAuthenticated else {
            throw LLMError.authenticationFailed(
                message: "Codex App Server is not logged in to ChatGPT. Open provider settings and connect your ChatGPT account."
            )
        }
    }

    private func authenticateWithAPIKey(_ key: String, client: CodexWebSocketRPCClient) async throws {
        do {
            _ = try await requestWithServerRequestHandling(
                client: client,
                method: "account/login/start",
                params: [
                    "type": "apiKey",
                    "apiKey": key
                ]
            )
        } catch {
            guard shouldFallbackToLegacyLogin(error) else {
                throw error
            }
            _ = try await requestWithServerRequestHandling(
                client: client,
                method: "loginApiKey",
                params: ["apiKey": key]
            )
        }
    }

    private func readAccountStatus(
        using client: CodexWebSocketRPCClient,
        refreshToken: Bool
    ) async throws -> AccountStatus {
        let result = try await requestWithServerRequestHandling(
            client: client,
            method: "account/read",
            params: ["refreshToken": refreshToken]
        )
        return try parseAccountStatus(from: result)
    }

    private func parseAccountStatus(from result: JSONValue) throws -> AccountStatus {
        guard let object = result.objectValue else {
            throw LLMError.decodingError(message: "Codex account/read returned unexpected payload.")
        }

        let authMode = object.string(at: ["authMode"])
        let requiresOpenAIAuth = object.bool(at: ["requiresOpenaiAuth"])
            ?? object.bool(at: ["requiresOpenAIAuth"])
            ?? false
        let account = object.object(at: ["account"])

        let accountType = account?.string(at: ["type"]) ?? authMode
        let displayName = account?.string(at: ["name"])
            ?? account?.string(at: ["displayName"])
            ?? account?.string(at: ["username"])
        let email = account?.string(at: ["email"])

        return AccountStatus(
            isAuthenticated: account != nil,
            requiresOpenAIAuth: requiresOpenAIAuth,
            authMode: authMode,
            accountType: accountType,
            displayName: displayName,
            email: email
        )
    }

    private func parsePrimaryRateLimit(from result: JSONValue) -> RateLimitStatus? {
        guard let object = result.objectValue else { return nil }

        let rootRateLimit = object.object(at: ["rateLimit"])
            ?? object.object(at: ["primary"])
            ?? object.object(at: ["rateLimits", "primary"])
        let arrayRateLimit = object.array(at: ["rateLimits"])?.first?.objectValue
            ?? object.array(at: ["limits"])?.first?.objectValue
        guard let rateLimit = rootRateLimit ?? arrayRateLimit else {
            return nil
        }

        let name = rateLimit.string(at: ["name"])
            ?? rateLimit.string(at: ["id"])
            ?? "primary"
        let usedPercentage = rateLimit.double(at: ["usedPercentage"])
            ?? rateLimit.double(at: ["usedPercent"])
            ?? rateLimit.double(at: ["percentUsed"])
        let windowMinutes = rateLimit.int(at: ["windowMinutes"])
            ?? rateLimit.int(at: ["windowMins"])
        let resetsAt = parseDate(rateLimit.string(at: ["resetsAt"])
            ?? rateLimit.string(at: ["resetAt"])
            ?? rateLimit.string(at: ["resetTime"]))

        return RateLimitStatus(
            name: name,
            usedPercentage: usedPercentage,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt
        )
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: raw) {
            return parsed
        }

        let fallback = ISO8601DateFormatter()
        return fallback.date(from: raw)
    }

    private func shouldFallbackToLegacyLogin(_ error: Error) -> Bool {
        guard case let LLMError.providerError(code, message) = error else {
            return false
        }

        if code == "-32601" {
            return true
        }
        let lower = message.lowercased()
        return lower.contains("not found") || lower.contains("unknown method")
    }

    // MARK: - Internal event handling

    private func handleInterleavedEnvelope(
        _ envelope: JSONRPCEnvelope,
        with client: CodexWebSocketRPCClient,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        state: CodexStreamState
    ) async throws {
        if let method = envelope.method {
            if let requestID = envelope.id {
                try await handleServerRequest(
                    id: requestID,
                    method: method,
                    with: client
                )
                return
            }

            guard let params = envelope.params?.objectValue else {
                if method == "turn/completed" {
                    if !state.didEmitMessageEnd {
                        if !state.didEmitMessageStart {
                            let startID = state.activeTurnID ?? UUID().uuidString
                            continuation.yield(.messageStart(id: startID))
                            state.didEmitMessageStart = true
                        }
                        continuation.yield(.messageEnd(usage: state.latestUsage))
                        state.didEmitMessageEnd = true
                    }
                    state.didCompleteTurn = true
                }
                return
            }

            switch method {
            case "turn/started":
                let turnID = params.string(at: ["turn", "id"]) ?? UUID().uuidString
                state.activeTurnID = turnID
                if !state.didEmitMessageStart {
                    continuation.yield(.messageStart(id: turnID))
                    state.didEmitMessageStart = true
                }

            case "item/agentMessage/delta":
                if !state.didEmitMessageStart {
                    let turnID = params.string(at: ["turnId"]) ?? state.activeTurnID ?? UUID().uuidString
                    state.activeTurnID = turnID
                    continuation.yield(.messageStart(id: turnID))
                    state.didEmitMessageStart = true
                }

                if let delta = params.string(at: ["delta"]), !delta.isEmpty {
                    continuation.yield(.contentDelta(.text(delta)))
                    state.didEmitAssistantText = true
                }

            case "item/reasoning/textDelta", "item/reasoning/summaryTextDelta":
                if let delta = params.string(at: ["delta"]), !delta.isEmpty {
                    continuation.yield(.thinkingDelta(.thinking(textDelta: delta, signature: nil)))
                }

            case "item/completed":
                if let item = params.object(at: ["item"]),
                   item.string(at: ["type"]) == "agentMessage",
                   let text = item.string(at: ["text"]),
                   !text.isEmpty,
                   !state.didEmitAssistantText {
                    if !state.didEmitMessageStart {
                        let turnID = params.string(at: ["turnId"]) ?? state.activeTurnID ?? UUID().uuidString
                        state.activeTurnID = turnID
                        continuation.yield(.messageStart(id: turnID))
                        state.didEmitMessageStart = true
                    }

                    continuation.yield(.contentDelta(.text(text)))
                    state.didEmitAssistantText = true
                }

            case "thread/tokenUsage/updated":
                if let usage = parseUsage(from: params.object(at: ["tokenUsage", "last"])) {
                    state.latestUsage = usage
                }

            case "turn/completed":
                let status = params.string(at: ["turn", "status"])?.lowercased()
                if status == "failed" {
                    let message = params.string(at: ["turn", "error", "message"])
                        ?? "Codex turn failed."
                    throw LLMError.providerError(code: "turn_failed", message: message)
                }

                if !state.didEmitMessageStart {
                    let turnID = params.string(at: ["turn", "id"]) ?? state.activeTurnID ?? UUID().uuidString
                    state.activeTurnID = turnID
                    continuation.yield(.messageStart(id: turnID))
                    state.didEmitMessageStart = true
                }

                if !state.didEmitMessageEnd {
                    continuation.yield(.messageEnd(usage: state.latestUsage))
                    state.didEmitMessageEnd = true
                }
                state.didCompleteTurn = true

            case "error":
                let message = params.string(at: ["error", "message"])
                    ?? params.string(at: ["message"])
                    ?? "Codex app-server returned an error notification."
                let willRetry = params.bool(at: ["willRetry"]) ?? false

                // `error` notifications may represent transient stream hiccups while Codex is
                // retrying in the background (for example "Reconnecting... 1/5").
                // Surface only terminal errors to the chat UI.
                if willRetry || message.lowercased().contains("reconnecting") {
                    break
                }
                throw LLMError.providerError(code: "codex_event_error", message: message)

            default:
                break
            }
        }
    }

    private func handleServerRequest(
        id: JSONRPCID,
        method: String,
        with client: CodexWebSocketRPCClient
    ) async throws {
        let message: String
        switch method {
        case "item/tool/call", "item/tool/requestUserInput":
            message = "Client callbacks are disabled for this Codex App Server provider."
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval", "applyPatchApproval", "execCommandApproval":
            message = "Interactive approval callbacks are disabled for this Codex App Server provider."
        default:
            message = "Unsupported server request method: \(method)"
        }

        try await client.respondWithError(
            id: id,
            code: -32601,
            message: message
        )
    }

    // MARK: - Request builders

    private func makeThreadStartParams(modelID: String, controls: GenerationControls) -> [String: Any] {
        var params: [String: Any] = [
            "model": modelID,
            "experimentalRawEvents": false,
            "persistExtendedHistory": false
        ]

        if let cwd = providerString(key: "codex_cwd", controls: controls) ?? providerString(key: "cwd", controls: controls) {
            params["cwd"] = cwd
        }
        if let approval = providerString(key: "codex_approval_policy", controls: controls) {
            params["approvalPolicy"] = approval
        }
        if let sandboxMode = providerSpecificValue(key: "codex_sandbox_mode", controls: controls) {
            params["sandbox"] = sandboxMode
        }
        if let personality = providerString(key: "codex_personality", controls: controls) {
            params["personality"] = personality
        }
        if let baseInstructions = providerString(key: "codex_base_instructions", controls: controls) {
            params["baseInstructions"] = baseInstructions
        }
        if let developerInstructions = providerString(key: "codex_developer_instructions", controls: controls) {
            params["developerInstructions"] = developerInstructions
        }

        return params
    }

    private func makeTurnStartParams(
        threadID: String,
        prompt: String,
        controls: GenerationControls,
        modelID: String
    ) -> [String: Any] {
        var params: [String: Any] = [
            "threadId": threadID,
            "input": [
                [
                    "type": "text",
                    "text": prompt,
                    "text_elements": [Any]()
                ]
            ],
            "model": modelID
        ]

        if let cwd = providerString(key: "codex_cwd", controls: controls) ?? providerString(key: "cwd", controls: controls) {
            params["cwd"] = cwd
        }
        if let approval = providerString(key: "codex_approval_policy", controls: controls) {
            params["approvalPolicy"] = approval
        }
        if let sandboxPolicy = providerSpecificValue(key: "codex_sandbox_policy", controls: controls) {
            params["sandboxPolicy"] = sandboxPolicy
        }
        if let personality = providerString(key: "codex_personality", controls: controls) {
            params["personality"] = personality
        }
        if let schema = providerSpecificValue(key: "codex_output_schema", controls: controls)
            ?? providerSpecificValue(key: "output_schema", controls: controls) {
            params["outputSchema"] = schema
        }

        if let reasoning = controls.reasoning, reasoning.enabled {
            let effort = reasoning.effort ?? .medium
            params["effort"] = effort.rawValue
            if let summary = reasoning.summary {
                params["summary"] = summary.rawValue
            }
        }

        return params
    }

    // MARK: - Helpers

    private func resolvedEndpointURL() throws -> URL {
        let fallback = ProviderType.codexAppServer.defaultBaseURL ?? "ws://127.0.0.1:4500"
        let raw = (providerConfig.baseURL ?? fallback)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            throw LLMError.invalidRequest(message: "Codex App Server base URL is empty.")
        }

        let normalized: String
        if raw.hasPrefix("ws://") || raw.hasPrefix("wss://") {
            normalized = raw
        } else if raw.hasPrefix("http://") {
            normalized = "ws://\(raw.dropFirst("http://".count))"
        } else if raw.hasPrefix("https://") {
            normalized = "wss://\(raw.dropFirst("https://".count))"
        } else {
            normalized = "ws://\(raw)"
        }

        guard let url = URL(string: normalized) else {
            throw LLMError.invalidRequest(message: "Invalid Codex App Server URL: \(raw)")
        }
        return url
    }

    private func makePrompt(from messages: [Message]) -> String {
        let rendered = messages
            .map { message in
                let role: String
                switch message.role {
                case .system:
                    role = "System"
                case .user:
                    role = "User"
                case .assistant:
                    role = "Assistant"
                case .tool:
                    role = "Tool"
                }

                let content = message.content.compactMap { part -> String? in
                    switch part {
                    case .text(let text):
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? nil : trimmed
                    case .thinking(let block):
                        let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? nil : "[Thinking] \(trimmed)"
                    case .redactedThinking:
                        return "[Thinking redacted]"
                    case .image(let image):
                        if let url = image.url?.absoluteString {
                            return "[Image] \(url)"
                        }
                        return "[Image attachment]"
                    case .video(let video):
                        if let url = video.url?.absoluteString {
                            return "[Video] \(url)"
                        }
                        return "[Video attachment]"
                    case .file(let file):
                        return "[File] \(file.filename)"
                    case .audio:
                        return "[Audio attachment]"
                    }
                }.joined(separator: "\n")

                if content.isEmpty {
                    return "\(role):"
                }
                return "\(role):\n\(content)"
            }
            .joined(separator: "\n\n")

        let trimmed = rendered.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Continue."
        }
        return trimmed
    }

    private func parseUsage(from dict: [String: JSONValue]?) -> Usage? {
        guard let dict else { return nil }

        let input = dict.int(at: ["inputTokens"]) ?? 0
        let output = dict.int(at: ["outputTokens"]) ?? 0
        let reasoning = dict.int(at: ["reasoningOutputTokens"])
        let cached = dict.int(at: ["cachedInputTokens"])

        return Usage(
            inputTokens: input,
            outputTokens: output,
            thinkingTokens: reasoning,
            cachedTokens: cached
        )
    }

    private func parseReasoningEffort(_ raw: String?) -> ReasoningEffort? {
        guard let raw else { return nil }
        return ReasoningEffort(rawValue: raw.lowercased())
    }

    private func providerSpecificValue(key: String, controls: GenerationControls) -> Any? {
        controls.providerSpecific[key]?.value
    }

    private func providerString(key: String, controls: GenerationControls) -> String? {
        guard let value = controls.providerSpecific[key]?.value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// WebSocket RPC client, stream state, and JSON helpers are in CodexWebSocketRPCClient.swift
