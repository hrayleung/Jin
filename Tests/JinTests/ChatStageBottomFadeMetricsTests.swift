import XCTest
@testable import Jin

final class ChatStageBottomFadeMetricsTests: XCTestCase {
    func testFadeHeightUsesCompactHeightWhenComposerIsHidden() {
        XCTAssertEqual(
            ChatStageBottomFadeMetrics.fadeHeight(composerHeight: 320, isComposerHidden: true),
            64
        )
    }

    func testFadeHeightKeepsMinimumWhenComposerIsVisible() {
        XCTAssertEqual(
            ChatStageBottomFadeMetrics.fadeHeight(composerHeight: 20, isComposerHidden: false),
            88
        )
    }

    func testFadeHeightTracksVisibleComposerWithExtraCoverage() {
        XCTAssertEqual(
            ChatStageBottomFadeMetrics.fadeHeight(composerHeight: 112, isComposerHidden: false),
            132
        )
    }

    func testFadeHeightCapsTallComposerCoverage() {
        XCTAssertEqual(
            ChatStageBottomFadeMetrics.fadeHeight(composerHeight: 240, isComposerHidden: false),
            180
        )
    }

    func testNormalizedComposerHeightAvoidsFractionalStateChurn() {
        XCTAssertEqual(ChatStageBottomFadeMetrics.normalizedComposerHeight(100.49), 100)
        XCTAssertEqual(ChatStageBottomFadeMetrics.normalizedComposerHeight(100.5), 101)
        XCTAssertEqual(ChatStageBottomFadeMetrics.normalizedComposerHeight(-8), 0)
        XCTAssertEqual(ChatStageBottomFadeMetrics.normalizedComposerHeight(.infinity), 0)
        XCTAssertEqual(ChatStageBottomFadeMetrics.normalizedComposerHeight(-.infinity), 0)
        XCTAssertEqual(ChatStageBottomFadeMetrics.normalizedComposerHeight(.nan), 0)
    }
}
