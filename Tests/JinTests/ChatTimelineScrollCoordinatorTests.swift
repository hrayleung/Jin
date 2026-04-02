import XCTest
@testable import Jin

final class ChatTimelineScrollCoordinatorTests: XCTestCase {
    func testRefreshPlanIncrementsGenerationWhenMaintainingBottomAnchor() {
        let plan = ChatTimelineScrollCoordinator.refreshPlan(
            currentGeneration: 4,
            shouldMaintainPinnedBottomAnchor: true,
            delays: [0, 0.12, 0.35]
        )

        XCTAssertEqual(plan?.generation, 5)
        XCTAssertEqual(plan?.delays, [0, 0.12, 0.35])
    }

    func testRefreshPlanReturnsNilWhenBottomAnchorShouldNotBeMaintained() {
        let plan = ChatTimelineScrollCoordinator.refreshPlan(
            currentGeneration: 4,
            shouldMaintainPinnedBottomAnchor: false,
            delays: [0.12]
        )

        XCTAssertNil(plan)
    }

    func testContentHeightChangeActionSchedulesRefreshWhenHeightMeaningfullyChangesWhileMaintainingBottomAnchor() {
        let action = ChatTimelineScrollCoordinator.contentHeightChangeAction(
            newHeight: 420,
            previousHeight: 360,
            shouldMaintainPinnedBottomAnchor: true
        )

        XCTAssertEqual(action?.measuredHeight, 420)
        XCTAssertTrue(action?.shouldScheduleRefresh == true)
    }

    func testContentHeightChangeActionUpdatesHeightWithoutSchedulingWhenBottomAnchorShouldNotBeMaintained() {
        let action = ChatTimelineScrollCoordinator.contentHeightChangeAction(
            newHeight: 420,
            previousHeight: 360,
            shouldMaintainPinnedBottomAnchor: false
        )

        XCTAssertEqual(action?.measuredHeight, 420)
        XCTAssertFalse(action?.shouldScheduleRefresh == true)
    }

    func testContentHeightChangeActionIgnoresInsignificantHeightChanges() {
        let action = ChatTimelineScrollCoordinator.contentHeightChangeAction(
            newHeight: 400.2,
            previousHeight: 400,
            shouldMaintainPinnedBottomAnchor: true
        )

        XCTAssertNil(action)
    }

    func testShouldPerformRefreshAllowsContentGrowthCompensationWhileMaintainingBottomAnchor() {
        XCTAssertTrue(
            ChatTimelineScrollCoordinator.shouldPerformRefresh(
                expectedGeneration: 5,
                currentGeneration: 5,
                shouldMaintainPinnedBottomAnchor: true
            )
        )
        XCTAssertFalse(
            ChatTimelineScrollCoordinator.shouldPerformRefresh(
                expectedGeneration: 5,
                currentGeneration: 6,
                shouldMaintainPinnedBottomAnchor: true
            )
        )
        XCTAssertFalse(
            ChatTimelineScrollCoordinator.shouldPerformRefresh(
                expectedGeneration: 5,
                currentGeneration: 5,
                shouldMaintainPinnedBottomAnchor: false
            )
        )
    }

    func testShouldScrollToBottomOnlyWhenContentOverflowsUnlessForced() {
        XCTAssertFalse(
            ChatTimelineScrollCoordinator.shouldScrollToBottom(
                lastMeasuredContentHeight: 399.4,
                viewportHeight: 400
            )
        )
        XCTAssertTrue(
            ChatTimelineScrollCoordinator.shouldScrollToBottom(
                lastMeasuredContentHeight: 401,
                viewportHeight: 400
            )
        )
        XCTAssertTrue(
            ChatTimelineScrollCoordinator.shouldScrollToBottom(
                lastMeasuredContentHeight: 200,
                viewportHeight: 400,
                allowWhenContentFits: true
            )
        )
    }

    func testInvalidatedRefreshGenerationBumpsGenerationToCancelPendingRefreshes() {
        XCTAssertEqual(
            ChatTimelineScrollCoordinator.invalidatedRefreshGeneration(current: 9),
            10
        )
    }

    func testPinnedBottomToleranceStaysConservativeEvenWithTallComposer() {
        XCTAssertEqual(
            ChatTimelineScrollCoordinator.pinnedBottomTolerance(composerHeight: 0),
            36
        )
        XCTAssertEqual(
            ChatTimelineScrollCoordinator.pinnedBottomTolerance(composerHeight: 80),
            36
        )
        XCTAssertEqual(
            ChatTimelineScrollCoordinator.pinnedBottomTolerance(composerHeight: 160),
            40
        )
        XCTAssertEqual(
            ChatTimelineScrollCoordinator.pinnedBottomTolerance(composerHeight: 600),
            64
        )
    }
}
