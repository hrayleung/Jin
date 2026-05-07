import SwiftUI

private struct OverlayScrollerStyleViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> OverlayScrollerProbeView {
        OverlayScrollerProbeView()
    }

    func updateNSView(_ nsView: OverlayScrollerProbeView, context: Context) {
        nsView.refreshAttachment()
    }
}

extension View {
    /// Conditionally applies overlay-style scrollers to the nearest
    /// NSScrollView, gated by the ``AppPreferenceKeys/useOverlayScrollbars``
    /// preference. When disabled, the system-wide scroller style is respected.
    func overlayScrollerStyle() -> some View {
        modifier(OverlayScrollerStyleModifier())
    }
}

private struct OverlayScrollerStyleModifier: ViewModifier {
    @AppStorage(AppPreferenceKeys.useOverlayScrollbars) private var useOverlayScrollbars = true

    func body(content: Content) -> some View {
        if useOverlayScrollbars {
            content.background(OverlayScrollerStyleViewRepresentable())
        } else {
            content
        }
    }
}
