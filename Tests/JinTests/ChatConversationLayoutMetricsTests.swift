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
                containerWidth: 1_600,
                contentWidth: ChatConversationLayoutMetrics.messageColumnMaxWidth,
                sidebarWidth: 320,
                isSidebarHidden: false
            ),
            160
        )
        XCTAssertEqual(
            ChatConversationLayoutMetrics.sidebarCompensationOffset(
                containerWidth: 1_120,
                contentWidth: 1_080,
                sidebarWidth: 320,
                isSidebarHidden: false
            ),
            160
        )
        XCTAssertEqual(
            ChatConversationLayoutMetrics.sidebarCompensationOffset(
                containerWidth: 1_600,
                contentWidth: ChatConversationLayoutMetrics.messageColumnMaxWidth,
                sidebarWidth: 320,
                isSidebarHidden: true
            ),
            0
        )
    }

    func testSidebarCompensationOffsetSupportsFullscreenVisualTuning() {
        XCTAssertEqual(
            ChatConversationLayoutMetrics.sidebarCompensationOffset(
                containerWidth: 1_600,
                contentWidth: ChatConversationLayoutMetrics.messageColumnMaxWidth,
                sidebarWidth: 320,
                isSidebarHidden: false,
                compensationRatio: ChatConversationLayoutMetrics.fullScreenSidebarCompensationRatio
            ),
            320 * ChatConversationLayoutMetrics.fullScreenSidebarCompensationRatio
        )
    }
}
