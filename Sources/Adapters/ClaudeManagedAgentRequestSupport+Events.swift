import Foundation

extension ClaudeManagedAgentRequestSupport {
    static func eventBodies(
        messages: [Message],
        controls: GenerationControls
    ) throws -> [[String: Any]] {
        if !controls.claudeManagedPendingCustomToolResults.isEmpty {
            return try controls.claudeManagedPendingCustomToolResults.map(customToolResultEvent(from:))
        }

        if let latestUserMessage = messages.last(where: { $0.role == .user }) {
            return [[
                "type": "user.message",
                "content": try userContentBlocks(from: latestUserMessage)
            ]]
        }

        return [[
            "type": "user.message",
            "content": continueContentBlocks()
        ]]
    }

    private static func customToolResultEvent(
        from result: ClaudeManagedAgentPendingToolResult
    ) throws -> [String: Any] {
        var event: [String: Any] = [
            "type": "user.custom_tool_result",
            "custom_tool_use_id": result.eventID,
            "is_error": result.isError
        ]
        if let sessionThreadID = normalizedTrimmedString(result.sessionThreadID) {
            event["session_thread_id"] = sessionThreadID
        }
        event["content"] = resultContentBlocks(result.content)
        return event
    }

    static func continueContentBlocks() -> [[String: Any]] {
        [[
            "type": "text",
            "text": "Continue."
        ]]
    }

    static func sessionEventsBody(events: [[String: Any]]) -> [String: Any] {
        [
            "events": events
        ]
    }

    private static func resultContentBlocks(_ text: String) -> [[String: Any]] {
        let safeText = text.trimmedNonEmpty == nil ? "<empty_content>" : text
        return [[
            "type": "text",
            "text": safeText
        ]]
    }
}
