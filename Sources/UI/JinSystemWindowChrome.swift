import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Opts the main window into the system unified toolbar and drops the
/// legacy title-bar separator. macOS 27.2 draws that separator as a hard
/// shadow when a split view asks for one, which reads as a flat pre-glass
/// bar. This does not touch `fullSizeContentView`, title-bar transparency,
/// or `window.toolbar` — those overrides fight the system sidebar.
struct JinSystemTitlebarMaterialModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.background {
                JinSystemTitlebarMaterialAnchor()
                    .allowsHitTesting(false)
            }
        } else {
            content
        }
    }
}

extension View {
    func jinSystemTitlebarMaterial() -> some View {
        modifier(JinSystemTitlebarMaterialModifier())
    }

    /// Toolbar icon. Liquid Glass capsule on macOS 26+. Older systems keep
    /// the default toolbar button, which is what these controls already used.
    @ViewBuilder
    func jinSystemToolbarButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            self
        }
    }

    /// Labeled toolbar control. macOS 14/15 keep the bordered style this
    /// button had; macOS 26+ uses the system glass capsule instead of a
    /// legacy bordered button sitting on the glass bar.
    @ViewBuilder
    func jinLabeledToolbarButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}

#if os(macOS)
@available(macOS 26.0, *)
private struct JinSystemTitlebarMaterialAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TitlebarMaterialView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class TitlebarMaterialView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        override func layout() {
            super.layout()
            apply()
        }

        private func apply() {
            guard let window else { return }
            if window.titlebarSeparatorStyle != .none {
                window.titlebarSeparatorStyle = .none
            }
            if window.toolbarStyle != .unified {
                window.toolbarStyle = .unified
            }
        }
    }
}
#endif
