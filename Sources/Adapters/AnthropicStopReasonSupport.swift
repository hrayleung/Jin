import Foundation

/// `stop_reason` values that end a Messages API stream without a finished answer.
///
/// `pause_turn` is the server-tool case: the API runs web search / code execution in a
/// server-side loop capped at 10 iterations per request, and a long research turn hits that cap
/// mid-thought — the stream ends with HTTP 200, a trailing `server_tool_use` block and no text.
/// The turn is resumed by re-sending the paused content as the assistant turn, which can
/// itself pause again.
enum AnthropicStopReasonSupport {
    static let pauseTurn = "pause_turn"

    /// Same bound as the docs' reference loop; each continuation allows up to 10 more
    /// server-tool iterations.
    static let maxPauseTurnContinuations = 5

    /// Stop reasons whose `messageEnd` waits until the adapter has decided to resume the turn
    /// or to append a notice first.
    static func defersMessageEnd(for stopReason: String?) -> Bool {
        switch stopReason {
        case "pause_turn", "max_tokens", "model_context_window_exceeded":
            return true
        default:
            return false
        }
    }

    /// The original request with everything the turn has produced so far appended as one
    /// assistant message. A resumed response starts with the result block for the previous
    /// response's trailing `server_tool_use`, so concatenating the segments rebuilds the turn
    /// as a single uninterrupted response would have returned it. The tools array must stay
    /// the same: the API rejects a resume whose pending server tool is no longer defined.
    static func continuationBody(
        from body: [String: Any],
        pausedContent: [[String: Any]],
        containerID: String?
    ) -> [String: Any] {
        var continued = body
        var messages = (body["messages"] as? [[String: Any]]) ?? []
        messages.append(["role": "assistant", "content": pausedContent])
        continued["messages"] = messages
        if let containerID, continued["container"] == nil {
            continued["container"] = containerID
        }
        return continued
    }

    static func noticeMarkdown(for stopReason: String?, pauseTurnContinuations: Int) -> String? {
        let message: String
        switch stopReason {
        case "max_tokens":
            message = "Response stopped early because the model hit the max output token limit. Increase Max Output Tokens or lower reasoning effort if you want a full answer."
        case "model_context_window_exceeded":
            message = "Response stopped early because the conversation filled the model's context window. Start a new chat or remove earlier messages to get a full answer."
        case "pause_turn":
            message = "Response stopped early because Claude was still running server tools after \(pauseTurnContinuations) automatic continuations. Reply “continue” to let it finish."
        default:
            return nil
        }
        return "\n\n---\n\n\(message)"
    }
}
