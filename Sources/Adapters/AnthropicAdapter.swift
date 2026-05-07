import Foundation

actor AnthropicAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning, .promptCaching]

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
        let request = try await buildRequest(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: streaming
        )

        let parser = SSEParser()
        let sseStream = await networkManager.streamRequest(request, parser: parser)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var currentMessageID: String?
                    var currentBlockIndex: Int?
                    var currentToolUse: AnthropicToolCallBuilder?
                    var currentServerToolUse: AnthropicSearchActivityBuilder?
                    var currentCodeExecutionID: String?
                    var currentCodeExecutionCode: String = ""
                    var currentContentBlockType: String?
                    var currentThinkingSignature: String?
                    var usageAccumulator = AnthropicUsageAccumulator()

                    for try await event in sseStream {
                        switch event {
                        case .event(_, let data):
                            do {
                                if let streamEvent = try parseJSONLine(
                                    data,
                                    currentMessageID: &currentMessageID,
                                    currentBlockIndex: &currentBlockIndex,
                                    currentToolUse: &currentToolUse,
                                    currentServerToolUse: &currentServerToolUse,
                                    currentCodeExecutionID: &currentCodeExecutionID,
                                    currentCodeExecutionCode: &currentCodeExecutionCode,
                                    currentContentBlockType: &currentContentBlockType,
                                    currentThinkingSignature: &currentThinkingSignature,
                                    usageAccumulator: &usageAccumulator
                                ) {
                                    continuation.yield(streamEvent)
                                }
                            } catch is DecodingError {
                                // Be resilient to provider-side schema drift in individual events.
                                // Skip malformed events instead of aborting the whole response stream.
                                continue
                            } catch is LLMError {
                                // Malformed tool call arguments or similar event-level issue.
                                // Skip the broken event rather than killing the entire stream.
                                continue
                            }
                        case .done:
                            continuation.yield(.messageEnd(usage: usageAccumulator.toUsage()))
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
        AnthropicToolSpecSupport.customToolSpecs(from: tools)
    }

}

// Stream parsing and search activities: AnthropicStreamParsing.swift
// Request construction: AnthropicAdapter+RequestSupport.swift
// Response types: AnthropicAdapterResponseTypes.swift
// Message translation: AnthropicAdapterMessageTranslation.swift
