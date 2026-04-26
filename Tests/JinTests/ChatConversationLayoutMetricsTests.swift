import XCTest
@testable import Jin

final class ChatConversationLayoutMetricsTests: XCTestCase {
    func testMessageColumnWidthCentersWideChatIntoReadableMaximum() {
        XCTAssertEqual(
            ChatConversationLayoutMetrics.messageColumnWidth(for: 1_800),
            ChatConversationLayoutMetrics.messageColumnMaxWidth
        )
    }

    func testMessageColumnWidthKeepsCompactWindowsInsideInsets() {
        XCTAssertEqual(
            ChatConversationLayoutMetrics.messageColumnWidth(for: 680),
            680 - ChatConversationLayoutMetrics.compactHorizontalInset * 2
        )
        XCTAssertEqual(
            ChatConversationLayoutMetrics.messageColumnWidth(for: 720),
            720 - ChatConversationLayoutMetrics.regularHorizontalInset * 2
        )
    }

    func testMessageColumnWidthRejectsInvalidInputs() {
        XCTAssertEqual(ChatConversationLayoutMetrics.messageColumnWidth(for: 0), 0)
        XCTAssertEqual(ChatConversationLayoutMetrics.messageColumnWidth(for: -1), 0)
        XCTAssertEqual(ChatConversationLayoutMetrics.messageColumnWidth(for: .nan), 0)
        XCTAssertEqual(ChatConversationLayoutMetrics.messageColumnWidth(for: .infinity), 0)
    }

    func testUserBubbleWidthStaysInsideReadingColumn() {
        XCTAssertEqual(
            ChatConversationLayoutMetrics.userBubbleMaxWidth(for: 1_120),
            1_120 * ChatConversationLayoutMetrics.userBubbleWidthRatio
        )
        XCTAssertEqual(
            ChatConversationLayoutMetrics.userBubbleMaxWidth(for: 300),
            ChatConversationLayoutMetrics.minimumBubbleWidth
        )
    }

    func testUserBubbleWidthUsesMinimumForInvalidInputs() {
        XCTAssertEqual(
            ChatConversationLayoutMetrics.userBubbleMaxWidth(for: 0),
            ChatConversationLayoutMetrics.minimumBubbleWidth
        )
        XCTAssertEqual(
            ChatConversationLayoutMetrics.userBubbleMaxWidth(for: -1),
            ChatConversationLayoutMetrics.minimumBubbleWidth
        )
        XCTAssertEqual(
            ChatConversationLayoutMetrics.userBubbleMaxWidth(for: .nan),
            ChatConversationLayoutMetrics.minimumBubbleWidth
        )
        XCTAssertEqual(
            ChatConversationLayoutMetrics.userBubbleMaxWidth(for: .infinity),
            ChatConversationLayoutMetrics.minimumBubbleWidth
        )
    }

    func testLayoutWidthBucketIsStableAfterColumnReachesMaximum() {
        XCTAssertEqual(
            ChatConversationLayoutMetrics.layoutWidthBucket(for: 1_200),
            ChatConversationLayoutMetrics.layoutWidthBucket(for: 1_800)
        )
        XCTAssertNotEqual(
            ChatConversationLayoutMetrics.layoutWidthBucket(for: 900),
            ChatConversationLayoutMetrics.layoutWidthBucket(for: 1_200)
        )
    }

    func testLayoutWidthBucketHandlesInvalidInputs() {
        XCTAssertEqual(ChatConversationLayoutMetrics.layoutWidthBucket(for: 0), 0)
        XCTAssertEqual(ChatConversationLayoutMetrics.layoutWidthBucket(for: -1), 0)
        XCTAssertEqual(ChatConversationLayoutMetrics.layoutWidthBucket(for: .nan), 0)
        XCTAssertEqual(ChatConversationLayoutMetrics.layoutWidthBucket(for: .infinity), 0)
    }

    func testVisibleContainerWidthExcludesVisibleOverlaySidebar() {
        XCTAssertEqual(
            ChatConversationLayoutMetrics.visibleContainerWidth(
                containerWidth: 1_600,
                sidebarWidth: 320,
                isSidebarHidden: false
            ),
            1_280
        )
        XCTAssertEqual(
            ChatConversationLayoutMetrics.visibleContainerWidth(
                containerWidth: 1_600,
                sidebarWidth: 320,
                isSidebarHidden: true
            ),
            1_600
        )
        XCTAssertEqual(
            ChatConversationLayoutMetrics.visibleContainerWidth(
                containerWidth: 1_600,
                sidebarWidth: -10,
                isSidebarHidden: false
            ),
            1_600
        )
    }

    func testSidebarCompensationOffsetCentersInVisibleOverlayArea() {
        XCTAssertEqual(
            ChatConversationLayoutMetrics.sidebarCompensationOffset(
                sidebarWidth: 320,
                isSidebarHidden: false
            ),
            160
        )
        XCTAssertEqual(
            ChatConversationLayoutMetrics.sidebarCompensationOffset(
                sidebarWidth: 320,
                isSidebarHidden: false
            ),
            160
        )
        XCTAssertEqual(
            ChatConversationLayoutMetrics.sidebarCompensationOffset(
                sidebarWidth: 320,
                isSidebarHidden: true
            ),
            0
        )
    }

    func testSidebarCompensationOffsetSupportsFullscreenVisualTuning() {
        XCTAssertEqual(
            ChatConversationLayoutMetrics.sidebarCompensationOffset(
                sidebarWidth: 320,
                isSidebarHidden: false,
                compensationRatio: ChatConversationLayoutMetrics.fullScreenSidebarCompensationRatio
            ),
            320 * ChatConversationLayoutMetrics.fullScreenSidebarCompensationRatio
        )
    }

    func testSidebarCompensationOffsetRejectsInvalidInputs() {
        XCTAssertEqual(
            ChatConversationLayoutMetrics.sidebarCompensationOffset(
                sidebarWidth: 0,
                isSidebarHidden: false
            ),
            0
        )
        XCTAssertEqual(
            ChatConversationLayoutMetrics.sidebarCompensationOffset(
                sidebarWidth: -1,
                isSidebarHidden: false
            ),
            0
        )
        XCTAssertEqual(
            ChatConversationLayoutMetrics.sidebarCompensationOffset(
                sidebarWidth: .nan,
                isSidebarHidden: false
            ),
            0
        )
        XCTAssertEqual(
            ChatConversationLayoutMetrics.sidebarCompensationOffset(
                sidebarWidth: 320,
                isSidebarHidden: false,
                compensationRatio: .nan
            ),
            0
        )
    }
}
