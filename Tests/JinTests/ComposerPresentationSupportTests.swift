import XCTest
@testable import Jin

final class ComposerPresentationSupportTests: XCTestCase {
    func testDraftTextMetricsCountWordsCharactersAndBuildSummary() {
        XCTAssertEqual(
            ComposerDraftTextMetrics(messageText: "").summaryText,
            "0 words · 0 characters"
        )

        let singleWord = ComposerDraftTextMetrics(messageText: "  hello  ")
        XCTAssertEqual(singleWord.wordCount, 1)
        XCTAssertEqual(singleWord.characterCount, 9)
        XCTAssertEqual(singleWord.summaryText, "1 word · 9 characters")

        let multiline = ComposerDraftTextMetrics(messageText: "hello\nworld\tagain")
        XCTAssertEqual(multiline.wordCount, 3)
        XCTAssertEqual(multiline.characterCount, 17)
        XCTAssertEqual(multiline.summaryText, "3 words · 17 characters")
    }

    func testSendButtonPresentationMatchesSendAndStopStates() {
        let ready = ComposerSendButtonPresentation(
            usesCommandReturn: true,
            isBusy: false,
            canSendDraft: true,
            isRecording: false,
            isTranscribing: false
        )

        XCTAssertFalse(ready.isDisabled)
        XCTAssertEqual(ready.expandedTitle, "Send")
        XCTAssertEqual(ready.expandedSystemImage, "arrow.up")
        XCTAssertEqual(ready.compactSystemImage, "arrow.up.circle.fill")
        XCTAssertEqual(ready.shortcutGlyph, "⌘↩")

        let busy = ComposerSendButtonPresentation(
            usesCommandReturn: false,
            isBusy: true,
            canSendDraft: false,
            isRecording: false,
            isTranscribing: false
        )

        XCTAssertFalse(busy.isDisabled)
        XCTAssertEqual(busy.expandedTitle, "Stop")
        XCTAssertEqual(busy.expandedSystemImage, "stop.fill")
        XCTAssertEqual(busy.compactSystemImage, "stop.circle.fill")
        XCTAssertEqual(busy.shortcutGlyph, "↩")
    }

    func testSendButtonPresentationDisablesOnlyBlockedCompositions() {
        XCTAssertTrue(
            ComposerSendButtonPresentation(
                usesCommandReturn: false,
                isBusy: false,
                canSendDraft: false,
                isRecording: false,
                isTranscribing: false
            ).isDisabled
        )

        XCTAssertTrue(
            ComposerSendButtonPresentation(
                usesCommandReturn: false,
                isBusy: false,
                canSendDraft: true,
                isRecording: true,
                isTranscribing: false
            ).isDisabled
        )

        XCTAssertTrue(
            ComposerSendButtonPresentation(
                usesCommandReturn: false,
                isBusy: false,
                canSendDraft: true,
                isRecording: false,
                isTranscribing: true
            ).isDisabled
        )
    }

    func testCompactComposerTextHeightMetricsClampAndThresholdUpdates() {
        XCTAssertEqual(
            CompactComposerTextHeightMetrics.clampedHeight(for: 12),
            CompactComposerTextHeightMetrics.minimumHeight
        )
        XCTAssertEqual(
            CompactComposerTextHeightMetrics.clampedHeight(for: 240),
            CompactComposerTextHeightMetrics.maximumHeight
        )
        XCTAssertEqual(
            CompactComposerTextHeightMetrics.clampedHeight(for: 72),
            72
        )

        XCTAssertNil(
            CompactComposerTextHeightMetrics.updatedHeight(
                current: 72,
                measured: 72.4
            )
        )
        XCTAssertEqual(
            CompactComposerTextHeightMetrics.updatedHeight(
                current: 72,
                measured: 72.6
            ),
            72.6
        )
    }
}
