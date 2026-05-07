import Foundation

/// OpenAI provider adapter (Responses API WebSocket mode)
actor OpenAIWebSocketAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .imageGeneration]

    let networkManager: NetworkManager
    let apiKey: String
    let overrideSession: URLSession?

    var urlSession: URLSession {
        overrideSession ?? .shared
    }

    var webSocketTask: URLSessionWebSocketTask?
    var isResponseInFlight = false
    var previousResponseID: String?
    var activeTraceSessionID: UUID?

    init(
        providerConfig: ProviderConfig,
        apiKey: String,
        networkManager: NetworkManager = NetworkManager(),
        urlSession: URLSession? = nil
    ) {
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager
        self.overrideSession = urlSession
    }

    deinit {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }

    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming _: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        guard ModelCatalog.isOpenAIWebSocketAdapterCompatible(modelID: modelID) else {
            throw LLMError.invalidRequest(
                message: "\(modelID) is not supported by the OpenAI WebSocket provider. Use the OpenAI provider instead."
            )
        }

        // Route image generation models through the OpenAI HTTP Images API.
        if isImageGenerationModel(modelID) {
            let httpAdapter = OpenAIAdapter(
                providerConfig: ProviderConfig(
                    id: providerConfig.id,
                    name: providerConfig.name,
                    type: .openai,
                    iconID: providerConfig.iconID,
                    authModeHint: providerConfig.authModeHint,
                    apiKey: providerConfig.apiKey,
                    serviceAccountJSON: providerConfig.serviceAccountJSON,
                    baseURL: resolvedHTTPBaseURLString(),
                    models: providerConfig.models
                ),
                apiKey: apiKey,
                networkManager: networkManager
            )
            return try await httpAdapter.sendMessage(
                messages: messages,
                modelID: modelID,
                controls: controls,
                tools: tools,
                streaming: true
            )
        }

        // OpenAI currently documents audio input support primarily on Chat Completions.
        // Route audio-bearing requests through the OpenAI-compatible Chat Completions path.
        if shouldRouteToChatCompletionsForAudio(messages: messages, modelID: modelID) {
            let chatCompletionsAdapter = OpenAICompatibleAdapter(
                providerConfig: ProviderConfig(
                    id: providerConfig.id,
                    name: providerConfig.name,
                    type: .openaiCompatible,
                    iconID: providerConfig.iconID,
                    authModeHint: providerConfig.authModeHint,
                    apiKey: providerConfig.apiKey,
                    serviceAccountJSON: providerConfig.serviceAccountJSON,
                    baseURL: resolvedHTTPBaseURLString(),
                    models: providerConfig.models
                ),
                apiKey: apiKey,
                networkManager: networkManager
            )
            return try await chatCompletionsAdapter.sendMessage(
                messages: messages,
                modelID: modelID,
                controls: controls,
                tools: tools,
                streaming: true
            )
        }

        if isResponseInFlight {
            throw LLMError.invalidRequest(message: "OpenAI WebSocket mode does not support concurrent responses on a single connection.")
        }

        let (inputMessages, continuationID) = continuationState(for: messages)
        let responsePayload = try buildResponsePayload(
            messages: inputMessages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            previousResponseID: continuationID
        )

        let createEvent = Self.responseCreateEvent(from: responsePayload)

        let createEventData = try JSONSerialization.data(withJSONObject: createEvent)
        guard let createEventString = String(data: createEventData, encoding: .utf8) else {
            throw LLMError.invalidRequest(message: "Failed to encode WebSocket request payload.")
        }

        isResponseInFlight = true
        let ws: URLSessionWebSocketTask
        do {
            ws = try await openWebSocket()
        } catch {
            isResponseInFlight = false
            throw error
        }

        let socketURL = ws.originalRequest?.url
        activeTraceSessionID = await NetworkDebugLogger.shared.beginWebSocketSession(
            url: socketURL ?? URL(string: "wss://unknown")!,
            headers: ws.originalRequest?.allHTTPHeaderFields
        )
        let traceSessionID = activeTraceSessionID

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await ws.send(.string(createEventString))
                    await NetworkDebugLogger.shared.logWebSocketSend(sessionID: traceSessionID, message: createEventString)

                    var functionCallsByItemID: [String: ResponsesAPIFunctionCallState] = [:]
                    var codeInterpreterState = OpenAICodeInterpreterState()
                    let eventDecoder = JSONDecoder()
                    eventDecoder.keyDecodingStrategy = .convertFromSnakeCase

                    while !Task.isCancelled {
                        try Task.checkCancellation()

                        let message = try await ws.receive()
                        let jsonString: String
                        switch message {
                        case .string(let text):
                            jsonString = text
                        case .data(let data):
                            jsonString = String(data: data, encoding: .utf8) ?? ""
                        @unknown default:
                            jsonString = ""
                        }

                        await NetworkDebugLogger.shared.logWebSocketReceive(sessionID: traceSessionID, message: jsonString)

                        guard let eventType = parseEventType(from: jsonString) else {
                            continue
                        }

                        let isTerminalEvent = isTerminalResponseEventType(eventType)

                        if eventType == "response.incomplete",
                           let jsonData = jsonString.data(using: .utf8),
                           let incomplete = try? eventDecoder.decode(ResponsesAPIIncompleteEvent.self, from: jsonData) {
                            if let notice = incomplete.response.incompleteNoticeMarkdown {
                                continuation.yield(.contentDelta(.text(notice)))
                            }
                            continuation.yield(.messageEnd(usage: incomplete.response.toUsage()))
                            break
                        }

                        do {
                            if let streamEvent = try parseSSEEvent(
                                type: eventType,
                                data: jsonString,
                                functionCallsByItemID: &functionCallsByItemID,
                                codeInterpreterState: &codeInterpreterState
                            ) {
                                if case .messageStart(let id) = streamEvent {
                                    previousResponseID = id
                                }

                                continuation.yield(streamEvent)
                            }
                        } catch is DecodingError {
                            // Be resilient to provider-side schema drift in individual events.
                            // Skip malformed events instead of aborting the whole response stream.
                            if isTerminalEvent {
                                break
                            }
                            continue
                        }

                        if isTerminalEvent {
                            break
                        }
                    }

                    isResponseInFlight = false
                    await NetworkDebugLogger.shared.endWebSocketSession(sessionID: traceSessionID, error: nil)
                    continuation.finish()
                } catch is CancellationError {
                    await cancelResponseIfPossible()
                    await NetworkDebugLogger.shared.endWebSocketSession(sessionID: traceSessionID, error: CancellationError())
                    resetWebSocketState()
                    continuation.finish(throwing: CancellationError())
                } catch {
                    await NetworkDebugLogger.shared.endWebSocketSession(sessionID: traceSessionID, error: error)
                    resetWebSocketState()
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task {
                    await self.cancelResponseIfPossible()
                }
            }
        }
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        try await validateOpenAIWebSocketAPIKey(key)
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        try await fetchOpenAIWebSocketModels()
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }
}
