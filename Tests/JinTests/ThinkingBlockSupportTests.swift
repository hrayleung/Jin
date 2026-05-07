import XCTest
@testable import Jin

final class ThinkingBlockSupportTests: XCTestCase {
    func testDisplayModeFallsBackToExpanded() {
        XCTAssertEqual(ThinkingBlockSupport.displayMode(rawValue: "collapseOnComplete"), .collapseOnComplete)
        XCTAssertEqual(ThinkingBlockSupport.displayMode(rawValue: "alwaysCollapsed"), .alwaysCollapsed)
        XCTAssertEqual(ThinkingBlockSupport.displayMode(rawValue: nil), .expanded)
        XCTAssertEqual(ThinkingBlockSupport.displayMode(rawValue: "unknown"), .expanded)
    }

    func testInitialExpansionForCompletedBlockFollowsDisplayMode() {
        XCTAssertTrue(
            ThinkingBlockSupport.initialExpansionForCompletedBlock(
                displayMode: .expanded
            )
        )
        XCTAssertFalse(
            ThinkingBlockSupport.initialExpansionForCompletedBlock(
                displayMode: .collapseOnComplete
            )
        )
        XCTAssertFalse(
            ThinkingBlockSupport.initialExpansionForCompletedBlock(
                displayMode: .alwaysCollapsed
            )
        )
    }

    func testInitialExpansionForStreamingBlockFollowsDisplayMode() {
        XCTAssertTrue(
            ThinkingBlockSupport.initialExpansionForStreamingBlock(
                displayMode: .expanded
            )
        )
        XCTAssertTrue(
            ThinkingBlockSupport.initialExpansionForStreamingBlock(
                displayMode: .collapseOnComplete
            )
        )
        XCTAssertFalse(
            ThinkingBlockSupport.initialExpansionForStreamingBlock(
                displayMode: .alwaysCollapsed
            )
        )
    }

    func testCompletionExpansionMatchesExistingModeRules() {
        XCTAssertNil(
            ThinkingBlockSupport.shouldExpandAfterThinkingCompletion(
                isComplete: false,
                displayMode: .collapseOnComplete
            )
        )
        XCTAssertEqual(
            ThinkingBlockSupport.shouldExpandAfterThinkingCompletion(
                isComplete: true,
                displayMode: .collapseOnComplete
            ),
            false
        )
        XCTAssertNil(
            ThinkingBlockSupport.shouldExpandAfterThinkingCompletion(
                isComplete: true,
                displayMode: .expanded
            )
        )
        XCTAssertNil(
            ThinkingBlockSupport.shouldExpandAfterThinkingCompletion(
                isComplete: true,
                displayMode: .alwaysCollapsed
            )
        )
    }
}
