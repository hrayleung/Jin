import Foundation

// MARK: - Shared Responses API Types
//
// These types are used by OpenAIAdapter, XAIAdapter, and OpenAIWebSocketAdapter
// for the OpenAI Responses API wire format.

struct ResponsesAPIFunctionCallState {
    let callID: String
    let name: String
    var argumentsBuffer: String = ""
}

struct ResponsesAPIUsageInfo: Codable {
    let inputTokens: Int?
    let outputTokens: Int?
    let outputTokensDetails: OutputTokensDetails?
    let inputTokensDetails: InputTokensDetails?

    struct OutputTokensDetails: Codable {
        let reasoningTokens: Int?
    }

    struct InputTokensDetails: Codable {
        let cachedTokens: Int?
    }

    var cachedTokens: Int? {
        inputTokensDetails?.cachedTokens
    }

    func toUsage() -> Usage? {
        guard let inputTokens, let outputTokens else { return nil }
        return Usage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            thinkingTokens: outputTokensDetails?.reasoningTokens,
            cachedTokens: cachedTokens
        )
    }
}

struct ResponsesAPIIncompleteDetails: Codable {
    let reason: String?

    static func noticeMarkdown(status: String?, reason: String?) -> String? {
        let normalizedStatus = status?.trimmedLowercased
        let normalizedReason = reason?.trimmedLowercased

        guard normalizedStatus == "incomplete" || normalizedReason != nil else {
            return nil
        }

        let message: String
        switch normalizedReason {
        case "max_output_tokens":
            message = "Response stopped early because the model hit the max output token limit. Increase Max Output Tokens or lower reasoning effort if you want a full answer."
        case let normalizedReason? where !normalizedReason.isEmpty:
            let readableReason = normalizedReason.replacingOccurrences(of: "_", with: " ")
            message = "Response stopped early (\(readableReason))."
        default:
            message = "Response stopped early before completion."
        }

        return "\n\n---\n\n\(message)"
    }
}

// MARK: - Non-streaming Response

struct ResponsesAPIResponse: Codable {
    let id: String
    let output: [ResponsesAPIOutputItem]
    let citations: [String]?
    let usage: ResponsesAPIUsageInfo?
    let status: String?
    let incompleteDetails: ResponsesAPIIncompleteDetails?
}
