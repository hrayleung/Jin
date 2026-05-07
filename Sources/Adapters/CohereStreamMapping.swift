import Foundation

extension CohereAdapter {
    func decodeChatResponse(_ data: Data) throws -> CohereChatResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(CohereChatResponse.self, from: data)
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }

    func makeNonStreamingStream(
        response: CohereChatResponse
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let messageID = response.id ?? UUID().uuidString
            continuation.yield(.messageStart(id: messageID))

            if let parts = response.message?.content {
                let text = parts
                    .compactMap { part -> String? in
                        guard (part.type ?? "").lowercased() == "text" else { return nil }
                        return part.text
                    }
                    .joined(separator: "")
                if !text.isEmpty {
                    continuation.yield(.contentDelta(.text(text)))
                }
            }

            if let toolCalls = response.message?.toolCalls, !toolCalls.isEmpty {
                for call in toolCalls {
                    let id = call.id ?? UUID().uuidString
                    let name = call.function?.name ?? ""
                    let argsString = call.function?.arguments ?? "{}"
                    let args = parseJSONObject(argsString)
                    let toolCall = ToolCall(id: id, name: name, arguments: args)
                    continuation.yield(.toolCallStart(toolCall))
                    continuation.yield(.toolCallEnd(toolCall))
                }
            }

            let usage = response.usage.flatMap { info -> Usage? in
                guard let input = info.tokens?.inputTokens,
                      let output = info.tokens?.outputTokens else { return nil }
                return Usage(inputTokens: input, outputTokens: output)
            }

            continuation.yield(.messageEnd(usage: usage))
            continuation.finish()
        }
    }

    func makeStreamingStream(
        sseStream: AsyncThrowingStream<SSEEvent, Error>
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var didStart = false
                    var messageID: String = UUID().uuidString
                    var pendingUsage: Usage?
                    var toolCallsByID: [String: CohereToolCallState] = [:]

                    for try await event in sseStream {
                        switch event {
                        case .done:
                            continuation.yield(.messageEnd(usage: pendingUsage))
                            continue

                        case .event(_, let data):
                            guard let jsonData = data.data(using: .utf8),
                                  let payload = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                                continue
                            }

                            let type = (payload["type"] as? String) ?? ""

                            if type == "message-start" {
                                if !didStart {
                                    if let id = payload["id"] as? String, !id.isEmpty {
                                        messageID = id
                                    }
                                    continuation.yield(.messageStart(id: messageID))
                                    didStart = true
                                }
                                continue
                            }

                            if !didStart {
                                continuation.yield(.messageStart(id: messageID))
                                didStart = true
                            }

                            switch type {
                            case "content-delta":
                                if let text = (((payload["delta"] as? [String: Any])?["message"] as? [String: Any])?["content"] as? [String: Any])?["text"] as? String,
                                   !text.isEmpty {
                                    continuation.yield(.contentDelta(.text(text)))
                                }

                            case "tool-call-start", "tool-call-delta", "tool-call-end":
                                guard let toolCalls = (((payload["delta"] as? [String: Any])?["message"] as? [String: Any])?["tool_calls"] as? [[String: Any]]) else {
                                    break
                                }

                                for call in toolCalls {
                                    let id = (call["id"] as? String) ?? ""
                                    guard !id.isEmpty else { continue }

                                    var state = toolCallsByID[id] ?? CohereToolCallState(callID: id, name: "", didEmitStart: false, argumentsBuffer: "")

                                    if let fn = call["function"] as? [String: Any] {
                                        if let name = fn["name"] as? String, !name.isEmpty {
                                            state.name = name
                                        }

                                        if let args = fn["arguments"] as? String, !args.isEmpty {
                                            if type == "tool-call-end" {
                                                state.argumentsBuffer = args
                                            } else {
                                                state.argumentsBuffer.append(args)
                                            }
                                            continuation.yield(.toolCallDelta(id: id, argumentsDelta: args))
                                        }
                                    }

                                    if state.didEmitStart == false, !state.name.isEmpty {
                                        state.didEmitStart = true
                                        continuation.yield(.toolCallStart(ToolCall(id: id, name: state.name, arguments: [:])))
                                    }

                                    if type == "tool-call-end", !state.name.isEmpty {
                                        let args = parseJSONObject(state.argumentsBuffer)
                                        continuation.yield(.toolCallEnd(ToolCall(id: id, name: state.name, arguments: args)))
                                    }

                                    toolCallsByID[id] = state
                                }

                            case "message-end":
                                pendingUsage = cohereUsageFromMessageEnd(payload)

                                // Ensure we emit toolCallEnd for any in-progress tool calls.
                                for (_, state) in toolCallsByID where !state.callID.isEmpty && !state.name.isEmpty {
                                    let args = parseJSONObject(state.argumentsBuffer)
                                    continuation.yield(.toolCallEnd(ToolCall(id: state.callID, name: state.name, arguments: args)))
                                }

                                continuation.yield(.messageEnd(usage: pendingUsage))

                            default:
                                break
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

    private func cohereUsageFromMessageEnd(_ payload: [String: Any]) -> Usage? {
        guard let delta = payload["delta"] as? [String: Any],
              let usage = delta["usage"] as? [String: Any],
              let tokens = usage["tokens"] as? [String: Any] else {
            return nil
        }

        guard let input = cohereIntValue(tokens["input_tokens"]),
              let output = cohereIntValue(tokens["output_tokens"]) else {
            return nil
        }

        return Usage(inputTokens: input, outputTokens: output)
    }

    private func cohereIntValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let num = value as? NSNumber { return num.intValue }
        if let str = value as? String { return Int(str) }
        return nil
    }
}

struct CohereChatResponse: Decodable {
    struct ChatMessage: Decodable {
        struct ContentPart: Decodable {
            let type: String?
            let text: String?
        }

        struct ToolCall: Decodable {
            struct Function: Decodable {
                let name: String?
                let arguments: String?
            }

            let id: String?
            let type: String?
            let function: Function?
        }

        let role: String?
        let content: [ContentPart]?
        let toolCalls: [ToolCall]?
    }

    struct UsageInfo: Decodable {
        struct Tokens: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
        }

        let tokens: Tokens?
    }

    let id: String?
    let finishReason: String?
    let message: ChatMessage?
    let usage: UsageInfo?
}

struct CohereToolCallState {
    var callID: String
    var name: String
    var didEmitStart: Bool
    var argumentsBuffer: String
}
