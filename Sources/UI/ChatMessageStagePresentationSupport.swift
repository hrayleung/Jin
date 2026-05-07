import CoreGraphics
import Foundation

enum ChatMessageStagePresentationSupport {
    struct LoadEarlierPlan: Equatable {
        let restoreMessageID: UUID
        let nextRenderLimit: Int
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

    struct MultiModelLayout {
        static let horizontalPadding: CGFloat = 20
        static let columnSpacing: CGFloat = 12
        static let minimumColumnWidth: CGFloat = 320
        static let horizontalContentInset: CGFloat = 34
        static let minimumBubbleMaxWidth: CGFloat = 220

        let horizontalPadding: CGFloat
        let columnSpacing: CGFloat
        let columnWidth: CGFloat
        let bubbleMaxWidth: CGFloat

        init(containerWidth: CGFloat, threadCount: Int) {
            horizontalPadding = Self.horizontalPadding
            columnSpacing = Self.columnSpacing

            let availableWidth = Self.availableColumnSpace(
                containerWidth: containerWidth,
                threadCount: threadCount
            )
            columnWidth = max(Self.minimumColumnWidth, availableWidth / CGFloat(max(threadCount, 1)))
            bubbleMaxWidth = Self.bubbleMaxWidth(for: columnWidth)
        }

        init(columnWidth: CGFloat) {
            horizontalPadding = Self.horizontalPadding
            columnSpacing = Self.columnSpacing
            self.columnWidth = columnWidth
            bubbleMaxWidth = Self.bubbleMaxWidth(for: columnWidth)
        }

        private static func availableColumnSpace(containerWidth: CGFloat, threadCount: Int) -> CGFloat {
            let spacingCount = max(threadCount - 1, 0)
            return max(
                0,
                containerWidth
                    - (horizontalPadding * 2)
                    - (columnSpacing * CGFloat(spacingCount))
            )
        }

        private static func bubbleMaxWidth(for columnWidth: CGFloat) -> CGFloat {
            max(minimumBubbleMaxWidth, columnWidth - horizontalContentInset)
        }
    }

    static func bottomAnchorID(threadID: UUID? = nil) -> String {
        guard let threadID else { return "bottom" }
        return "bottom-\(threadID.uuidString)"
    }
}
