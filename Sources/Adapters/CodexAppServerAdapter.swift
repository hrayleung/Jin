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
    static let fallbackContextWindow = 256_000

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
        let fullTurnInput = Self.makeTurnInput(from: messages, resumeExistingThread: false)
        let resumedTurnInput = Self.makeTurnInput(from: messages, resumeExistingThread: true)
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

                    let persistedThreadID = controls.codexResumeThreadID
                    let pendingRollbackTurns = controls.codexPendingRollbackTurns

                    let threadID: String
                    let turnInput: [Any]

                    if let persistedThreadID {
                        do {
                            let threadResumeResult = try await client.request(
                                method: "thread/resume",
                                params: makeThreadResumeParams(
                                    threadID: persistedThreadID,
                                    modelID: modelID,
                                    controls: controls
                                )
                            ) { envelope in
                                try await self.handleInterleavedEnvelope(
                                    envelope,
                                    with: client,
                                    continuation: continuation,
                                    state: state
                                )
                            }

                            let resumedThreadID = Self.extractThreadID(from: threadResumeResult) ?? persistedThreadID

                            if pendingRollbackTurns > 0 {
                                _ = try await client.request(
                                    method: "thread/rollback",
                                    params: [
                                        "threadId": resumedThreadID,
                                        "numTurns": pendingRollbackTurns
                                    ]
                                ) { envelope in
                                    try await self.handleInterleavedEnvelope(
                                        envelope,
                                        with: client,
                                        continuation: continuation,
                                        state: state
                                    )
                                }
                            }

                            threadID = resumedThreadID
                            turnInput = resumedTurnInput
                        } catch {
                            guard Self.shouldFallbackToFreshThread(error) else {
                                throw error
                            }

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

                            guard let newThreadID = Self.extractThreadID(from: threadStartResult) else {
                                throw LLMError.decodingError(message: "Codex thread/start did not return thread.id.")
                            }

                            threadID = newThreadID
                            turnInput = fullTurnInput
                        }
                    } else {
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

                        guard let newThreadID = Self.extractThreadID(from: threadStartResult) else {
                            throw LLMError.decodingError(message: "Codex thread/start did not return thread.id.")
                        }

                        threadID = newThreadID
                        turnInput = fullTurnInput
                    }

                    continuation.yield(.codexThreadState(CodexThreadState(remoteThreadID: threadID)))

                    let turnStartParams = makeTurnStartParams(
                        threadID: threadID,
                        inputItems: turnInput,
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

                if let nextCursor = object.string(at: ["nextCursor"])?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !nextCursor.isEmpty {
                    cursor = nextCursor
                } else {
                    cursor = nil
                }
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
                params: envelope.params?.objectValue,
                with: client,
                continuation: nil
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
                    params: envelope.params?.objectValue,
                    with: client,
                    continuation: continuation
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

                    break
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
        params: [String: JSONValue]?,
        with client: CodexWebSocketRPCClient,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation?
    ) async throws {
        let params = params ?? [:]

        if let continuation,
           let interaction = Self.interactionRequest(id: id, method: method, params: params) {
            continuation.yield(.codexInteractionRequest(interaction))
            let response = await withTaskCancellationHandler(
                operation: {
                    await interaction.waitForResponse()
                },
                onCancel: {
                    Task {
                        await interaction.resolve(.cancelled(message: nil))
                    }
                }
            )
            try await Self.sendInteractionResponse(
                response,
                for: interaction,
                requestID: id,
                client: client
            )
            return
        }

        if let autoReply = CodexAppServerAutoReply.result(forServerRequestMethod: method) {
            try await client.respond(id: id, result: autoReply)
            return
        }

        let message: String
        switch method {
        case "item/tool/call", "item/tool/requestUserInput":
            message = "Client callbacks are disabled for this Codex App Server provider."
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
        CodexAppServerRequestBuilder.threadStartParams(modelID: modelID, controls: controls)
    }

    private func makeThreadResumeParams(threadID: String, modelID: String, controls: GenerationControls) -> [String: Any] {
        CodexAppServerRequestBuilder.threadResumeParams(threadID: threadID, modelID: modelID, controls: controls)
    }

    private func makeTurnStartParams(
        threadID: String,
        inputItems: [Any],
        controls: GenerationControls,
        modelID: String
    ) -> [String: Any] {
        CodexAppServerRequestBuilder.turnStartParams(
            threadID: threadID,
            inputItems: inputItems,
            modelID: modelID,
            controls: controls
        )
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

    nonisolated static func makeTurnInput(from messages: [Message], resumeExistingThread: Bool) -> [Any] {
        let fallbackPrompt = makePrompt(from: messages)

        guard resumeExistingThread,
              let lastMessage = messages.last,
              lastMessage.role == .user else {
            return [makeCodexTextInput(fallbackPrompt)]
        }

        let imageInputs = lastMessage.content.compactMap { part -> [String: Any]? in
            guard case .image(let image) = part else { return nil }
            return Self.codexImageInputItem(from: image)
        }
        guard !imageInputs.isEmpty else {
            let latestUserText = renderUserTextForCodex(from: lastMessage.content)
            let trimmedUserText = latestUserText.trimmingCharacters(in: .whitespacesAndNewlines)
            return [makeCodexTextInput(trimmedUserText.isEmpty ? "Continue." : trimmedUserText)]
        }

        let latestUserText = renderUserTextForCodex(from: lastMessage.content)

        var inputs: [Any] = []
        let trimmedUserText = latestUserText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputs.append(makeCodexTextInput(trimmedUserText.isEmpty ? "Continue." : trimmedUserText))
        inputs.append(contentsOf: imageInputs)
        return inputs.isEmpty ? [makeCodexTextInput(fallbackPrompt)] : inputs
    }

    private nonisolated static func renderUserTextForCodex(from content: [ContentPart]) -> String {
        content.compactMap { part -> String? in
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
                return Self.codexImageInputItem(from: image) == nil ? "[Image attachment]" : nil
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
    }

    private nonisolated static func makeCodexTextInput(_ text: String) -> [String: Any] {
        [
            "type": "text",
            "text": text,
            "text_elements": [Any]()
        ]
    }

    private nonisolated static func makePrompt(from messages: [Message]) -> String {
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

    private nonisolated static func codexImageInputItem(from image: ImageContent) -> [String: Any]? {
        if let url = image.url {
            if url.isFileURL {
                return [
                    "type": "localImage",
                    "path": url.path
                ]
            }
            return [
                "type": "image",
                "url": url.absoluteString
            ]
        }
        return nil
    }

    private nonisolated static func extractThreadID(from result: JSONValue) -> String? {
        if let threadID = result.objectValue?.string(at: ["thread", "id"]), !threadID.isEmpty {
            return threadID
        }
        if let threadID = result.objectValue?.string(at: ["threadId"]), !threadID.isEmpty {
            return threadID
        }
        return nil
    }

    nonisolated static func shouldFallbackToFreshThread(_ error: Error) -> Bool {
        guard case let LLMError.providerError(code, message) = error else {
            return false
        }

        let lower = message.lowercased()
        return lower.contains("not found")
            || lower.contains("unknown thread")
            || lower.contains("no such thread")
            || (code == "-32602" && lower.contains("missing thread"))
    }

}

// WebSocket RPC client, stream state, and JSON helpers are in CodexWebSocketRPCClient.swift
