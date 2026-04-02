import SwiftUI

extension View {
    /// Tracks whether a scroll view remains pinned to its bottom edge.
    /// The `bottomTolerance` parameter is applied directly so callers can keep
    /// the pin window conservative for chat timelines.
    @ViewBuilder
    func onScrollPinChange(
        isPinned: Binding<Bool>,
        bottomTolerance: CGFloat = 40,
        onChange: ((Bool, Bool) -> Void)? = nil
    ) -> some View {
        if #available(macOS 15.0, *) {
            self.onScrollGeometryChange(for: Bool.self) { geo in
                let distFromBottom = geo.contentSize.height - geo.contentOffset.y - geo.containerSize.height
                return distFromBottom <= max(0, bottomTolerance)
            } action: { _, pinned in
                let previousPinned = isPinned.wrappedValue
                if pinned != previousPinned {
                    isPinned.wrappedValue = pinned
                    onChange?(previousPinned, pinned)
                }
            }
        } else {
            self
        }
    }

    /// Reports whether the scroll view is currently being manipulated by the
    /// user, excluding programmatic scroll animations.
    @ViewBuilder
    func onUserScrollIntentChange(_ action: @escaping (Bool) -> Void) -> some View {
        if #available(macOS 15.0, *) {
            self.onScrollPhaseChange { _, newPhase in
                switch newPhase {
                case .tracking, .interacting, .decelerating:
                    action(true)
                case .animating, .idle:
                    action(false)
                @unknown default:
                    action(false)
                }
            }
        } else {
            self
        }
    }
}
