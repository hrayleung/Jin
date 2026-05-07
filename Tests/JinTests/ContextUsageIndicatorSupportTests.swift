import XCTest
@testable import Jin

final class ContextUsageIndicatorSupportTests: XCTestCase {
    func testPresentationBuildsExistingSummaryHelpAndAccessibilityCopy() {
        let estimate = makeEstimate(
            inputTokens: 12_900,
            contextWindow: 200_000,
            availableInputTokens: 180_000,
            reservedOutputTokens: 20_000
        )

        let presentation = ContextUsageIndicatorSupport.Presentation(
            estimate: estimate,
            modelName: "GPT-5.2"
        )

        XCTAssertEqual(presentation.severity, .normal)
        XCTAssertEqual(presentation.percentageText, "7.2%")
        XCTAssertEqual(presentation.summaryText, "7.2% · 12.9K / 200.0K context used")
        XCTAssertEqual(presentation.titleText, "GPT-5.2 context usage")
        XCTAssertEqual(presentation.usageLine, "12,900 of 180,000 input tokens used")
        XCTAssertEqual(presentation.reserveLine, "20,000 reserved for output from a 200,000-token context window")
        XCTAssertNil(presentation.truncationLine)
        XCTAssertEqual(
            presentation.helpText,
            """
            7.2% · 12.9K / 200.0K context used
            12,900 of 180,000 input tokens used
            20,000 reserved for output from a 200,000-token context window
            """
        )
        XCTAssertEqual(
            presentation.accessibilityValueText,
            "7.2% used, 12,900 of 180,000 input tokens used"
        )
    }

    func testPresentationIncludesTruncationCopyWhenHistoryWasTrimmed() {
        let estimate = makeEstimate(
            inputTokens: 70_000,
            untruncatedInputTokens: 95_000,
            contextWindow: 100_000,
            availableInputTokens: 90_000,
            reservedOutputTokens: 10_000,
            messageCount: 12,
            effectiveMessageCount: 8
        )

        let presentation = ContextUsageIndicatorSupport.Presentation(
            estimate: estimate,
            modelName: nil
        )

        XCTAssertEqual(presentation.severity, .critical)
        XCTAssertEqual(presentation.titleText, "Current model context usage")
        XCTAssertEqual(
            presentation.truncationLine,
            "Older history trimmed: 4 messages, about 25,000 tokens"
        )
        XCTAssertTrue(
            presentation.helpText.hasSuffix("Older history trimmed: 4 messages, about 25,000 tokens")
        )
        XCTAssertTrue(
            presentation.accessibilityValueText.hasSuffix("Older history trimmed: 4 messages, about 25,000 tokens")
        )
    }

    func testSeverityUsesExistingThresholdsAndTruncationOverride() {
        XCTAssertEqual(
            ContextUsageIndicatorSupport.severity(for: makeEstimate(inputTokens: 74, availableInputTokens: 100)),
            .normal
        )
        XCTAssertEqual(
            ContextUsageIndicatorSupport.severity(for: makeEstimate(inputTokens: 75, availableInputTokens: 100)),
            .warning
        )
        XCTAssertEqual(
            ContextUsageIndicatorSupport.severity(for: makeEstimate(inputTokens: 90, availableInputTokens: 100)),
            .critical
        )
        XCTAssertEqual(
            ContextUsageIndicatorSupport.severity(
                for: makeEstimate(
                    inputTokens: 10,
                    untruncatedInputTokens: 10,
                    availableInputTokens: 100,
                    messageCount: 2,
                    effectiveMessageCount: 1
                )
            ),
            .critical
        )
    }

    func testDisplayedFractionPreservesMinimumVisibleProgressForNonZeroUsage() {
        XCTAssertEqual(
            ContextUsageIndicatorSupport.displayedFraction(
                for: makeEstimate(inputTokens: 0, availableInputTokens: 100)
            ),
            0
        )
        XCTAssertEqual(
            ContextUsageIndicatorSupport.displayedFraction(
                for: makeEstimate(inputTokens: 1, availableInputTokens: 10_000)
            ),
            0.025
        )
        XCTAssertEqual(
            ContextUsageIndicatorSupport.displayedFraction(
                for: makeEstimate(inputTokens: 50, availableInputTokens: 100)
            ),
            0.5
        )
    }

    func testCompactTokenCountMatchesExistingFormattingBoundaries() {
        XCTAssertEqual(ContextUsageIndicatorSupport.compactTokenCount(999), "999")
        XCTAssertEqual(ContextUsageIndicatorSupport.compactTokenCount(1_000), "1.0K")
        XCTAssertEqual(ContextUsageIndicatorSupport.compactTokenCount(12_900), "12.9K")
        XCTAssertEqual(ContextUsageIndicatorSupport.compactTokenCount(1_000_000), "1.0M")
        XCTAssertEqual(ContextUsageIndicatorSupport.compactTokenCount(-1_200), "-1.2K")
    }

    private func makeEstimate(
        inputTokens: Int,
        untruncatedInputTokens: Int? = nil,
        contextWindow: Int = 100,
        availableInputTokens: Int = 100,
        reservedOutputTokens: Int = 0,
        messageCount: Int = 1,
        effectiveMessageCount: Int = 1
    ) -> ChatContextUsageEstimate {
        ChatContextUsageEstimate(
            inputTokens: inputTokens,
            untruncatedInputTokens: untruncatedInputTokens ?? inputTokens,
            contextWindow: contextWindow,
            availableInputTokens: availableInputTokens,
            reservedOutputTokens: reservedOutputTokens,
            messageCount: messageCount,
            effectiveMessageCount: effectiveMessageCount
        )
    }
}
