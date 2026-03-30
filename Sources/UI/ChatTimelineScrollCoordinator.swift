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
        isPinnedToBottom: Bool,
        delays: [TimeInterval]
    ) -> PinnedBottomRefreshPlan? {
        guard let generation = nextRefreshGeneration(
            current: currentGeneration,
            isPinnedToBottom: isPinnedToBottom
        ) else {
            return nil
        }
        return PinnedBottomRefreshPlan(generation: generation, delays: delays)
    }

    static func contentHeightChangeAction(
        newHeight: CGFloat,
        previousHeight: CGFloat,
        isPinnedToBottom: Bool,
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
            shouldScheduleRefresh: isPinnedToBottom
        )
    }

    static func nextRefreshGeneration(current: Int, isPinnedToBottom: Bool) -> Int? {
        guard isPinnedToBottom else { return nil }
        return current &+ 1
    }

    static func shouldPerformRefresh(
        expectedGeneration: Int,
        currentGeneration: Int,
        isPinnedToBottom: Bool
    ) -> Bool {
        guard isPinnedToBottom else { return false }
        return expectedGeneration == currentGeneration
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
