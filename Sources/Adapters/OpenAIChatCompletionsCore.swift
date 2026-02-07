import Foundation

enum OpenAIChatCompletionsReasoningField {
    case reasoning
    case reasoningContent
}

struct OpenAIChatCompletionsCore {
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
                if let reasoning = messageReasoning(choice.message, field: reasoningField) {
                    continuation.yield(.thinkingDelta(.thinking(textDelta: reasoning, signature: nil)))
                }

                if let content = normalized(choice.message.content) {
                    continuation.yield(.contentDelta(.text(content)))
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
                    var toolCallsByIndex: [Int: OpenAIChatCompletionsToolCallState] = [:]

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

                            guard let choice = chunk.choices.first else { continue }

                            if let delta = deltaReasoning(choice.delta, field: reasoningField) {
                                continuation.yield(.thinkingDelta(.thinking(textDelta: delta, signature: nil)))
                            }

                            if let delta = normalized(choice.delta.content) {
                                continuation.yield(.contentDelta(.text(delta)))
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

    private static func messageReasoning(
        _ message: OpenAIChatCompletionsResponse.AssistantMessage,
        field: OpenAIChatCompletionsReasoningField
    ) -> String? {
        switch field {
        case .reasoning:
            return normalized(message.reasoning)
        case .reasoningContent:
            return normalized(message.reasoningContent)
        }
    }

    private static func deltaReasoning(
        _ delta: OpenAIChatCompletionsChunk.Delta,
        field: OpenAIChatCompletionsReasoningField
    ) -> String? {
        switch field {
        case .reasoning:
            return normalized(delta.reasoning)
        case .reasoningContent:
            return normalized(delta.reasoningContent)
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    private static func parseJSONObject(_ jsonString: String) -> [String: AnyCodable] {
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object.mapValues(AnyCodable.init)
    }
}

struct OpenAIModelsResponse: Codable {
    let data: [Model]

    struct Model: Codable {
        let id: String
    }
}

struct OpenAIChatCompletionsResponse: Codable {
    let id: String
    let choices: [Choice]
    let usage: UsageInfo?

    struct Choice: Codable {
        let message: AssistantMessage
        let finishReason: String?
    }

    struct AssistantMessage: Codable {
        let role: String?
        let content: String?
        let reasoning: String?
        let reasoningContent: String?
        let toolCalls: [ToolCall]?
    }

    struct ToolCall: Codable {
        let id: String?
        let type: String?
        let function: Function?

        struct Function: Codable {
            let name: String?
            let arguments: String?
        }
    }

    struct UsageInfo: Codable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
    }

    func toUsage() -> Usage? {
        guard let usage else { return nil }
        guard let input = usage.promptTokens, let output = usage.completionTokens else { return nil }
        return Usage(inputTokens: input, outputTokens: output)
    }
}

struct OpenAIChatCompletionsChunk: Codable {
    let id: String?
    let choices: [Choice]
    let usage: OpenAIChatCompletionsResponse.UsageInfo?

    struct Choice: Codable {
        let index: Int?
        let delta: Delta
        let finishReason: String?
    }

    struct Delta: Codable {
        let role: String?
        let content: String?
        let reasoning: String?
        let reasoningContent: String?
        let toolCalls: [ToolCallDelta]?
    }

    struct ToolCallDelta: Codable {
        let index: Int?
        let id: String?
        let type: String?
        let function: FunctionDelta?

        struct FunctionDelta: Codable {
            let name: String?
            let arguments: String?
        }
    }

    func toUsage() -> Usage? {
        guard let usage else { return nil }
        guard let input = usage.promptTokens, let output = usage.completionTokens else { return nil }
        return Usage(inputTokens: input, outputTokens: output)
    }
}

struct OpenAIChatCompletionsToolCallState {
    var callID: String
    var name: String
    var argumentsBuffer: String = ""
    var didEmitStart: Bool = false
}
