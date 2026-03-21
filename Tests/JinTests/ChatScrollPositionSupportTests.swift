import XCTest
@testable import Jin

final class ChatScrollPositionSupportTests: XCTestCase {
    func testStoredMessageIDFallsBackToFirstRenderedMessage() {
        let firstRenderedID = UUID()

        let messageID = ChatScrollPositionSupport.storedMessageID(
            topVisibleMessageID: nil,
            renderedMessageIDs: [firstRenderedID, UUID()]
        )

        XCTAssertEqual(messageID, firstRenderedID)
    }

    func testStoredMessageIDPrefersVisibleAnchorEvenAtBottom() {
        let topVisibleID = UUID()

        let messageID = ChatScrollPositionSupport.storedMessageID(
            topVisibleMessageID: topVisibleID,
            renderedMessageIDs: [UUID(), UUID()]
        )

        XCTAssertEqual(messageID, topVisibleID)
    }

    func testRestorationPlanExpandsRenderLimitForSavedMessage() {
        let messageIDs = (0..<80).map { _ in UUID() }
        let targetID = messageIDs[14]

        let plan = ChatScrollPositionSupport.restorationPlan(
            savedMessageID: targetID,
            messageIDs: messageIDs,
            currentRenderLimit: 24,
            pageSize: 40
        )

        XCTAssertEqual(plan.messageRenderLimit, 80)
        XCTAssertEqual(plan.pendingRestoreMessageID, targetID)
        XCTAssertFalse(plan.isPinnedToBottom)
        XCTAssertFalse(plan.clearsStoredAnchor)
    }

    func testRestorationPlanClearsMissingAnchorWhenMessagesExist() {
        let plan = ChatScrollPositionSupport.restorationPlan(
            savedMessageID: UUID(),
            messageIDs: [UUID(), UUID()],
            currentRenderLimit: 24,
            pageSize: 40
        )

        XCTAssertEqual(plan.messageRenderLimit, 24)
        XCTAssertNil(plan.pendingRestoreMessageID)
        XCTAssertTrue(plan.isPinnedToBottom)
        XCTAssertTrue(plan.clearsStoredAnchor)
    }

    func testRestorationPlanKeepsAnchorWhenCacheIsEmpty() {
        let plan = ChatScrollPositionSupport.restorationPlan(
            savedMessageID: UUID(),
            messageIDs: [],
            currentRenderLimit: 24,
            pageSize: 40
        )

        XCTAssertEqual(plan.messageRenderLimit, 24)
        XCTAssertNil(plan.pendingRestoreMessageID)
        XCTAssertTrue(plan.isPinnedToBottom)
        XCTAssertFalse(plan.clearsStoredAnchor)
    }

    func testTopVisibleMessageIDUsesFirstVisibleMessageInViewportOrder() {
        let topID = UUID()
        let lowerID = UUID()

        let messageID = ChatScrollPositionSupport.topVisibleMessageID(
            messageFrames: [
                .init(id: lowerID, minY: 42, maxY: 140),
                .init(id: topID, minY: -18, maxY: 36)
            ],
            viewportHeight: 400
        )

        XCTAssertEqual(messageID, topID)
    }

    func testIsPinnedToBottomUsesToleranceAgainstBottomAnchor() {
        XCTAssertTrue(
            ChatScrollPositionSupport.isPinnedToBottom(
                bottomAnchorMaxY: 712,
                viewportHeight: 680,
                bottomTolerance: 40
            ) ?? false
        )

        XCTAssertFalse(
            ChatScrollPositionSupport.isPinnedToBottom(
                bottomAnchorMaxY: 820,
                viewportHeight: 680,
                bottomTolerance: 40
            ) ?? true
        )
    }
}
