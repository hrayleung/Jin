import CoreGraphics
import XCTest
@testable import Jin

final class ChatMessageStagePresentationSupportTests: XCTestCase {
    func testTimelineWindowUsesSuffixAndTracksHiddenCount() {
        let messages = (0..<5).map { makeItem(index: $0) }
        let window = ChatMessageStagePresentationSupport.TimelineWindow(
            messages: messages,
            renderLimit: 2,
            pageSize: 2,
            eagerCodeHighlightTailCount: 3,
            nonLazyMessageStackThreshold: 4
        )

        XCTAssertEqual(window.visibleMessages.map(\.copyText), ["message-3", "message-4"])
        XCTAssertEqual(window.hiddenCount, 3)
        XCTAssertEqual(window.eagerCodeHighlightStartIndex, 0)
        XCTAssertFalse(window.usesLazyStack)
        XCTAssertEqual(window.nextRenderLimit, 4)
        XCTAssertTrue(window.canLoadEarlier)
        XCTAssertEqual(window.loadEarlierPlan?.restoreMessageID, messages[3].id)
        XCTAssertEqual(window.loadEarlierPlan?.nextRenderLimit, 4)
    }

    func testTimelineWindowClampsNextLimitAndLazyThreshold() {
        let messages = (0..<5).map { makeItem(index: $0) }
        let window = ChatMessageStagePresentationSupport.TimelineWindow(
            messages: messages,
            renderLimit: 10,
            pageSize: 4,
            eagerCodeHighlightTailCount: 2,
            nonLazyMessageStackThreshold: 4
        )

        XCTAssertEqual(window.visibleMessages.count, 5)
        XCTAssertEqual(window.hiddenCount, 0)
        XCTAssertEqual(window.eagerCodeHighlightStartIndex, 3)
        XCTAssertTrue(window.usesLazyStack)
        XCTAssertEqual(window.nextRenderLimit, 5)
        XCTAssertFalse(window.canLoadEarlier)
        XCTAssertEqual(window.loadEarlierPlan?.restoreMessageID, messages[0].id)
        XCTAssertEqual(window.loadEarlierPlan?.nextRenderLimit, 5)
    }

    func testTimelineWindowLoadEarlierPlanIsNilWithoutVisibleMessages() {
        let window = ChatMessageStagePresentationSupport.TimelineWindow(
            messages: [],
            renderLimit: 2,
            pageSize: 2,
            eagerCodeHighlightTailCount: 2,
            nonLazyMessageStackThreshold: 4
        )

        XCTAssertNil(window.loadEarlierPlan)
        XCTAssertFalse(window.canLoadEarlier)
    }

    func testSingleThreadLayoutUsesConversationMetrics() {
        let layout = ChatMessageStagePresentationSupport.SingleThreadLayout(
            visibleContainerWidth: 1_200
        )

        XCTAssertEqual(
            layout.columnWidth,
            ChatConversationLayoutMetrics.messageColumnWidth(for: 1_200)
        )
        XCTAssertEqual(
            layout.bubbleMaxWidth,
            ChatConversationLayoutMetrics.assistantBubbleMaxWidth(for: layout.columnWidth)
        )
    }

    func testMultiModelLayoutAccountsForPaddingSpacingAndMinimums() {
        let layout = ChatMessageStagePresentationSupport.MultiModelLayout(
            containerWidth: 1_000,
            threadCount: 3
        )

        XCTAssertEqual(layout.horizontalPadding, 20)
        XCTAssertEqual(layout.columnSpacing, 12)
        XCTAssertEqual(layout.columnWidth, 320)
        XCTAssertEqual(layout.bubbleMaxWidth, 286)

        let narrow = ChatMessageStagePresentationSupport.MultiModelLayout(
            containerWidth: 400,
            threadCount: 3
        )
        XCTAssertEqual(narrow.columnWidth, 320)
        XCTAssertEqual(narrow.bubbleMaxWidth, 286)

        let resolvedColumn = ChatMessageStagePresentationSupport.MultiModelLayout(
            columnWidth: 280
        )
        XCTAssertEqual(resolvedColumn.columnWidth, 280)
        XCTAssertEqual(resolvedColumn.bubbleMaxWidth, 246)
    }

    func testMultiModelLayoutTotalColumnsWidthMatchesPaddingSpacingAndColumnSum() {
        // Wide container, 2 threads: columns expand to fill, total should equal container.
        let two = ChatMessageStagePresentationSupport.MultiModelLayout(
            containerWidth: 1_000,
            threadCount: 2
        )
        // expected: 2*20 (padding) + 1*12 (spacing) + 2*((1000 - 40 - 12) / 2) = 40 + 12 + 948 = 1000
        XCTAssertEqual(two.totalColumnsWidth, 1_000)

        // Wide container, 3 threads: columns expand, total equals container.
        let three = ChatMessageStagePresentationSupport.MultiModelLayout(
            containerWidth: 1_500,
            threadCount: 3
        )
        // expected: 40 + 24 + 3 * ((1500 - 40 - 24) / 3) = 40 + 24 + 1436 = 1500
        XCTAssertEqual(three.totalColumnsWidth, 1_500)

        // Narrow container, columns clamp to minimum 320 — total exceeds visible width
        // so the multi-model stage scrolls horizontally.
        let narrow = ChatMessageStagePresentationSupport.MultiModelLayout(
            containerWidth: 400,
            threadCount: 3
        )
        // expected: 40 + 24 + 3*320 = 40 + 24 + 960 = 1024
        XCTAssertEqual(narrow.totalColumnsWidth, 1_024)

        // Single thread is still meaningful for fallback paths.
        let single = ChatMessageStagePresentationSupport.MultiModelLayout(
            containerWidth: 800,
            threadCount: 1
        )
        // expected: 40 + 0 + 760 = 800
        XCTAssertEqual(single.totalColumnsWidth, 800)

        // Resolved-column initializer reports zero total since thread count is unknown.
        let resolvedColumn = ChatMessageStagePresentationSupport.MultiModelLayout(
            columnWidth: 280
        )
        XCTAssertEqual(resolvedColumn.totalColumnsWidth, 0)
    }

    func testBottomAnchorIDsMatchSingleAndThreadedStages() {
        let threadID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

        XCTAssertEqual(ChatMessageStagePresentationSupport.bottomAnchorID(), "bottom")
        XCTAssertEqual(
            ChatMessageStagePresentationSupport.bottomAnchorID(threadID: threadID),
            "bottom-00000000-0000-0000-0000-000000000123"
        )
    }

    private func makeItem(index: Int) -> MessageRenderItem {
        MessageRenderItem(
            id: UUID(),
            contextThreadID: nil,
            role: MessageRole.assistant.rawValue,
            timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
            renderedBlocks: [.content(anchorID: "anchor-\(index)", part: .text("message-\(index)"))],
            toolCalls: [],
            searchActivities: [],
            codeExecutionActivities: [],
            assistantModelLabel: nil,
            assistantProviderIconID: nil,
            responseMetrics: nil,
            copyText: "message-\(index)",
            preferredRenderMode: .fullWeb,
            isMemoryIntensiveAssistantContent: false,
            collapsedPreview: nil,
            canEditUserMessage: false,
            canDeleteResponse: false,
            perMessageMCPServerNames: []
        )
    }
}
