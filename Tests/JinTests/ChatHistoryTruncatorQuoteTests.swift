import XCTest
@testable import Jin

final class ChatHistoryTruncatorQuoteTests: XCTestCase {
    func testApproximateTokenCountIncludesQuotedTextLength() {
        let shortQuote = Message(role: .user, content: [.quote(QuoteContent(quotedText: "tiny"))])
        let longQuote = Message(role: .user, content: [.quote(QuoteContent(quotedText: String(repeating: "long ", count: 40)))])

        XCTAssertLessThan(
            ChatHistoryTruncator.approximateTokenCount(for: shortQuote),
            ChatHistoryTruncator.approximateTokenCount(for: longQuote)
        )
    }

    func testTruncatedHistoryKeepsQuoteHeavyMessageWhenBudgetExactlyFits() {
        let history = makeHistory(quotedText: String(repeating: "Q", count: 40))
        let exactBudget = ChatHistoryTruncator.approximateTokenCount(for: history)

        let truncated = ChatHistoryTruncator.truncatedHistory(
            history,
            contextWindow: exactBudget,
            reservedOutputTokens: 0
        )

        XCTAssertEqual(truncated.map(\.id), history.map(\.id))
    }

    func testTruncatedHistoryDropsQuoteHeavyMessageWhenOneTokenOverBudget() {
        let history = makeHistory(quotedText: String(repeating: "Q", count: 40))
        let exactBudget = ChatHistoryTruncator.approximateTokenCount(for: history)

        let truncated = ChatHistoryTruncator.truncatedHistory(
            history,
            contextWindow: exactBudget - 1,
            reservedOutputTokens: 0
        )

        XCTAssertEqual(truncated.count, 2)
        XCTAssertEqual(truncated.map(\.id), Array(history.suffix(2)).map(\.id))
    }

    func testTruncatedHistoryWithLatestMessageBudgetKeepsNewestMessageOnly() {
        let history = makeHistory(quotedText: String(repeating: "Q", count: 120))
        let latestOnlyBudget = ChatHistoryTruncator.approximateTokenCount(for: history.last!)

        let truncated = ChatHistoryTruncator.truncatedHistory(
            history,
            contextWindow: latestOnlyBudget,
            reservedOutputTokens: 0
        )

        XCTAssertEqual(truncated.count, 1)
        XCTAssertEqual(truncated.first?.id, history.last?.id)
    }

    private func makeHistory(quotedText: String) -> [Message] {
        [
            Message(role: .user, content: [.quote(QuoteContent(quotedText: quotedText))]),
            Message(role: .assistant, content: [.text("Acknowledged")]),
            Message(role: .user, content: [.text("Follow up")])
        ]
    }
}
