import Foundation
import Network

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
    private static let fallbackContextWindow = 256_000

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
                    continuation.finish(
                        throwing: Self.remapCodexConnectivityError(error, endpoint: endpoint)
                    )
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
                        guard let modelInfo = Self.makeModelInfo(from: modelObject) else { continue }
                        allModels.append(modelInfo)
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
                        contextWindow: Self.fallbackContextWindow,
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
        do {
            try await client.connect()
            defer {
                Task { await client.close() }
            }
            try await initializeSession(with: client)
            return try await body(client)
        } catch {
            throw Self.remapCodexConnectivityError(error, endpoint: endpoint)
        }
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

            case "item/started":
                guard let item = params.object(at: ["item"]) else { break }
                if let activity = Self.searchActivityFromCodexItem(
                    item: item,
                    method: method,
                    params: params,
                    fallbackTurnID: state.activeTurnID
                ) {
                    continuation.yield(.searchActivity(activity))
                }
                if let toolActivity = Self.codexToolActivityFromCodexItem(
                    item: item,
                    method: method,
                    params: params,
                    fallbackTurnID: state.activeTurnID
                ) {
                    continuation.yield(.codexToolActivity(toolActivity))
                }

            case "item/agentMessage/delta":
                if let delta = params.string(at: ["delta"]), !delta.isEmpty {
                    emitAssistantText(
                        delta,
                        params: params,
                        continuation: continuation,
                        state: state
                    )
                }

            case "item/reasoning/textDelta", "item/reasoning/summaryTextDelta":
                if let delta = params.string(at: ["delta"]), !delta.isEmpty {
                    continuation.yield(.thinkingDelta(.thinking(textDelta: delta, signature: nil)))
                }

            case "item/reasoning/summaryPartAdded":
                if let delta = params.string(at: ["part", "text"]) ?? params.string(at: ["text"]),
                   !delta.isEmpty {
                    continuation.yield(.thinkingDelta(.thinking(textDelta: delta, signature: nil)))
                }

            case "item/completed":
                guard let item = params.object(at: ["item"]) else { break }

                let itemType = item.string(at: ["type"]) ?? ""
                if itemType == "agentMessage",
                   let completedText = Self.parseAgentMessageText(from: item) {
                    emitAssistantTextSnapshot(
                        completedText,
                        params: params,
                        continuation: continuation,
                        state: state
                    )
                }

                // Compatibility: newer app-server versions can return multimodal dynamic tool outputs.
                // Surface them in the stream so users can still see text/image tool results.
                if itemType == "dynamicToolCall" {
                    for part in Self.parseDynamicToolCallOutputParts(from: item) {
                        if case .text(let text) = part {
                            state.assistantTextBuffer.append(text)
                            state.didEmitAssistantText = true
                        }
                        continuation.yield(.contentDelta(part))
                    }
                    if let activity = Self.searchActivityFromDynamicToolCall(
                        item: item,
                        method: method,
                        params: params,
                            fallbackTurnID: state.activeTurnID
                    ) {
                        continuation.yield(.searchActivity(activity))
                    }
                    if let toolActivity = Self.codexToolActivityFromDynamicToolCall(
                        item: item,
                        method: method,
                        params: params,
                        fallbackTurnID: state.activeTurnID
                    ) {
                        continuation.yield(.codexToolActivity(toolActivity))
                    }
                }

                if let activity = Self.searchActivityFromCodexItem(
                    item: item,
                    method: method,
                    params: params,
                    fallbackTurnID: state.activeTurnID
                ) {
                    continuation.yield(.searchActivity(activity))
                }
                if let toolActivity = Self.codexToolActivityFromCodexItem(
                    item: item,
                    method: method,
                    params: params,
                    fallbackTurnID: state.activeTurnID
                ) {
                    continuation.yield(.codexToolActivity(toolActivity))
                }

            case "item/updated":
                guard let item = params.object(at: ["item"]) else { break }
                let itemType = item.string(at: ["type"]) ?? ""
                if itemType == "agentMessage",
                   let snapshotText = Self.parseAgentMessageText(from: item) {
                    emitAssistantTextSnapshot(
                        snapshotText,
                        params: params,
                        continuation: continuation,
                        state: state
                    )
                } else if let activity = Self.searchActivityFromCodexItem(
                    item: item,
                    method: method,
                    params: params,
                    fallbackTurnID: state.activeTurnID
                ) {
                    continuation.yield(.searchActivity(activity))
                }
                if let toolActivity = Self.codexToolActivityFromCodexItem(
                    item: item,
                    method: method,
                    params: params,
                    fallbackTurnID: state.activeTurnID
                ) {
                    continuation.yield(.codexToolActivity(toolActivity))
                }

            case let dynamicToolMethod where dynamicToolMethod.hasPrefix("item/dynamicToolCall/"):
                var item = params.object(at: ["item"]) ?? params
                if item.string(at: ["type"]) == nil {
                    item["type"] = .string("dynamicToolCall")
                }
                if let activity = Self.searchActivityFromCodexItem(
                    item: item,
                    method: dynamicToolMethod,
                    params: params,
                    fallbackTurnID: state.activeTurnID
                ) {
                    continuation.yield(.searchActivity(activity))
                }
                if let toolActivity = Self.codexToolActivityFromCodexItem(
                    item: item,
                    method: dynamicToolMethod,
                    params: params,
                    fallbackTurnID: state.activeTurnID
                ) {
                    continuation.yield(.codexToolActivity(toolActivity))
                }

            case let itemSubMethod where itemSubMethod.hasPrefix("item/commandExecution/")
                || itemSubMethod.hasPrefix("item/fileChange/")
                || itemSubMethod.hasPrefix("item/mcpToolCall/")
                || itemSubMethod.hasPrefix("item/collabToolCall/"):
                let item = params.object(at: ["item"]) ?? params
                if let toolActivity = Self.codexToolActivityFromCodexItem(
                    item: item,
                    method: itemSubMethod,
                    params: params,
                    fallbackTurnID: state.activeTurnID
                ) {
                    continuation.yield(.codexToolActivity(toolActivity))
                }

            case "thread/tokenUsage/updated":
                if let usage = parseUsage(from: params.object(at: ["tokenUsage", "last"])) {
                    state.latestUsage = usage
                }

            case "model/rerouted":
                // Compatibility no-op for newer app-server notifications.
                // We keep streaming behavior unchanged while tolerating reroute events.
                break

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

    private func emitAssistantText(
        _ text: String,
        params: [String: JSONValue],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        state: CodexStreamState
    ) {
        guard !text.isEmpty else { return }
        ensureMessageStartIfNeeded(params: params, continuation: continuation, state: state)
        continuation.yield(.contentDelta(.text(text)))
        state.assistantTextBuffer.append(text)
        state.didEmitAssistantText = true
    }

    private func emitAssistantTextSnapshot(
        _ snapshot: String,
        params: [String: JSONValue],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        state: CodexStreamState
    ) {
        guard let delta = Self.assistantTextSuffix(fromSnapshot: snapshot, emitted: state.assistantTextBuffer) else {
            return
        }
        emitAssistantText(delta, params: params, continuation: continuation, state: state)
    }

    private func ensureMessageStartIfNeeded(
        params: [String: JSONValue],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        state: CodexStreamState
    ) {
        guard !state.didEmitMessageStart else { return }
        let turnID = params.string(at: ["turnId"]) ?? params.string(at: ["turn", "id"]) ?? state.activeTurnID ?? UUID().uuidString
        state.activeTurnID = turnID
        continuation.yield(.messageStart(id: turnID))
        state.didEmitMessageStart = true
    }

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

    nonisolated static func makeModelInfo(from modelObject: [String: JSONValue]) -> ModelInfo? {
        let modelID = trimmedValue(
            modelObject.string(at: ["id"])
                ?? modelObject.string(at: ["model"])
        )
        guard let modelID else { return nil }

        let displayName = trimmedValue(
            modelObject.string(at: ["displayName"])
                ?? modelObject.string(at: ["model"])
        ) ?? modelID

        var capabilities: ModelCapability = [.streaming]
        if modelObject.contains(inArray: "image", at: ["inputModalities"]) {
            capabilities.insert(.vision)
        }

        let supportedEfforts = parseSupportedReasoningEfforts(from: modelObject)
        var reasoningConfig: ModelReasoningConfig?
        if !supportedEfforts.isEmpty {
            capabilities.insert(.reasoning)
            let defaultEffort = parseReasoningEffort(modelObject.string(at: ["defaultReasoningEffort"]))
                ?? supportedEfforts.first
                ?? .medium
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: defaultEffort)
        }

        let contextWindow = firstPositiveInt(
            from: modelObject,
            candidatePaths: [
                ["contextWindow"],
                ["contextLength"],
                ["context_window"],
                ["context_length"]
            ]
        ) ?? fallbackContextWindow

        let catalogMetadata = parseCatalogMetadata(from: modelObject)

        return ModelInfo(
            id: modelID,
            name: displayName,
            capabilities: capabilities,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig,
            catalogMetadata: catalogMetadata
        )
    }

    private nonisolated static func parseDynamicToolCallOutputParts(
        from item: [String: JSONValue]
    ) -> [ContentPart] {
        guard let contentItems = item.array(at: ["contentItems"]), !contentItems.isEmpty else {
            return []
        }

        var parts: [ContentPart] = []
        parts.reserveCapacity(contentItems.count)

        for contentItem in contentItems {
            guard let object = contentItem.objectValue else { continue }
            let type = object.string(at: ["type"])?.lowercased()
            switch type {
            case "inputtext", "input_text":
                if let text = trimmedValue(object.string(at: ["text"])), !text.isEmpty {
                    parts.append(.text(text))
                }

            case "inputimage", "input_image":
                let rawURL = trimmedValue(object.string(at: ["imageUrl"]) ?? object.string(at: ["image_url"]))
                if let rawURL, let url = URL(string: rawURL) {
                    parts.append(.image(ImageContent(mimeType: "image/png", url: url)))
                }

            default:
                break
            }
        }

        return parts
    }

    nonisolated static func searchActivityFromCodexItem(
        item: [String: JSONValue],
        method: String,
        params: [String: JSONValue],
        fallbackTurnID: String?
    ) -> SearchActivity? {
        let itemType = item.string(at: ["type"]) ?? ""
        if itemType == "webSearch" {
            return searchActivityFromWebSearchItem(item: item, method: method)
        }
        if itemType == "dynamicToolCall" {
            return searchActivityFromDynamicToolCall(
                item: item,
                method: method,
                params: params,
                fallbackTurnID: fallbackTurnID
            )
        }
        return nil
    }

    private nonisolated static func searchActivityFromWebSearchItem(
        item: [String: JSONValue],
        method: String
    ) -> SearchActivity? {
        guard item.string(at: ["type"]) == "webSearch" else { return nil }
        let id = trimmedValue(item.string(at: ["id"])) ?? UUID().uuidString

        var arguments: [String: AnyCodable] = [:]
        var queries: [String] = []
        var seenQueries = Set<String>()

        func appendQuery(_ raw: String?) {
            guard let query = trimmedValue(raw) else { return }
            let key = query.lowercased()
            guard seenQueries.insert(key).inserted else { return }
            queries.append(query)
        }

        appendQuery(item.string(at: ["query"]))
        if let action = item.object(at: ["action"]) {
            appendQuery(action.string(at: ["query"]))
            for queryValue in action.array(at: ["queries"]) ?? [] {
                appendQuery(queryValue.stringValue)
            }
            if let url = trimmedValue(action.string(at: ["url"])) {
                arguments["url"] = AnyCodable(url)
            }
            if let pattern = trimmedValue(action.string(at: ["pattern"])) {
                arguments["pattern"] = AnyCodable(pattern)
            }
            if let actionType = trimmedValue(action.string(at: ["type"])) {
                arguments["action_type"] = AnyCodable(actionType)
            }
        }

        if let firstQuery = queries.first {
            arguments["query"] = AnyCodable(firstQuery)
            arguments["queries"] = AnyCodable(queries)
        }

        let status: SearchActivityStatus
        if method == "item/completed" || method.hasSuffix("/completed") {
            status = .completed
        } else if method.hasSuffix("/failed") {
            status = .failed
        } else {
            status = .searching
        }

        return SearchActivity(
            id: id,
            type: "web_search_call",
            status: status,
            arguments: arguments
        )
    }

    nonisolated static func searchActivityFromDynamicToolCall(
        item: [String: JSONValue],
        method: String,
        params: [String: JSONValue],
        fallbackTurnID: String?
    ) -> SearchActivity? {
        guard let toolName = dynamicToolCallName(from: item),
              isLikelyWebSearchTool(named: toolName) else {
            return nil
        }

        let id = dynamicToolCallID(from: item, params: params, fallbackTurnID: fallbackTurnID, toolName: toolName)
        let status = dynamicToolCallSearchStatus(from: item, method: method)
        let arguments = dynamicToolCallSearchArguments(from: item)

        return SearchActivity(
            id: id,
            type: "web_search_call",
            status: status,
            arguments: arguments,
            outputIndex: item.int(at: ["outputIndex"]) ?? params.int(at: ["outputIndex"]),
            sequenceNumber: item.int(at: ["sequenceNumber"]) ?? params.int(at: ["sequenceNumber"])
        )
    }

    // MARK: - Codex Tool Activity Parsing

    /// Creates a `CodexToolActivity` from a `dynamicToolCall` item, excluding web-search tools
    /// (those are handled by `searchActivityFromDynamicToolCall`).
    nonisolated static func codexToolActivityFromDynamicToolCall(
        item: [String: JSONValue],
        method: String,
        params: [String: JSONValue],
        fallbackTurnID: String?
    ) -> CodexToolActivity? {
        guard let toolName = dynamicToolCallName(from: item) else {
            return nil
        }
        // Web-search tools are rendered in the SearchActivityTimelineView, not here.
        guard !isLikelyWebSearchTool(named: toolName) else {
            return nil
        }

        let id = codexToolActivityID(from: item, params: params, fallbackTurnID: fallbackTurnID, toolName: toolName)
        let status = codexToolActivityStatus(from: item, method: method)
        let arguments = codexToolActivityArguments(from: item)
        let output = codexToolActivityOutput(from: item)

        return CodexToolActivity(
            id: id,
            toolName: toolName,
            status: status,
            arguments: arguments,
            output: output
        )
    }

    /// Dispatches to the appropriate codex tool activity parser based on item type.
    /// Returns `nil` for non-tool item types (webSearch, agentMessage, reasoning, etc.).
    nonisolated static func codexToolActivityFromCodexItem(
        item: [String: JSONValue],
        method: String,
        params: [String: JSONValue],
        fallbackTurnID: String?
    ) -> CodexToolActivity? {
        let itemType = item.string(at: ["type"]) ?? ""

        // Item types that are NOT tool executions.
        let nonToolTypes: Set<String> = [
            "webSearch",
            "agentMessage",
            "reasoning",
            "enteredReviewMode",
            "exitedReviewMode",
            "contextCompaction",
            ""
        ]
        if nonToolTypes.contains(itemType) {
            return nil
        }

        if itemType == "dynamicToolCall" {
            return codexToolActivityFromDynamicToolCall(
                item: item,
                method: method,
                params: params,
                fallbackTurnID: fallbackTurnID
            )
        }

        // Handle other tool-like item types: commandExecution, fileChange,
        // mcpToolCall, collabToolCall, imageView, etc.
        return codexToolActivityFromGenericItem(
            item: item,
            itemType: itemType,
            method: method,
            params: params,
            fallbackTurnID: fallbackTurnID
        )
    }

    /// Parses a `CodexToolActivity` from non-dynamicToolCall item types such as
    /// `commandExecution`, `fileChange`, `mcpToolCall`, `collabToolCall`, `imageView`, etc.
    private nonisolated static func codexToolActivityFromGenericItem(
        item: [String: JSONValue],
        itemType: String,
        method: String,
        params: [String: JSONValue],
        fallbackTurnID: String?
    ) -> CodexToolActivity? {
        let id = codexToolActivityID(
            from: item,
            params: params,
            fallbackTurnID: fallbackTurnID,
            toolName: itemType
        )

        let toolName = genericItemToolName(item: item, itemType: itemType)
        let status = codexToolActivityStatus(from: item, method: method)
        let arguments = genericItemArguments(item: item, itemType: itemType)
        let output = genericItemOutput(item: item, itemType: itemType)

        return CodexToolActivity(
            id: id,
            toolName: toolName,
            status: status,
            arguments: arguments,
            output: output
        )
    }

    /// Derives a human-readable tool name from the item type and its content.
    private nonisolated static func genericItemToolName(
        item: [String: JSONValue],
        itemType: String
    ) -> String {
        switch itemType {
        case "commandExecution":
            return trimmedValue(item.string(at: ["command"]))
                .map { cmd in
                    let first = cmd.components(separatedBy: .whitespaces).first ?? cmd
                    return first.count > 40 ? String(first.prefix(37)) + "..." : first
                }
                ?? "shell"
        case "fileChange":
            if let changes = item.array(at: ["changes"]),
               let firstPath = changes.first?.objectValue?.string(at: ["path"]) {
                let filename = (firstPath as NSString).lastPathComponent
                let kind = changes.first?.objectValue?.string(at: ["kind"]) ?? "edit"
                return "\(kind): \(filename)"
            }
            return "file change"
        case "mcpToolCall":
            if let server = trimmedValue(item.string(at: ["server"])),
               let tool = trimmedValue(item.string(at: ["tool"])) {
                return "\(server)/\(tool)"
            }
            return trimmedValue(item.string(at: ["tool"])) ?? "mcp tool"
        case "collabToolCall":
            return trimmedValue(item.string(at: ["tool"])) ?? "collab tool"
        case "imageView":
            return "image view"
        default:
            // Use the tool/name field if present, otherwise fall back to the item type.
            return trimmedValue(
                item.string(at: ["tool"])
                    ?? item.string(at: ["name"])
                    ?? item.string(at: ["tool", "name"])
            ) ?? itemType
        }
    }

    /// Extracts arguments from non-dynamicToolCall items.
    private nonisolated static func genericItemArguments(
        item: [String: JSONValue],
        itemType: String
    ) -> [String: AnyCodable] {
        var arguments: [String: AnyCodable] = [:]

        switch itemType {
        case "commandExecution":
            if let command = trimmedValue(item.string(at: ["command"])) {
                arguments["command"] = AnyCodable(command)
            }
            if let cwd = trimmedValue(item.string(at: ["cwd"])) {
                arguments["cwd"] = AnyCodable(cwd)
            }
            if let exitCode = item.int(at: ["exitCode"]) {
                arguments["exitCode"] = AnyCodable(exitCode)
            }

        case "fileChange":
            if let changes = item.array(at: ["changes"]) {
                var paths: [String] = []
                for change in changes {
                    if let obj = change.objectValue,
                       let path = trimmedValue(obj.string(at: ["path"])) {
                        paths.append(path)
                    }
                }
                if !paths.isEmpty {
                    arguments["paths"] = AnyCodable(paths)
                }
            }

        case "mcpToolCall":
            if let server = trimmedValue(item.string(at: ["server"])) {
                arguments["server"] = AnyCodable(server)
            }
            if let tool = trimmedValue(item.string(at: ["tool"])) {
                arguments["tool"] = AnyCodable(tool)
            }
            if let argsObj = item.object(at: ["arguments"]) {
                for (key, value) in argsObj {
                    arguments[key] = AnyCodable(jsonValueToAny(value))
                }
            }

        case "collabToolCall":
            if let tool = trimmedValue(item.string(at: ["tool"])) {
                arguments["tool"] = AnyCodable(tool)
            }
            if let prompt = trimmedValue(item.string(at: ["prompt"])) {
                arguments["prompt"] = AnyCodable(prompt)
            }

        case "imageView":
            if let path = trimmedValue(item.string(at: ["path"])) {
                arguments["path"] = AnyCodable(path)
            }

        default:
            // Generic fallback: try arguments/input objects, then common top-level keys.
            if let argsObj = item.object(at: ["arguments"]) {
                for (key, value) in argsObj {
                    arguments[key] = AnyCodable(jsonValueToAny(value))
                }
            } else if let inputObj = item.object(at: ["input"]) {
                for (key, value) in inputObj {
                    arguments[key] = AnyCodable(jsonValueToAny(value))
                }
            }
            for key in ["command", "path", "file", "tool", "query"] {
                if arguments[key] == nil, let value = item.string(at: [key]) {
                    arguments[key] = AnyCodable(value)
                }
            }
        }

        return arguments
    }

    /// Extracts output text from non-dynamicToolCall items.
    private nonisolated static func genericItemOutput(
        item: [String: JSONValue],
        itemType: String
    ) -> String? {
        switch itemType {
        case "commandExecution":
            return trimmedValue(item.string(at: ["aggregatedOutput"]))
                ?? trimmedValue(item.string(at: ["output"]))
        case "fileChange":
            // File changes typically don't have textual output.
            return nil
        case "mcpToolCall":
            return trimmedValue(item.string(at: ["result"]))
                ?? trimmedValue(item.string(at: ["error"]))
        default:
            return codexToolActivityOutput(from: item)
        }
    }

    private nonisolated static func codexToolActivityID(
        from item: [String: JSONValue],
        params: [String: JSONValue],
        fallbackTurnID: String?,
        toolName: String
    ) -> String {
        if let explicitID = trimmedValue(
            item.string(at: ["id"])
                ?? item.string(at: ["callId"])
                ?? item.string(at: ["toolCallId"])
                ?? params.string(at: ["itemId"])
        ) {
            return explicitID
        }

        let turnID = trimmedValue(
            params.string(at: ["turnId"])
                ?? params.string(at: ["turn", "id"])
                ?? fallbackTurnID
        ) ?? "unknown_turn"

        var fallbackID = "codex_tool_\(turnID)_\(toolName.lowercased())"
        if let suffix = toolActivityFallbackSuffix(from: item, params: params) {
            fallbackID += "_\(suffix)"
        }
        return fallbackID
    }

    private nonisolated static func codexToolActivityStatus(
        from item: [String: JSONValue],
        method: String
    ) -> CodexToolActivityStatus {
        if method == "item/completed" || method.hasSuffix("/completed") {
            return .completed
        }
        if method.hasSuffix("/failed") {
            return .failed
        }
        if method.hasSuffix("/started") || method == "item/started" {
            return .running
        }
        // Sub-notifications like outputDelta, requestApproval indicate running.
        if method.hasSuffix("/outputDelta") || method.hasSuffix("/requestApproval") {
            return .running
        }

        if let rawStatus = trimmedValue(item.string(at: ["status"]) ?? item.string(at: ["state"])) {
            let normalized = rawStatus
                .replacingOccurrences(
                    of: "([a-z0-9])([A-Z])",
                    with: "$1_$2",
                    options: .regularExpression
                )
                .lowercased()
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
            // Map Codex-specific statuses.
            if normalized == "in_progress" || normalized == "inprogress" {
                return .running
            }
            if normalized == "declined" {
                return .failed
            }
            return CodexToolActivityStatus(rawValue: normalized)
        }
        return .running
    }

    private nonisolated static func codexToolActivityArguments(from item: [String: JSONValue]) -> [String: AnyCodable] {
        var arguments: [String: AnyCodable] = [:]

        // Extract from explicit "arguments" or "input" objects.
        if let argsObj = item.object(at: ["arguments"]) {
            for (key, value) in argsObj {
                arguments[key] = AnyCodable(jsonValueToAny(value))
            }
        } else if let inputObj = item.object(at: ["input"]) {
            for (key, value) in inputObj {
                arguments[key] = AnyCodable(jsonValueToAny(value))
            }
        }

        // Fallback: pick up common top-level keys.
        for key in ["command", "cmd", "path", "file", "filePath", "file_path", "query", "content"] {
            if arguments[key] == nil, let value = item.string(at: [key]) {
                arguments[key] = AnyCodable(value)
            }
        }

        return arguments
    }

    private nonisolated static func jsonValueToAny(_ value: JSONValue) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let b):
            return b
        case .number(let n):
            return n
        case .string(let s):
            return s
        case .array(let arr):
            return arr.map { jsonValueToAny($0) }
        case .object(let obj):
            return obj.mapValues { jsonValueToAny($0) }
        }
    }

    private nonisolated static func codexToolActivityOutput(from item: [String: JSONValue]) -> String? {
        if let output = trimmedValue(item.string(at: ["output"])) {
            return output
        }
        if let result = trimmedValue(item.string(at: ["result"])) {
            return result
        }
        // Try nested output.text
        if let outputText = trimmedValue(item.string(at: ["output", "text"])) {
            return outputText
        }
        return nil
    }

    nonisolated static func parseAgentMessageText(from item: [String: JSONValue]) -> String? {
        let root = JSONValue.object(item)
        let collected = collectAgentMessageTextFragments(from: root)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collected.isEmpty ? nil : collected
    }

    nonisolated static func assistantTextSuffix(fromSnapshot snapshot: String, emitted: String) -> String? {
        guard !snapshot.isEmpty else { return nil }
        if emitted.isEmpty {
            return snapshot
        }
        if snapshot == emitted {
            return nil
        }
        if snapshot.hasPrefix(emitted) {
            let index = snapshot.index(snapshot.startIndex, offsetBy: emitted.count)
            let suffix = String(snapshot[index...])
            return suffix.isEmpty ? nil : suffix
        }

        // If we only saw whitespace deltas, prefer the server snapshot.
        if emitted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return snapshot
        }
        return nil
    }

    private nonisolated static func collectAgentMessageTextFragments(from value: JSONValue) -> [String] {
        switch value {
        case .string(let text):
            return [text]

        case .array(let array):
            return array.flatMap { collectAgentMessageTextFragments(from: $0) }

        case .object(let object):
            var fragments: [String] = []

            if let text = object.string(at: ["text"]) {
                fragments.append(text)
            }
            if let valueText = object.string(at: ["value"]),
               object.string(at: ["type"]) == "output_text" || object.string(at: ["type"]) == "text" {
                fragments.append(valueText)
            }

            for key in ["message", "content", "contentItems", "output", "parts", "item"] {
                guard let nested = object[key] else { continue }
                fragments.append(contentsOf: collectAgentMessageTextFragments(from: nested))
            }
            return fragments

        default:
            return []
        }
    }

    private nonisolated static func dynamicToolCallName(from item: [String: JSONValue]) -> String? {
        trimmedValue(
            item.string(at: ["name"])
                ?? item.string(at: ["toolName"])
                ?? item.string(at: ["tool"])
                ?? item.string(at: ["tool", "name"])
                ?? item.string(at: ["tool", "id"])
                ?? item.string(at: ["tool", "type"])
                ?? item.string(at: ["kind"])
        )
    }

    private nonisolated static func isLikelyWebSearchTool(named rawName: String) -> Bool {
        let normalized = rawName
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        let canonical = normalized.replacingOccurrences(of: ".", with: "_")

        let knownNames: Set<String> = [
            "web_search",
            "websearch",
            "search_web",
            "browser.search",
            "browser_search"
        ]
        if knownNames.contains(normalized) || knownNames.contains(canonical) {
            return true
        }

        let tokens = Set(
            canonical
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )

        if tokens.contains("websearch") {
            return true
        }
        if tokens.contains("browser") && (tokens.contains("search") || tokens.contains("browse")) {
            return true
        }
        if tokens.contains("web") && (tokens.contains("search") || tokens.contains("browse")) {
            return true
        }
        if tokens.contains("search") && tokens.contains("engine") {
            return true
        }
        return false
    }

    private nonisolated static func dynamicToolCallID(
        from item: [String: JSONValue],
        params: [String: JSONValue],
        fallbackTurnID: String?,
        toolName: String
    ) -> String {
        if let explicitID = trimmedValue(
            item.string(at: ["id"])
                ?? item.string(at: ["callId"])
                ?? item.string(at: ["toolCallId"])
                ?? params.string(at: ["itemId"])
        ) {
            return explicitID
        }

        let turnID = trimmedValue(
            params.string(at: ["turnId"])
                ?? params.string(at: ["turn", "id"])
                ?? fallbackTurnID
        ) ?? "unknown_turn"

        var fallbackID = "codex_dynamic_search_\(turnID)_\(toolName.lowercased())"
        if let suffix = toolActivityFallbackSuffix(from: item, params: params) {
            fallbackID += "_\(suffix)"
        }
        return fallbackID
    }

    private nonisolated static func toolActivityFallbackSuffix(
        from item: [String: JSONValue],
        params: [String: JSONValue]
    ) -> String? {
        if let sequence = item.int(at: ["sequenceNumber"]) ?? params.int(at: ["sequenceNumber"]) {
            return "seq\(sequence)"
        }
        if let outputIndex = item.int(at: ["outputIndex"]) ?? params.int(at: ["outputIndex"]) {
            return "out\(outputIndex)"
        }
        if let callIndex = item.int(at: ["callIndex"])
            ?? params.int(at: ["callIndex"])
            ?? item.int(at: ["index"])
            ?? params.int(at: ["index"]) {
            return "idx\(callIndex)"
        }
        return nil
    }

    private nonisolated static func dynamicToolCallSearchStatus(
        from item: [String: JSONValue],
        method: String
    ) -> SearchActivityStatus {
        if method == "item/completed" || method.hasSuffix("/completed") {
            return .completed
        }
        if method.hasSuffix("/failed") {
            return .failed
        }
        if method.hasSuffix("/searching") {
            return .searching
        }
        if method.hasSuffix("/started") {
            return .inProgress
        }

        if let rawStatus = trimmedValue(item.string(at: ["status"]) ?? item.string(at: ["state"])) {
            let normalized = rawStatus
                .replacingOccurrences(
                    of: "([a-z0-9])([A-Z])",
                    with: "$1_$2",
                    options: .regularExpression
                )
                .lowercased()
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
            if normalized == "running" || normalized == "inprogress" || normalized == "in_progress" {
                return .inProgress
            }
            return SearchActivityStatus(rawValue: normalized)
        }
        return .inProgress
    }

    private nonisolated static func dynamicToolCallSearchArguments(from item: [String: JSONValue]) -> [String: AnyCodable] {
        var arguments: [String: AnyCodable] = [:]

        var queries: [String] = []
        var seenQueries = Set<String>()
        func appendQuery(_ candidate: String?) {
            guard let query = trimmedValue(candidate) else { return }
            let key = query.lowercased()
            guard seenQueries.insert(key).inserted else { return }
            queries.append(query)
        }

        appendQuery(item.string(at: ["query"]))
        appendQuery(item.string(at: ["searchQuery"]))
        appendQuery(item.string(at: ["prompt"]))
        appendQuery(item.object(at: ["arguments"])?.string(at: ["query"]))
        appendQuery(item.object(at: ["arguments"])?.string(at: ["searchQuery"]))
        appendQuery(item.object(at: ["input"])?.string(at: ["query"]))
        appendQuery(item.object(at: ["input"])?.string(at: ["searchQuery"]))

        for queryValue in item.array(at: ["queries"]) ?? [] {
            appendQuery(queryValue.stringValue)
        }
        for queryValue in item.object(at: ["arguments"])?.array(at: ["queries"]) ?? [] {
            appendQuery(queryValue.stringValue)
        }
        for queryValue in item.object(at: ["input"])?.array(at: ["queries"]) ?? [] {
            appendQuery(queryValue.stringValue)
        }

        if let firstQuery = queries.first {
            arguments["query"] = AnyCodable(firstQuery)
            arguments["queries"] = AnyCodable(queries)
        }

        var sources: [[String: Any]] = []
        var seenURLs = Set<String>()
        func appendSource(url candidateURL: String?, title: String?, snippet: String?) {
            guard let normalizedURL = trimmedValue(candidateURL) else { return }
            let dedupeKey = normalizedURL.lowercased()
            guard seenURLs.insert(dedupeKey).inserted else { return }

            var source: [String: Any] = ["url": normalizedURL]
            if let title = trimmedValue(title) {
                source["title"] = title
            }
            if let snippet = trimmedValue(snippet) {
                source["snippet"] = snippet
            }
            sources.append(source)
        }

        let sourceCandidatePaths: [[String]] = [
            ["sources"],
            ["result", "sources"],
            ["result", "results"],
            ["output", "sources"],
            ["output", "results"],
            ["searchResult", "sources"],
            ["searchResult", "results"],
            ["webSearch", "sources"],
            ["webSearch", "results"],
            ["arguments", "sources"],
            ["input", "sources"]
        ]

        for path in sourceCandidatePaths {
            for candidate in item.array(at: path) ?? [] {
                guard let object = candidate.objectValue else { continue }
                appendSource(
                    url: object.string(at: ["url"]) ?? object.object(at: ["source"])?.string(at: ["url"]),
                    title: object.string(at: ["title"]) ?? object.object(at: ["source"])?.string(at: ["title"]),
                    snippet: preferredSnippetValue(from: object)
                        ?? object.object(at: ["source"]).flatMap(preferredSnippetValue(from:))
                )
            }
        }

        let allText = collectAgentMessageTextFragments(from: .object(item)).joined(separator: "\n")
        for url in extractURLs(from: allText) {
            appendSource(url: url, title: nil, snippet: nil)
        }

        if !sources.isEmpty {
            arguments["sources"] = AnyCodable(sources)
            if let first = sources.first {
                if let firstURL = first["url"] as? String {
                    arguments["url"] = AnyCodable(firstURL)
                }
                if let firstTitle = first["title"] as? String {
                    arguments["title"] = AnyCodable(firstTitle)
                }
            }
        }

        return arguments
    }

    private nonisolated static func preferredSnippetValue(from object: [String: JSONValue]) -> String? {
        let candidatePaths: [[String]] = [
            ["snippet"],
            ["summary"],
            ["description"],
            ["preview"],
            ["excerpt"],
            ["citedText"],
            ["cited_text"],
            ["quote"],
            ["abstract"]
        ]

        for path in candidatePaths {
            if let value = trimmedValue(object.string(at: path)) {
                return value
            }
        }
        return nil
    }

    private nonisolated static func extractURLs(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        let pattern = #"https?://[^\s<>"'\]\)]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        var results: [String] = []
        var seen = Set<String>()
        for match in matches {
            let url = nsText.substring(with: match.range)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}>\"'"))
            guard !url.isEmpty else { continue }
            let key = url.lowercased()
            guard seen.insert(key).inserted else { continue }
            results.append(url)
        }
        return results
    }

    private nonisolated static func parseCatalogMetadata(from modelObject: [String: JSONValue]) -> ModelCatalogMetadata? {
        let availabilityMessage = trimmedValue(modelObject.string(at: ["availabilityNux", "message"]))
        let upgradeTarget = trimmedValue(
            modelObject.string(at: ["upgradeInfo", "model"])
                ?? modelObject.string(at: ["upgrade"])
        )
        let upgradeMessage = trimmedValue(
            modelObject.string(at: ["upgradeInfo", "upgradeCopy"])
                ?? modelObject.string(at: ["upgradeCopy"])
        )

        let metadata = ModelCatalogMetadata(
            availabilityMessage: availabilityMessage,
            upgradeTargetModelID: upgradeTarget,
            upgradeMessage: upgradeMessage
        )
        return metadata.isEmpty ? nil : metadata
    }

    private nonisolated static func parseSupportedReasoningEfforts(from modelObject: [String: JSONValue]) -> [ReasoningEffort] {
        guard let supported = modelObject.array(at: ["supportedReasoningEfforts"]) else {
            return []
        }

        var efforts: [ReasoningEffort] = []
        for item in supported {
            if let effort = parseReasoningEffort(item.stringValue) {
                efforts.append(effort)
                continue
            }

            if let object = item.objectValue {
                let value = object.string(at: ["reasoningEffort"]) ?? object.string(at: ["effort"])
                if let effort = parseReasoningEffort(value) {
                    efforts.append(effort)
                }
            }
        }

        // Preserve server ordering while removing duplicates.
        var seen = Set<ReasoningEffort>()
        return efforts.filter { seen.insert($0).inserted }
    }

    private nonisolated static func parseReasoningEffort(_ raw: String?) -> ReasoningEffort? {
        guard let raw else { return nil }
        return ReasoningEffort(rawValue: raw.lowercased())
    }

    private nonisolated static func firstPositiveInt(
        from object: [String: JSONValue],
        candidatePaths: [[String]]
    ) -> Int? {
        for path in candidatePaths {
            if let value = object.int(at: path), value > 0 {
                return value
            }
        }
        return nil
    }

    private nonisolated static func trimmedValue(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func remapCodexConnectivityError(_ error: Error, endpoint: URL) -> Error {
        guard let guidance = codexConnectivityGuidanceMessage(for: error, endpoint: endpoint) else {
            return error
        }
        return LLMError.providerError(code: "codex_server_unavailable", message: guidance)
    }

    nonisolated static func codexConnectivityGuidanceMessage(
        for error: Error,
        endpoint: URL
    ) -> String? {
        guard isLikelyCodexServerUnavailable(error) else { return nil }
        let endpointString = endpoint.absoluteString
        return """
        Cannot connect to Codex App Server at \(endpointString).

        If you're using a local server, start it first:
        - Jin -> Settings -> Providers -> Codex App Server (Beta) -> Start Server
        - Terminal: codex app-server --listen \(endpointString)

        If you're using a remote endpoint, verify the URL/network and retry.
        """
    }

    private nonisolated static func isLikelyCodexServerUnavailable(_ error: Error) -> Bool {
        if case LLMError.invalidRequest(let message) = error,
           message.localizedCaseInsensitiveContains("not connected") {
            return true
        }

        guard case LLMError.networkError(let underlying) = error else {
            return false
        }

        if isLikelyConnectionPOSIXError(underlying) {
            return true
        }

        let description = underlying.localizedDescription.lowercased()
        let connectivityHints = [
            "connection refused",
            "failed to connect",
            "timed out",
            "network is unreachable",
            "host is down",
            "socket is not connected",
            "websocket connection was cancelled",
            "connection reset",
            "connection aborted",
            "broken pipe"
        ]
        return connectivityHints.contains { description.contains($0) }
    }

    private nonisolated static func isLikelyConnectionPOSIXError(_ error: Error) -> Bool {
        if let nwError = error as? NWError {
            switch nwError {
            case .posix(let code):
                return isLikelyConnectionPOSIXCode(Int32(code.rawValue))
            case .dns:
                return true
            default:
                break
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            return isLikelyConnectionPOSIXCode(Int32(nsError.code))
        }
        return false
    }

    private nonisolated static func isLikelyConnectionPOSIXCode(_ code: Int32) -> Bool {
        code == ECONNREFUSED
            || code == ETIMEDOUT
            || code == EHOSTUNREACH
            || code == ENETUNREACH
            || code == EHOSTDOWN
            || code == ECONNRESET
            || code == ECONNABORTED
            || code == EPIPE
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
