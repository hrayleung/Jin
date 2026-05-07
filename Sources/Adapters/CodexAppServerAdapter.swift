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

}
