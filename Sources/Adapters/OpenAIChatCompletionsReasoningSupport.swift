import Foundation

enum OpenAIChatCompletionsReasoningSupport {
    static func messageReasoning(
        _ message: OpenAIChatCompletionsResponse.AssistantMessage,
        field: OpenAIChatCompletionsReasoningField
    ) -> String? {
        extractReasoning(
            reasoning: message.reasoning,
            reasoningContent: message.reasoningContent,
            reasoningDetails: message.reasoningDetails,
            field: field
        )
    }

    static func responseChoiceReasoning(
        _ choice: OpenAIChatCompletionsResponse.Choice,
        field: OpenAIChatCompletionsReasoningField
    ) -> String? {
        extractReasoning(
            reasoning: choice.reasoning,
            reasoningContent: choice.reasoningContent,
            reasoningDetails: choice.reasoningDetails,
            field: field
        )
    }

    static func deltaReasoning(
        _ delta: OpenAIChatCompletionsChunk.Delta,
        field: OpenAIChatCompletionsReasoningField
    ) -> String? {
        extractReasoning(
            reasoning: delta.reasoning,
            reasoningContent: delta.reasoningContent,
            reasoningDetails: delta.reasoningDetails,
            field: field
        )
    }

    static func chunkChoiceReasoning(
        _ choice: OpenAIChatCompletionsChunk.Choice,
        field: OpenAIChatCompletionsReasoningField
    ) -> String? {
        extractReasoning(
            reasoning: choice.reasoning,
            reasoningContent: choice.reasoningContent,
            reasoningDetails: choice.reasoningDetails,
            field: field
        )
    }

    static func incrementalDelta(candidate: String, previousSnapshot: String) -> String {
        guard !candidate.isEmpty else { return "" }
        guard !previousSnapshot.isEmpty else { return candidate }

        if candidate == previousSnapshot {
            return ""
        }

        if candidate.hasPrefix(previousSnapshot) {
            return String(candidate.dropFirst(previousSnapshot.count))
        }

        return candidate
    }

    /// Extracts reasoning text from any type that carries the standard
    /// `reasoning` / `reasoningContent` / `reasoningDetails` fields.
    private static func extractReasoning(
        reasoning: String?,
        reasoningContent: String?,
        reasoningDetails: [[String: AnyCodable]]?,
        field: OpenAIChatCompletionsReasoningField
    ) -> String? {
        switch field {
        case .reasoning:
            return normalized(reasoning)
                ?? reasoningDetailsText(reasoningDetails)
        case .reasoningContent:
            return normalized(reasoningContent)
                ?? reasoningDetailsText(reasoningDetails)
        case .reasoningOrReasoningContent:
            return normalized(reasoning)
                ?? normalized(reasoningContent)
                ?? reasoningDetailsText(reasoningDetails)
        }
    }

    private static func reasoningDetailsText(_ details: [[String: AnyCodable]]?) -> String? {
        guard let details, !details.isEmpty else { return nil }

        var parts: [String] = []
        parts.reserveCapacity(details.count)

        func appendCandidate(_ value: Any?) {
            guard let value else { return }

            if let str = value as? String {
                if normalized(str) != nil {
                    parts.append(str)
                }
                return
            }

            if let dict = value as? [String: Any] {
                appendCandidate(dict["text"])
                appendCandidate(dict["content"])
                appendCandidate(dict["reasoning"])
                appendCandidate(dict["summary"])
                return
            }

            if let array = value as? [Any] {
                for item in array {
                    appendCandidate(item)
                }
            }
        }

        for detail in details {
            appendCandidate(detail["text"]?.value)
            appendCandidate(detail["content"]?.value)
            appendCandidate(detail["reasoning"]?.value)
            appendCandidate(detail["summary"]?.value)
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n")
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.trimmedNonEmpty == nil ? nil : value
    }
}
