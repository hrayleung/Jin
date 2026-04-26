import CoreGraphics

enum ChatConversationLayoutMetrics {
    static let messageColumnMaxWidth: CGFloat = 1_120
    static let composerMaxWidth: CGFloat = 1_120
    static let regularHorizontalInset: CGFloat = 24
    static let compactHorizontalInset: CGFloat = 18
    static let minimumBubbleWidth: CGFloat = 260
    static let userBubbleWidthRatio: CGFloat = 0.70

    private static let compactWidthThreshold: CGFloat = 720

    static func horizontalInset(for containerWidth: CGFloat) -> CGFloat {
        guard containerWidth.isFinite else { return regularHorizontalInset }
        return containerWidth < compactWidthThreshold ? compactHorizontalInset : regularHorizontalInset
    }

    static func messageColumnWidth(for containerWidth: CGFloat) -> CGFloat {
        guard containerWidth.isFinite, containerWidth > 0 else { return 0 }

        let availableWidth = max(0, containerWidth - horizontalInset(for: containerWidth) * 2)
        return min(messageColumnMaxWidth, availableWidth)
    }

    static func assistantBubbleMaxWidth(for columnWidth: CGFloat) -> CGFloat {
        guard columnWidth.isFinite, columnWidth > 0 else { return 0 }
        return columnWidth
    }

    static func userBubbleMaxWidth(for columnWidth: CGFloat) -> CGFloat {
        guard columnWidth.isFinite, columnWidth > 0 else { return minimumBubbleWidth }

        let preferredWidth = columnWidth * userBubbleWidthRatio
        return min(columnWidth, max(minimumBubbleWidth, preferredWidth))
    }

    static func layoutWidthBucket(for containerWidth: CGFloat) -> Int {
        let columnWidth = messageColumnWidth(for: containerWidth)
        guard columnWidth < messageColumnMaxWidth else {
            return Int(messageColumnMaxWidth.rounded())
        }

        return Int((columnWidth / 64).rounded(.toNearestOrAwayFromZero))
    }

    static func sidebarCompensationOffset(sidebarWidth: CGFloat, isSidebarHidden: Bool) -> CGFloat {
        guard !isSidebarHidden else { return 0 }
        guard sidebarWidth.isFinite, sidebarWidth > 0 else { return 0 }

        return -sidebarWidth / 2
    }

    static func sidebarCompensationOffset(
        containerWidth: CGFloat,
        contentWidth: CGFloat,
        sidebarWidth: CGFloat,
        isSidebarHidden: Bool
    ) -> CGFloat {
        let targetOffset = sidebarCompensationOffset(
            sidebarWidth: sidebarWidth,
            isSidebarHidden: isSidebarHidden
        )
        guard targetOffset < 0 else { return targetOffset }
        guard containerWidth.isFinite, contentWidth.isFinite else { return 0 }
        guard containerWidth > contentWidth else { return 0 }

        let centeredSideSpace = max(0, (containerWidth - contentWidth) / 2)
        let maximumLeadingShift = max(0, centeredSideSpace - horizontalInset(for: containerWidth))
        return max(targetOffset, -maximumLeadingShift)
    }
}
