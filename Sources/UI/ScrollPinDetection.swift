import SwiftUI

extension View {
    @ViewBuilder
    func onScrollPinChange(isPinned: Binding<Bool>) -> some View {
        if #available(macOS 15.0, *) {
            self.onScrollGeometryChange(for: Bool.self) { geo in
                let distFromBottom = geo.contentSize.height - geo.contentOffset.y - geo.containerSize.height
                return distFromBottom <= 80
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
