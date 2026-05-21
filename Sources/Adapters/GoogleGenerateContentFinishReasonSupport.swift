import Foundation

enum GoogleGenerateContentFinishReasonSupport {
    private static let normalReasons: Set<String> = [
        "",
        "STOP",
        "FINISH_REASON_UNSPECIFIED",
    ]

    private static let filteredReasons: Set<String> = [
        "SAFETY",
        "BLOCKED",
        "BLOCKLIST",
        "PROHIBITED_CONTENT",
        "SPII",
        "RECITATION",
        "MODEL_ARMOR",
        "IMAGE_SAFETY",
        "IMAGE_PROHIBITED_CONTENT",
        "IMAGE_RECITATION",
    ]

    static func isCandidateContentFiltered(_ candidate: GoogleGenerateContentResponse.Candidate) -> Bool {
        filteredReasons.contains(normalized(candidate.finishReason))
    }

    static func terminalError(
        in response: GoogleGenerateContentResponse,
        providerName: String
    ) -> LLMError? {
        if response.promptFeedback?.blockReason != nil {
            return .contentFiltered
        }

        for candidate in response.candidates ?? [] {
            if let error = terminalError(for: candidate, providerName: providerName) {
                return error
            }
        }

        return nil
    }

    static func terminalError(
        for candidate: GoogleGenerateContentResponse.Candidate,
        providerName: String
    ) -> LLMError? {
        let reason = normalized(candidate.finishReason)
        guard !normalReasons.contains(reason) else { return nil }

        if filteredReasons.contains(reason) {
            return .contentFiltered
        }

        let detail = candidate.finishMessage?.trimmedNonEmpty
        let message = terminalMessage(
            reason: reason,
            finishMessage: detail,
            providerName: providerName
        )
        return .providerError(code: "google_finish_reason", message: message)
    }

    private static func terminalMessage(
        reason: String,
        finishMessage: String?,
        providerName: String
    ) -> String {
        let base: String
        switch reason {
        case "MAX_TOKENS":
            base = "\(providerName) stopped before completing the answer because it reached the configured max output tokens. Increase max output tokens or reduce thinking level, then retry."
        case "MALFORMED_FUNCTION_CALL":
            base = "\(providerName) stopped because the model generated a malformed function call."
        case "UNEXPECTED_TOOL_CALL":
            base = "\(providerName) stopped because the model generated a tool call that was not valid for this request."
        case "TOO_MANY_TOOL_CALLS":
            base = "\(providerName) stopped because the model generated too many tool calls."
        case "MISSING_THOUGHT_SIGNATURE":
            base = "\(providerName) stopped because a required thought signature was missing from the request context."
        case "NO_IMAGE":
            base = "\(providerName) stopped because the model was expected to generate an image but did not return one."
        case "IMAGE_OTHER", "OTHER":
            base = "\(providerName) stopped generation before returning a complete answer."
        default:
            base = "\(providerName) stopped generation with finish reason \(reason)."
        }

        guard let finishMessage else { return base }
        return "\(base) \(finishMessage)"
    }

    private static func normalized(_ reason: String?) -> String {
        reason?.trimmedNonEmpty?.uppercased() ?? ""
    }
}
