import XCTest
@testable import Jin

final class ChatContextUsageEstimatorTests: XCTestCase {
    func testEstimateIncludesSystemPromptAndDraftMessage() {
        let history = [
            Message(role: .user, content: [.text("hello there")]),
            Message(role: .assistant, content: [.text("general kenobi")])
        ]
        let draftParts: [ContentPart] = [.text("follow up question")]

        let estimate = ChatContextUsageEstimator.estimate(
            history: history,
            draftMessageParts: draftParts,
            systemPrompt: "Be concise.",
            maxHistoryMessages: nil,
            shouldTruncateMessages: false,
            contextWindow: 1_000,
            reservedOutputTokens: 200
        )

        let preparedHistory = ChatContextUsageEstimator.preparedHistory(
            history: history,
            draftMessageParts: draftParts,
            systemPrompt: "Be concise.",
            maxHistoryMessages: nil,
            shouldTruncateMessages: false
        )

        XCTAssertEqual(estimate.messageCount, preparedHistory.count)
        XCTAssertEqual(
            estimate.inputTokens,
            ChatHistoryTruncator.approximateTokenCount(for: preparedHistory)
        )
        XCTAssertEqual(estimate.untruncatedInputTokens, estimate.inputTokens)
        XCTAssertEqual(estimate.availableInputTokens, 800)
        XCTAssertEqual(estimate.reservedOutputTokens, 200)
        XCTAssertFalse(estimate.didTruncateHistory)
    }

    func testEstimateReportsTruncationWhenBudgetIsExceeded() {
        let history = [
            Message(role: .user, content: [.text(String(repeating: "a", count: 200))]),
            Message(role: .assistant, content: [.text(String(repeating: "b", count: 200))]),
            Message(role: .user, content: [.text(String(repeating: "c", count: 200))])
        ]

        let estimate = ChatContextUsageEstimator.estimate(
            history: history,
            draftMessageParts: [.text(String(repeating: "d", count: 120))],
            systemPrompt: nil,
            maxHistoryMessages: nil,
            shouldTruncateMessages: true,
            contextWindow: 120,
            reservedOutputTokens: 20
        )

        XCTAssertTrue(estimate.didTruncateHistory)
        XCTAssertGreaterThan(estimate.truncatedInputTokens, 0)
        XCTAssertGreaterThan(estimate.truncatedMessageCount, 0)
        XCTAssertLessThan(estimate.effectiveMessageCount, estimate.messageCount)
        XCTAssertLessThanOrEqual(estimate.inputTokens, estimate.availableInputTokens)
        XCTAssertEqual(estimate.clampedUsageFraction, estimate.usageFraction, accuracy: 0.0001)
    }

    func testPreparedHistoryClampsNegativeMaxHistoryMessagesToZero() {
        let history = [
            Message(role: .user, content: [.text("hello there")]),
            Message(role: .assistant, content: [.text("general kenobi")])
        ]

        let preparedHistory = ChatContextUsageEstimator.preparedHistory(
            history: history,
            draftMessageParts: [],
            systemPrompt: "Be concise.",
            maxHistoryMessages: -3,
            shouldTruncateMessages: true
        )

        XCTAssertTrue(preparedHistory.isEmpty)
    }

    func testHistoryCappedByMessageCountCountsSystemMessagesTowardLimit() {
        let history = [
            Message(role: .system, content: [.text("rule 1")]),
            Message(role: .system, content: [.text("rule 2")]),
            Message(role: .user, content: [.text("hello there")]),
            Message(role: .assistant, content: [.text("general kenobi")])
        ]

        let capped = ChatContextUsageEstimator.historyCappedByMessageCount(
            history,
            maxHistoryMessages: 2
        )

        XCTAssertEqual(capped.count, 2)
        XCTAssertEqual(capped.map(\.role), [.system, .system])
    }

    func testIndicatorSummaryTextMatchesCompactBubbleFormat() {
        let estimate = ChatContextUsageEstimate(
            inputTokens: 12_900,
            untruncatedInputTokens: 12_900,
            contextWindow: 200_000,
            availableInputTokens: 200_000,
            reservedOutputTokens: 0,
            messageCount: 8,
            effectiveMessageCount: 8
        )

        XCTAssertEqual(
            ContextUsageIndicatorView.summaryText(for: estimate),
            "6.4% · 12.9K / 200.0K context used"
        )
    }
}
