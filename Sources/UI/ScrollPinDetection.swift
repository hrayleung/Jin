import SwiftUI

extension View {
    /// Tracks whether a scroll view remains pinned to its bottom edge.
    /// The `bottomTolerance` parameter defaults to `80` and is clamped to a
    /// minimum of `80` to avoid overly-sensitive pin detection.
    @ViewBuilder
    func onScrollPinChange(
        isPinned: Binding<Bool>,
        bottomTolerance: CGFloat = 80
    ) -> some View {
        if #available(macOS 15.0, *) {
            self.onScrollGeometryChange(for: Bool.self) { geo in
                let distFromBottom = geo.contentSize.height - geo.contentOffset.y - geo.containerSize.height
                return distFromBottom <= max(80, bottomTolerance)
            } action: { _, pinned in
                if pinned != isPinned.wrappedValue {
                    isPinned.wrappedValue = pinned
                }
            }
        } else {
            self
        }
    }

    /// Estimates the top-visible message by mapping the scroll offset fraction
    /// to the visible message array. On macOS < 15 this is a no-op; callers
    /// fall back to a coarser heuristic (first message of the render window).
    @ViewBuilder
    func onScrollPositionChange(
        visibleMessageIDs: [UUID],
        topVisibleMessageID: Binding<UUID?>
    ) -> some View {
        if #available(macOS 15.0, *) {
            self.onScrollGeometryChange(for: CGFloat.self) { geo in
                let scrollable = geo.contentSize.height - geo.containerSize.height
                guard scrollable > 1 else { return 0 }
                return geo.contentOffset.y / scrollable
            } action: { _, scrollFraction in
                guard !visibleMessageIDs.isEmpty else {
                    topVisibleMessageID.wrappedValue = nil
                    return
                }
                let fraction = min(1.0, max(0.0, scrollFraction))
                let index = Int(fraction * CGFloat(visibleMessageIDs.count - 1))
                let clamped = min(visibleMessageIDs.count - 1, max(0, index))
                let newID = visibleMessageIDs[clamped]
                if topVisibleMessageID.wrappedValue != newID {
                    topVisibleMessageID.wrappedValue = newID
                }
            }
        } else {
            self
        }
    }
}
