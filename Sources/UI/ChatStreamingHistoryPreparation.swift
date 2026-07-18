import Foundation

extension ChatStreamingOrchestrator {
    static func prepareHistory(from ctx: SessionContext) -> [Message] {
        // Runs on the detached streaming task — keep decode off MainActor.
        let decoder = JSONDecoder()
        var history = ctx.messageSnapshots
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .compactMap { $0.toDomain(using: decoder) }

        if let systemPrompt = ctx.systemPrompt, !systemPrompt.isEmpty {
            history.insert(Message(role: .system, content: [.text(systemPrompt)]), at: 0)
        }

        if let maxMessages = ctx.maxHistoryMessages, ctx.shouldTruncateMessages {
            history = ChatContextUsageEstimator.historyCappedByMessageCount(
                history,
                maxHistoryMessages: maxMessages
            )
        }

        if ctx.shouldTruncateMessages {
            history = ChatHistoryTruncator.truncatedHistory(
                history,
                contextWindow: ctx.modelContextWindow,
                reservedOutputTokens: ctx.reservedOutputTokens
            )
        }

        // Replace any attachments whose files were deleted/moved with text
        // placeholders so a single lost attachment can't abort the whole request.
        return MissingAttachmentSanitizer.sanitize(history)
    }
}
