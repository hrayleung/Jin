import Foundation

/// OpenAI provider adapter (Responses API)
actor OpenAIAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .imageGeneration]

    let networkManager: NetworkManager
    let apiKey: String

    init(providerConfig: ProviderConfig, apiKey: String, networkManager: NetworkManager = NetworkManager()) {
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
        if isImageGenerationModel(modelID) {
            return try makeImageGenerationStream(messages: messages, modelID: modelID, controls: controls)
        }

        // OpenAI currently documents audio input support primarily on Chat Completions.
        // Route audio-bearing requests through the OpenAI-compatible Chat Completions path.
        if shouldRouteToChatCompletionsForAudio(messages: messages, modelID: modelID) {
            let chatCompletionsAdapter = OpenAICompatibleAdapter(
                providerConfig: providerConfig,
                apiKey: apiKey,
                networkManager: networkManager
            )
            return try await chatCompletionsAdapter.sendMessage(
                messages: messages,
                modelID: modelID,
                controls: controls,
                tools: tools,
                streaming: streaming
            )
        }

        let request = try await buildRequest(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: streaming
        )

        if !streaming {
            let (data, _) = try await networkManager.sendRequest(request)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(ResponsesAPIResponse.self, from: data)

            return AsyncThrowingStream { continuation in
                continuation.yield(.messageStart(id: response.id))

                for activity in response.searchActivities {
                    continuation.yield(.searchActivity(activity))
                }

                for text in response.outputTextParts {
                    continuation.yield(.contentDelta(.text(text)))
                }

                if let notice = response.incompleteNoticeMarkdown {
                    continuation.yield(.contentDelta(.text(notice)))
                }

                continuation.yield(.messageEnd(usage: response.toUsage()))
                continuation.finish()
            }
        }

        let parser = SSEParser()
        let sseStream = await networkManager.streamRequest(request, parser: parser)
        let streamDecoder = JSONDecoder()
        streamDecoder.keyDecodingStrategy = .convertFromSnakeCase

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var functionCallsByItemID: [String: ResponsesAPIFunctionCallState] = [:]
                    var codeInterpreterState = OpenAICodeInterpreterState()
                    var didEmitTerminalMessageEnd = false

                    for try await event in sseStream {
                        switch event {
                        case .event(let type, let data):
                            if type == "response.incomplete",
                               let jsonData = data.data(using: .utf8),
                               let incomplete = try? streamDecoder.decode(ResponsesAPIIncompleteEvent.self, from: jsonData) {
                                if let notice = incomplete.response.incompleteNoticeMarkdown {
                                    continuation.yield(.contentDelta(.text(notice)))
                                }
                                continuation.yield(.messageEnd(usage: incomplete.response.toUsage()))
                                didEmitTerminalMessageEnd = true
                                continue
                            }

                            do {
                                if let streamEvent = try parseSSEEvent(
                                    type: type,
                                    data: data,
                                    functionCallsByItemID: &functionCallsByItemID,
                                    codeInterpreterState: &codeInterpreterState
                                ) {
                                    if case .messageEnd = streamEvent {
                                        didEmitTerminalMessageEnd = true
                                    }
                                    continuation.yield(streamEvent)
                                }
                            } catch is DecodingError {
                                // Be resilient to provider-side schema drift in individual events.
                                // Skip malformed events instead of aborting the whole response stream.
                                continue
                            }
                        case .done:
                            if !didEmitTerminalMessageEnd {
                                continuation.yield(.messageEnd(usage: nil))
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }

    var baseURL: String {
        providerConfig.baseURL ?? "https://api.openai.com/v1"
    }
}
