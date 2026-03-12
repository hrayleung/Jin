import SwiftUI

extension View {
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
