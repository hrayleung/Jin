import Foundation

struct ChatContextUsageEstimate: Equatable, Sendable {
    let inputTokens: Int
    let untruncatedInputTokens: Int
    let contextWindow: Int
    let availableInputTokens: Int
    let reservedOutputTokens: Int
    let messageCount: Int
    let effectiveMessageCount: Int

    var truncatedInputTokens: Int {
        max(0, untruncatedInputTokens - inputTokens)
    }

    var truncatedMessageCount: Int {
        max(0, messageCount - effectiveMessageCount)
    }

    var didTruncateHistory: Bool {
        truncatedInputTokens > 0 || truncatedMessageCount > 0
    }

    var usageFraction: Double {
        guard availableInputTokens > 0 else {
            return inputTokens > 0 ? 1 : 0
        }
        return Double(inputTokens) / Double(availableInputTokens)
    }

    var clampedUsageFraction: Double {
        min(max(usageFraction, 0), 1)
    }
}

enum ChatContextUsageEstimator {
    static func estimate(
        history: [Message],
        draftMessageParts: [ContentPart],
        systemPrompt: String?,
        maxHistoryMessages: Int?,
        shouldTruncateMessages: Bool,
        contextWindow: Int,
        reservedOutputTokens: Int
    ) -> ChatContextUsageEstimate {
        let preparedHistory = preparedHistory(
            history: history,
            draftMessageParts: draftMessageParts,
            systemPrompt: systemPrompt,
            maxHistoryMessages: maxHistoryMessages,
            shouldTruncateMessages: shouldTruncateMessages
        )

        let untruncatedInputTokens = ChatHistoryTruncator.approximateTokenCount(for: preparedHistory)
        let effectiveHistory: [Message]
        if shouldTruncateMessages {
            effectiveHistory = ChatHistoryTruncator.truncatedHistory(
                preparedHistory,
                contextWindow: contextWindow,
                reservedOutputTokens: reservedOutputTokens
            )
        } else {
            effectiveHistory = preparedHistory
        }

        let effectiveReserved = min(max(0, reservedOutputTokens), max(0, contextWindow))
        let availableInputTokens = max(0, contextWindow - effectiveReserved)

        return ChatContextUsageEstimate(
            inputTokens: ChatHistoryTruncator.approximateTokenCount(for: effectiveHistory),
            untruncatedInputTokens: untruncatedInputTokens,
            contextWindow: max(0, contextWindow),
            availableInputTokens: availableInputTokens,
            reservedOutputTokens: effectiveReserved,
            messageCount: preparedHistory.count,
            effectiveMessageCount: effectiveHistory.count
        )
    }

    static func preparedHistory(
        history: [Message],
        draftMessageParts: [ContentPart],
        systemPrompt: String?,
        maxHistoryMessages: Int?,
        shouldTruncateMessages: Bool
    ) -> [Message] {
        var preparedHistory = history

        if let normalizedSystemPrompt = normalizedSystemPrompt(systemPrompt) {
            preparedHistory.insert(
                Message(role: .system, content: [.text(normalizedSystemPrompt)]),
                at: 0
            )
        }

        if !draftMessageParts.isEmpty {
            preparedHistory.append(
                Message(role: .user, content: draftMessageParts)
            )
        }

        if shouldTruncateMessages,
           let maxHistoryMessages {
            preparedHistory = historyCappedByMessageCount(
                preparedHistory,
                maxHistoryMessages: maxHistoryMessages
            )
        }

        return preparedHistory
    }

    static func historyCappedByMessageCount(
        _ history: [Message],
        maxHistoryMessages: Int
    ) -> [Message] {
        let messageLimit = max(0, min(maxHistoryMessages, history.count))
        guard history.count > messageLimit else { return history }

        let systemMessages = history.prefix(while: { $0.role == .system })
        let nonSystemMessages = history.drop(while: { $0.role == .system })
        let keptSystem = Array(systemMessages.prefix(messageLimit))
        let nonSystemBudget = max(0, messageLimit - keptSystem.count)
        let keptMessages = Array(nonSystemMessages.suffix(nonSystemBudget))
        return keptSystem + keptMessages
    }

    private static func normalizedSystemPrompt(_ systemPrompt: String?) -> String? {
        let trimmed = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
