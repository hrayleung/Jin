import Foundation

enum OpenAIChatCompletionsReasoningField {
    case reasoning
    case reasoningContent
    case reasoningOrReasoningContent
}

enum OpenAIChatCompletionsCore {
    static func decodeResponse(_ data: Data) throws -> OpenAIChatCompletionsResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OpenAIChatCompletionsResponse.self, from: data)
    }

    static func decodeChunk(_ data: Data) throws -> OpenAIChatCompletionsChunk {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OpenAIChatCompletionsChunk.self, from: data)
    }

    static func makeNonStreamingStream(
        response: OpenAIChatCompletionsResponse,
        reasoningField: OpenAIChatCompletionsReasoningField
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.messageStart(id: response.id))

            for choice in response.choices {
                let explicitReasoning = OpenAIChatCompletionsReasoningSupport.messageReasoning(
                    choice.message,
                    field: reasoningField
                ) ?? OpenAIChatCompletionsReasoningSupport.responseChoiceReasoning(
                    choice,
                    field: reasoningField
                )
                if let reasoning = explicitReasoning {
                    continuation.yield(.thinkingDelta(.thinking(textDelta: reasoning, signature: nil)))
                }

                if explicitReasoning == nil, let thinking = normalized(choice.message.content?.thinking) {
                    continuation.yield(.thinkingDelta(.thinking(textDelta: thinking, signature: nil)))
                }

                if let rawContent = normalized(choice.message.content?.text) {
                    let split = OpenAIChatCompletionsThinkTagSplitter.splitNonStreaming(rawContent)
                    if explicitReasoning == nil, let thinking = normalized(split.thinking) {
                        continuation.yield(.thinkingDelta(.thinking(textDelta: thinking, signature: nil)))
                    }
                    if let visible = normalized(split.visible) {
                        continuation.yield(.contentDelta(.text(visible)))
                    }
                }

                for image in OpenAIChatCompletionsImageSupport.imageOutputs(choice.message.images) {
                    continuation.yield(.contentDelta(.image(image)))
                }

                if let toolCalls = choice.message.toolCalls, !toolCalls.isEmpty {
                    for call in toolCalls {
                        let name = call.function?.name ?? ""
                        let arguments = parseJSONObject(call.function?.arguments ?? "")
                        let toolCall = ToolCall(id: call.id ?? UUID().uuidString, name: name, arguments: arguments)
                        continuation.yield(.toolCallStart(toolCall))
                        continuation.yield(.toolCallEnd(toolCall))
                    }
                }
            }

            if let sources = OpenAIChatCompletionsSourceSupport.sourcesMarkdown(
                citations: response.citations,
                searchResults: response.searchResults
            ) {
                continuation.yield(.contentDelta(.text(sources)))
            }

            continuation.yield(.messageEnd(usage: response.toUsage()))
            continuation.finish()
        }
    }

    static func makeStreamingStream(
        sseStream: AsyncThrowingStream<SSEEvent, Error>,
        reasoningField: OpenAIChatCompletionsReasoningField
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var didStart = false
                    var messageID: String = UUID().uuidString
                    var pendingUsage: Usage?
                    var pendingCitations: [String]?
                    var pendingSearchResults: [OpenAIChatCompletionsSearchResult]?
                    var toolCallsByIndex: [Int: OpenAIChatCompletionsToolCallState] = [:]
                    var thinkSplitter = OpenAIChatCompletionsThinkTagSplitter()
                    var streamedChoiceReasoningSnapshot = ""

                    for try await event in sseStream {
                        switch event {
                        case .event(_, let data):
                            guard let jsonData = data.data(using: .utf8) else { continue }
                            let chunk = try decodeChunk(jsonData)

                            if !didStart {
                                messageID = chunk.id ?? messageID
                                continuation.yield(.messageStart(id: messageID))
                                didStart = true
                            }

                            if let usage = chunk.toUsage() {
                                pendingUsage = usage
                            }

                            if let citations = chunk.citations, !citations.isEmpty {
                                pendingCitations = citations
                            }
                            if let results = chunk.searchResults, !results.isEmpty {
                                pendingSearchResults = results
                            }

                            guard let choice = chunk.choices.first else { continue }

                            var didEmitExplicitReasoning = false
                            if let delta = OpenAIChatCompletionsReasoningSupport.deltaReasoning(
                                choice.delta,
                                field: reasoningField
                            ) {
                                continuation.yield(.thinkingDelta(.thinking(textDelta: delta, signature: nil)))
                                didEmitExplicitReasoning = true
                            } else if let choiceReasoning = OpenAIChatCompletionsReasoningSupport.chunkChoiceReasoning(
                                choice,
                                field: reasoningField
                            ) {
                                let incremental = OpenAIChatCompletionsReasoningSupport.incrementalDelta(
                                    candidate: choiceReasoning,
                                    previousSnapshot: streamedChoiceReasoningSnapshot
                                )
                                if !incremental.isEmpty {
                                    continuation.yield(.thinkingDelta(.thinking(textDelta: incremental, signature: nil)))
                                    didEmitExplicitReasoning = true
                                }
                                streamedChoiceReasoningSnapshot = choiceReasoning
                            }

                            if !didEmitExplicitReasoning,
                               let thinking = normalized(choice.delta.content?.thinking) {
                                continuation.yield(.thinkingDelta(.thinking(textDelta: thinking, signature: nil)))
                            }

                            if let delta = normalized(choice.delta.content?.text) {
                                let split = thinkSplitter.process(delta)
                                if !split.thinking.isEmpty {
                                    continuation.yield(.thinkingDelta(.thinking(textDelta: split.thinking, signature: nil)))
                                }
                                if !split.visible.isEmpty {
                                    continuation.yield(.contentDelta(.text(split.visible)))
                                }
                            }

                            for image in OpenAIChatCompletionsImageSupport.imageOutputs(choice.delta.images) {
                                continuation.yield(.contentDelta(.image(image)))
                            }

                            if let toolDeltas = choice.delta.toolCalls {
                                for toolDelta in toolDeltas {
                                    guard let index = toolDelta.index else { continue }

                                    if toolCallsByIndex[index] == nil {
                                        toolCallsByIndex[index] = OpenAIChatCompletionsToolCallState(
                                            callID: toolDelta.id ?? "",
                                            name: toolDelta.function?.name ?? ""
                                        )
                                    }

                                    if let id = toolDelta.id, !id.isEmpty {
                                        toolCallsByIndex[index]?.callID = id
                                    }
                                    if let name = toolDelta.function?.name, !name.isEmpty {
                                        toolCallsByIndex[index]?.name = name
                                    }

                                    if toolCallsByIndex[index]?.didEmitStart == false,
                                       let state = toolCallsByIndex[index],
                                       !state.callID.isEmpty,
                                       !state.name.isEmpty {
                                        toolCallsByIndex[index]?.didEmitStart = true
                                        continuation.yield(.toolCallStart(ToolCall(id: state.callID, name: state.name, arguments: [:])))
                                    }

                                    if let argsDelta = toolDelta.function?.arguments, !argsDelta.isEmpty {
                                        toolCallsByIndex[index]?.argumentsBuffer.append(argsDelta)
                                        if let id = toolCallsByIndex[index]?.callID, !id.isEmpty {
                                            continuation.yield(.toolCallDelta(id: id, argumentsDelta: argsDelta))
                                        }
                                    }
                                }
                            }

                        case .done:
                            for (_, state) in toolCallsByIndex.sorted(by: { $0.key < $1.key }) {
                                guard !state.callID.isEmpty, !state.name.isEmpty else { continue }
                                let args = parseJSONObject(state.argumentsBuffer)
                                continuation.yield(.toolCallEnd(ToolCall(id: state.callID, name: state.name, arguments: args)))
                            }

                            let remainder = thinkSplitter.flushRemainder()
                            if !remainder.thinking.isEmpty {
                                continuation.yield(.thinkingDelta(.thinking(textDelta: remainder.thinking, signature: nil)))
                            }
                            if !remainder.visible.isEmpty {
                                continuation.yield(.contentDelta(.text(remainder.visible)))
                            }

                            if let sources = OpenAIChatCompletionsSourceSupport.sourcesMarkdown(
                                citations: pendingCitations,
                                searchResults: pendingSearchResults
                            ) {
                                continuation.yield(.contentDelta(.text(sources)))
                            }

                            continuation.yield(.messageEnd(usage: pendingUsage))
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.trimmedNonEmpty == nil ? nil : value
    }

}
