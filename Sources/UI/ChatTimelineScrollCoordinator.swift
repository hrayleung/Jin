import CoreGraphics
import Foundation

enum ChatTimelineScrollCoordinator {
    struct PinnedBottomRefreshPlan: Equatable {
        let generation: Int
        let delays: [TimeInterval]
    }

    struct ContentHeightChangeAction: Equatable {
        let measuredHeight: CGFloat
        let shouldScheduleRefresh: Bool
    }

    static func refreshPlan(
        currentGeneration: Int,
        shouldMaintainPinnedBottomAnchor: Bool,
        delays: [TimeInterval]
    ) -> PinnedBottomRefreshPlan? {
        guard let generation = nextRefreshGeneration(
            current: currentGeneration,
            shouldMaintainPinnedBottomAnchor: shouldMaintainPinnedBottomAnchor
        ) else {
            return nil
        }
        return PinnedBottomRefreshPlan(generation: generation, delays: delays)
    }

    static func contentHeightChangeAction(
        newHeight: CGFloat,
        previousHeight: CGFloat,
        shouldMaintainPinnedBottomAnchor: Bool,
        threshold: CGFloat = 0.5
    ) -> ContentHeightChangeAction? {
        guard let measuredHeight = measuredContentHeight(
            afterChangeTo: newHeight,
            previousHeight: previousHeight,
            threshold: threshold
        ) else {
            return nil
        }
        return ContentHeightChangeAction(
            measuredHeight: measuredHeight,
            shouldScheduleRefresh: shouldMaintainPinnedBottomAnchor
        )
    }

    static func nextRefreshGeneration(
        current: Int,
        shouldMaintainPinnedBottomAnchor: Bool
    ) -> Int? {
        guard shouldMaintainPinnedBottomAnchor else { return nil }
        return current &+ 1
    }

    static func shouldPerformRefresh(
        expectedGeneration: Int,
        currentGeneration: Int,
        shouldMaintainPinnedBottomAnchor: Bool
    ) -> Bool {
        guard shouldMaintainPinnedBottomAnchor else { return false }
        return expectedGeneration == currentGeneration
    }

    static func invalidatedRefreshGeneration(current: Int) -> Int {
        current &+ 1
    }

    static func pinnedBottomTolerance(
        composerHeight: CGFloat,
        minimum: CGFloat = 36,
        maximum: CGFloat = 64
    ) -> CGFloat {
        min(maximum, max(minimum, composerHeight * 0.25))
    }

    static func shouldScrollToBottom(
        lastMeasuredContentHeight: CGFloat,
        viewportHeight: CGFloat,
        allowWhenContentFits: Bool = false
    ) -> Bool {
        let contentOverflowsViewport = lastMeasuredContentHeight > viewportHeight + 0.5
        return allowWhenContentFits || contentOverflowsViewport
    }

    static func measuredContentHeight(
        afterChangeTo newHeight: CGFloat,
        previousHeight: CGFloat,
        threshold: CGFloat = 0.5
    ) -> CGFloat? {
        guard abs(previousHeight - newHeight) > threshold else { return nil }
        return newHeight
    }
}
