import SwiftUI

struct ContentViewSidebarOverlayPane<Sidebar: View>: View {
    let width: CGFloat
    let isVisible: Bool
    let onResizeChanged: (CGFloat) -> Void
    let onResizeEnded: () -> Void
    @ViewBuilder var sidebar: () -> Sidebar

    var body: some View {
        ZStack(alignment: .trailing) {
            sidebar()
                .frame(
                    minWidth: width,
                    idealWidth: width,
                    maxWidth: width,
                    maxHeight: .infinity
                )
                .clipped()
                .shadow(color: .black.opacity(isVisible ? 0.12 : 0), radius: 14, x: 4, y: 0)

            resizeHandle
                .offset(x: 4)
                .opacity(isVisible ? 1 : 0)
        }
        .frame(
            minWidth: width,
            idealWidth: width,
            maxWidth: width,
            maxHeight: .infinity
        )
        .offset(x: isVisible ? 0 : -width)
        .allowsHitTesting(isVisible)
        .zIndex(2)
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onResizeChanged(value.translation.width)
                    }
                    .onEnded { _ in
                        onResizeEnded()
                    }
            )
    }
}
