import Foundation

struct OpenAIChatCompletionsResponse: Decodable {
    let id: String
    let choices: [Choice]
    let usage: UsageInfo?
    let citations: [String]?
    let searchResults: [OpenAIChatCompletionsSearchResult]?

    struct Choice: Decodable {
        let message: AssistantMessage
        let finishReason: String?
        let reasoning: String?
        let reasoningContent: String?
        let reasoningDetails: [[String: AnyCodable]]?
    }

    struct AssistantMessage: Decodable {
        let role: String?
        let content: OpenAIChatCompletionsContent?
        let reasoning: String?
        let reasoningContent: String?
        let reasoningDetails: [[String: AnyCodable]]?
        let toolCalls: [ToolCall]?
        let images: [GeneratedImage]?
    }

    struct ToolCall: Decodable {
        let id: String?
        let type: String?
        let function: Function?

        struct Function: Decodable {
            let name: String?
            let arguments: String?
        }
    }

    struct GeneratedImage: Decodable {
        let type: String?
        let imageURL: ImageURL?
        let mimeType: String?

        var resolvedImageURL: String? {
            imageURL?.url
        }

        enum CodingKeys: String, CodingKey {
            case type
            case imageURL = "imageUrl"
            case mimeType
        }
    }

    struct ImageURL: Decodable {
        let url: String

        private enum CodingKeys: String, CodingKey {
            case url
        }

        init(from decoder: Decoder) throws {
            let singleValue = try decoder.singleValueContainer()
            if let raw = try? singleValue.decode(String.self) {
                url = raw
                return
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)
            url = try container.decode(String.self, forKey: .url)
        }
    }

    struct UsageInfo: Decodable {
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

struct OpenAIChatCompletionsChunk: Decodable {
    let id: String?
    let choices: [Choice]
    let usage: OpenAIChatCompletionsResponse.UsageInfo?
    let citations: [String]?
    let searchResults: [OpenAIChatCompletionsSearchResult]?

    struct Choice: Decodable {
        let index: Int?
        let delta: Delta
        let finishReason: String?
        let reasoning: String?
        let reasoningContent: String?
        let reasoningDetails: [[String: AnyCodable]]?
    }

    struct Delta: Decodable {
        let role: String?
        let content: OpenAIChatCompletionsContent?
        let reasoning: String?
        let reasoningContent: String?
        let reasoningDetails: [[String: AnyCodable]]?
        let toolCalls: [ToolCallDelta]?
        let images: [OpenAIChatCompletionsResponse.GeneratedImage]?
    }

    struct ToolCallDelta: Decodable {
        let index: Int?
        let id: String?
        let type: String?
        let function: FunctionDelta?

        struct FunctionDelta: Decodable {
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

struct OpenAIChatCompletionsSearchResult: Codable {
    let title: String?
    let url: String?
    let snippet: String?
}

struct OpenAIChatCompletionsContent: Decodable {
    let text: String?
    let thinking: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            text = nil
            thinking = nil
            return
        }

        if let raw = try? container.decode(String.self) {
            text = raw
            thinking = nil
            return
        }

        let chunks = try container.decode([OpenAIChatCompletionsContentChunk].self)
        var textParts: [String] = []
        var thinkingParts: [String] = []

        for chunk in chunks {
            if chunk.isThinkingChunk {
                if let fragment = chunk.thinkingFragment {
                    thinkingParts.append(fragment)
                }
            } else if let fragment = chunk.visibleTextFragment {
                textParts.append(fragment)
            }
        }

        let joinedText = textParts.joined()
        let joinedThinking = thinkingParts.joined()
        text = joinedText.isEmpty ? nil : joinedText
        thinking = joinedThinking.isEmpty ? nil : joinedThinking
    }
}

private struct OpenAIChatCompletionsContentChunk: Decodable {
    let type: String?
    let text: String?
    let content: String?
    let thinkingText: String?
    let thinkingChunks: [OpenAIChatCompletionsContentChunk]?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case content
        case thinking
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        thinkingText = try? container.decode(String.self, forKey: .thinking)
        thinkingChunks = try? container.decode([OpenAIChatCompletionsContentChunk].self, forKey: .thinking)
    }

    var isThinkingChunk: Bool {
        type?.caseInsensitiveCompare("thinking") == .orderedSame
    }

    var visibleTextFragment: String? {
        normalizedContentFragment(text) ?? normalizedContentFragment(content)
    }

    var thinkingFragment: String? {
        var parts: [String] = []
        if let thinkingText = normalizedContentFragment(thinkingText) {
            parts.append(thinkingText)
        }
        if let thinkingChunks {
            for chunk in thinkingChunks {
                if let nested = chunk.visibleTextFragment ?? chunk.thinkingFragment {
                    parts.append(nested)
                }
            }
        }
        return parts.isEmpty ? nil : parts.joined()
    }
}

private func normalizedContentFragment(_ value: String?) -> String? {
    guard let value else { return nil }
    return value.trimmedNonEmpty == nil ? nil : value
}

struct OpenAIChatCompletionsToolCallState {
    var callID: String
    var name: String
    var argumentsBuffer: String = ""
    var didEmitStart: Bool = false
}
