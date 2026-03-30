import XCTest
@testable import Jin

final class ChatTimelineScrollCoordinatorTests: XCTestCase {
    func testRefreshPlanIncrementsGenerationWhenPinnedToBottom() {
        let plan = ChatTimelineScrollCoordinator.refreshPlan(
            currentGeneration: 4,
            isPinnedToBottom: true,
            delays: [0, 0.12, 0.35]
        )

        XCTAssertEqual(plan?.generation, 5)
        XCTAssertEqual(plan?.delays, [0, 0.12, 0.35])
    }

    func testRefreshPlanReturnsNilWhenNotPinnedToBottom() {
        let plan = ChatTimelineScrollCoordinator.refreshPlan(
            currentGeneration: 4,
            isPinnedToBottom: false,
            delays: [0.12]
        )

        XCTAssertNil(plan)
    }

    func testContentHeightChangeActionSchedulesRefreshWhenHeightMeaningfullyChangesWhilePinned() {
        let action = ChatTimelineScrollCoordinator.contentHeightChangeAction(
            newHeight: 420,
            previousHeight: 360,
            isPinnedToBottom: true
        )

        XCTAssertEqual(action?.measuredHeight, 420)
        XCTAssertTrue(action?.shouldScheduleRefresh == true)
    }

    func testContentHeightChangeActionUpdatesHeightWithoutSchedulingWhenNotPinned() {
        let action = ChatTimelineScrollCoordinator.contentHeightChangeAction(
            newHeight: 420,
            previousHeight: 360,
            isPinnedToBottom: false
        )

        XCTAssertEqual(action?.measuredHeight, 420)
        XCTAssertFalse(action?.shouldScheduleRefresh == true)
    }

    func testContentHeightChangeActionIgnoresInsignificantHeightChanges() {
        let action = ChatTimelineScrollCoordinator.contentHeightChangeAction(
            newHeight: 400.2,
            previousHeight: 400,
            isPinnedToBottom: true
        )

        XCTAssertNil(action)
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
}
