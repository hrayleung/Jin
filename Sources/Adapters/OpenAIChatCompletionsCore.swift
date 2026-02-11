import Foundation

enum OpenAIChatCompletionsReasoningField {
    case reasoning
    case reasoningContent
    case reasoningOrReasoningContent
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
                let explicitReasoning = messageReasoning(choice.message, field: reasoningField)
                if let reasoning = explicitReasoning {
                    continuation.yield(.thinkingDelta(.thinking(textDelta: reasoning, signature: nil)))
                }

                if let rawContent = normalized(choice.message.content) {
                    let split = ThinkTagStreamSplitter.splitNonStreaming(rawContent)
                    if explicitReasoning == nil, let thinking = normalized(split.thinking) {
                        continuation.yield(.thinkingDelta(.thinking(textDelta: thinking, signature: nil)))
                    }
                    if let visible = normalized(split.visible) {
                        continuation.yield(.contentDelta(.text(visible)))
                    }
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

            if let sources = sourcesMarkdown(citations: response.citations, searchResults: response.searchResults) {
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
                    var thinkSplitter = ThinkTagStreamSplitter()

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

                            if let delta = deltaReasoning(choice.delta, field: reasoningField) {
                                continuation.yield(.thinkingDelta(.thinking(textDelta: delta, signature: nil)))
                            }

                            if let delta = normalized(choice.delta.content) {
                                let split = thinkSplitter.process(delta)
                                if !split.thinking.isEmpty {
                                    continuation.yield(.thinkingDelta(.thinking(textDelta: split.thinking, signature: nil)))
                                }
                                if !split.visible.isEmpty {
                                    continuation.yield(.contentDelta(.text(split.visible)))
                                }
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

                            if let sources = sourcesMarkdown(citations: pendingCitations, searchResults: pendingSearchResults) {
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

    private static func messageReasoning(
        _ message: OpenAIChatCompletionsResponse.AssistantMessage,
        field: OpenAIChatCompletionsReasoningField
    ) -> String? {
        switch field {
        case .reasoning:
            return normalized(message.reasoning)
        case .reasoningContent:
            return normalized(message.reasoningContent)
        case .reasoningOrReasoningContent:
            return normalized(message.reasoning) ?? normalized(message.reasoningContent)
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
        case .reasoningOrReasoningContent:
            return normalized(delta.reasoning) ?? normalized(delta.reasoningContent)
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

    private static func sourcesMarkdown(
        citations: [String]?,
        searchResults: [OpenAIChatCompletionsSearchResult]?
    ) -> String? {
        func trimmedNonEmpty(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        func escapeMarkdownLinkText(_ value: String) -> String {
            value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "[", with: "\\[")
                .replacingOccurrences(of: "]", with: "\\]")
        }

        if let searchResults {
            var seenURLs = Set<String>()
            var lines: [String] = ["\n\n---\n\n### Sources"]

            var index = 0
            for raw in searchResults {
                guard let url = trimmedNonEmpty(raw.url) else { continue }
                guard seenURLs.insert(url).inserted else { continue }

                index += 1

                let title = trimmedNonEmpty(raw.title) ?? url
                let titleEscaped = escapeMarkdownLinkText(title)
                var line = "\(index). [\(titleEscaped)](<\(url)>)"

                if let snippet = trimmedNonEmpty(raw.snippet) {
                    let oneLine = snippet.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    line += " — \(oneLine)"
                }

                lines.append(line)
            }

            if lines.count > 1 {
                return lines.joined(separator: "\n")
            }
        }

        if let citations {
            var seen = Set<String>()
            var unique: [String] = []
            unique.reserveCapacity(citations.count)
            for raw in citations {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                guard seen.insert(trimmed).inserted else { continue }
                unique.append(trimmed)
            }

            guard !unique.isEmpty else { return nil }

            var lines: [String] = ["\n\n---\n\n### Sources"]
            for (idx, citation) in unique.enumerated() {
                if citation.lowercased().hasPrefix("http") {
                    lines.append("\(idx + 1). <\(citation)>")
                } else {
                    lines.append("\(idx + 1). \(citation)")
                }
            }
            return lines.joined(separator: "\n")
        }

        return nil
    }

    /// Splits leading `<think>...</think>` blocks out of streamed `content` so reasoning models that
    /// embed thinking inline (instead of using `reasoning` fields) still render correctly.
    private struct ThinkTagStreamSplitter {
        private static let startTag = "<think>"
        private static let endTag = "</think>"

        private var isInThinking = false
        private var hasEmittedVisibleNonWhitespace = false
        private var tagBuffer = ""

        mutating func process(_ input: String) -> (visible: String, thinking: String) {
            if tagBuffer.isEmpty, !input.contains("<") {
                if isInThinking {
                    return (visible: "", thinking: input)
                }

                if !hasEmittedVisibleNonWhitespace,
                   input.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil {
                    hasEmittedVisibleNonWhitespace = true
                }
                return (visible: input, thinking: "")
            }

            var visibleOut = ""
            var thinkingOut = ""
            visibleOut.reserveCapacity(input.count)

            func appendLiteral(_ ch: Character) {
                if isInThinking {
                    thinkingOut.append(ch)
                } else {
                    visibleOut.append(ch)
                    if !hasEmittedVisibleNonWhitespace,
                       String(ch).rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil {
                        hasEmittedVisibleNonWhitespace = true
                    }
                }
            }

            func flushTagBufferAsLiteral() {
                guard !tagBuffer.isEmpty else { return }
                for ch in tagBuffer {
                    appendLiteral(ch)
                }
                tagBuffer.removeAll(keepingCapacity: true)
            }

            func isPossibleTagPrefix(_ lower: String) -> Bool {
                Self.startTag.hasPrefix(lower) || Self.endTag.hasPrefix(lower)
            }

            for ch in input {
                if tagBuffer.isEmpty {
                    if ch == "<" {
                        tagBuffer.append(ch)
                        continue
                    }
                    appendLiteral(ch)
                    continue
                }

                tagBuffer.append(ch)
                let lower = tagBuffer.lowercased()

                if lower == Self.startTag {
                    if !isInThinking, !hasEmittedVisibleNonWhitespace {
                        isInThinking = true
                        tagBuffer.removeAll(keepingCapacity: true)
                        continue
                    }
                    flushTagBufferAsLiteral()
                    continue
                }

                if lower == Self.endTag {
                    if isInThinking {
                        isInThinking = false
                        tagBuffer.removeAll(keepingCapacity: true)
                        continue
                    }
                    flushTagBufferAsLiteral()
                    continue
                }

                if isPossibleTagPrefix(lower) {
                    continue
                }

                while !tagBuffer.isEmpty {
                    let currentLower = tagBuffer.lowercased()
                    if isPossibleTagPrefix(currentLower) {
                        break
                    }
                    let first = tagBuffer.removeFirst()
                    appendLiteral(first)
                }
            }

            return (visibleOut, thinkingOut)
        }

        mutating func flushRemainder() -> (visible: String, thinking: String) {
            guard !tagBuffer.isEmpty else { return ("", "") }
            let remainder = tagBuffer
            tagBuffer.removeAll(keepingCapacity: true)
            return isInThinking ? ("", remainder) : (remainder, "")
        }

        static func splitNonStreaming(_ input: String) -> (visible: String, thinking: String?) {
            guard input.lowercased().contains("<think>") else {
                return (input, nil)
            }

            var splitter = ThinkTagStreamSplitter()
            let first = splitter.process(input)
            let remainder = splitter.flushRemainder()
            let visible = first.visible + remainder.visible
            let thinkingRaw = first.thinking + remainder.thinking
            return (visible, thinkingRaw.isEmpty ? nil : thinkingRaw)
        }
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
    let citations: [String]?
    let searchResults: [OpenAIChatCompletionsSearchResult]?

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
    let citations: [String]?
    let searchResults: [OpenAIChatCompletionsSearchResult]?

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

struct OpenAIChatCompletionsSearchResult: Codable {
    let title: String?
    let url: String?
    let snippet: String?
}

struct OpenAIChatCompletionsToolCallState {
    var callID: String
    var name: String
    var argumentsBuffer: String = ""
    var didEmitStart: Bool = false
}
