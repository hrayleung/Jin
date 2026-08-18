import CoreGraphics
import Foundation

enum ChatMessageStagePresentationSupport {
    struct LoadEarlierPlan: Equatable {
        let restoreMessageID: UUID
        let nextRenderLimit: Int
    }

    /// Render limit that keeps the current window head in place while `appended`
    /// new messages land at the tail.
    ///
    /// The window is `messages.suffix(renderLimit)`, so appending without
    /// growing the limit *slides* it: the oldest visible identity drops while a
    /// new one appears, which reconciles as a removal+insertion instead of a
    /// pure `appendTail`. Growing by exactly `appended` keeps every existing
    /// row identity and makes the send a clean tail insert.
    ///
    /// Growing all the way to `projectedTotal` (what the send path used to do)
    /// also avoids the slide, but by inserting the entire backlog at the head in
    /// one apply — past `ChatTimelineReconcilePlanner.maxBatchMutations` that
    /// degrades into a full `reloadData`, and it permanently unbounds the window.
    static func renderLimitAfterAppend(
        currentLimit: Int,
        projectedTotal: Int,
        appended: Int
    ) -> Int {
        guard appended > 0 else { return currentLimit }
        return max(currentLimit, min(projectedTotal, currentLimit + appended))
    }

    struct TimelineWindow {
        let visibleMessages: [MessageRenderItem]
        let hiddenCount: Int
        let eagerCodeHighlightStartIndex: Int
        let usesLazyStack: Bool
        let nextRenderLimit: Int
        let canLoadEarlier: Bool

        init(
            messages: [MessageRenderItem],
            renderLimit: Int,
            pageSize: Int,
            eagerCodeHighlightTailCount: Int,
            nonLazyMessageStackThreshold: Int
        ) {
            visibleMessages = Self.limitedVisibleMessages(from: messages, renderLimit: renderLimit)
            hiddenCount = messages.count - visibleMessages.count
            eagerCodeHighlightStartIndex = Self.eagerCodeHighlightStartIndex(
                visibleMessageCount: visibleMessages.count,
                tailCount: eagerCodeHighlightTailCount
            )
            usesLazyStack = visibleMessages.count > nonLazyMessageStackThreshold
            nextRenderLimit = Self.nextRenderLimit(
                messageCount: messages.count,
                renderLimit: renderLimit,
                pageSize: pageSize
            )
            canLoadEarlier = hiddenCount > 0
        }

        var loadEarlierPlan: LoadEarlierPlan? {
            guard let firstVisibleMessage = visibleMessages.first else { return nil }
            return LoadEarlierPlan(
                restoreMessageID: firstVisibleMessage.id,
                nextRenderLimit: nextRenderLimit
            )
        }

        private static func limitedVisibleMessages(
            from messages: [MessageRenderItem],
            renderLimit: Int
        ) -> [MessageRenderItem] {
            Array(messages.suffix(renderLimit))
        }

        private static func eagerCodeHighlightStartIndex(
            visibleMessageCount: Int,
            tailCount: Int
        ) -> Int {
            max(0, visibleMessageCount - tailCount)
        }

        private static func nextRenderLimit(
            messageCount: Int,
            renderLimit: Int,
            pageSize: Int
        ) -> Int {
            min(messageCount, renderLimit + pageSize)
        }
    }

    struct SingleThreadLayout {
        let columnWidth: CGFloat
        let bubbleMaxWidth: CGFloat

        init(visibleContainerWidth: CGFloat) {
            columnWidth = ChatConversationLayoutMetrics.messageColumnWidth(for: visibleContainerWidth)
            bubbleMaxWidth = ChatConversationLayoutMetrics.assistantBubbleMaxWidth(for: columnWidth)
        }
    }

    static func bottomAnchorID() -> String {
        "bottom"
    }
}
