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

    let apiKey: String
    let networkManager: NetworkManager
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

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        _ = tools
        return [[String: Any]]()
    }

    // MARK: - Request builders

    func makeThreadStartParams(modelID: String, controls: GenerationControls) -> [String: Any] {
        CodexAppServerRequestBuilder.threadStartParams(modelID: modelID, controls: controls)
    }

    func makeThreadResumeParams(threadID: String, modelID: String, controls: GenerationControls) -> [String: Any] {
        CodexAppServerRequestBuilder.threadResumeParams(threadID: threadID, modelID: modelID, controls: controls)
    }

    func makeTurnStartParams(
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

    func resolvedEndpointURL() throws -> URL {
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

    nonisolated static func extractThreadID(from result: JSONValue) -> String? {
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
