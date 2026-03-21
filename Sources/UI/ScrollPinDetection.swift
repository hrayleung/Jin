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
}
