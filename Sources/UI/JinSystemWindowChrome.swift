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

    /// Let the toolbar own grouping, material, and the keyboard focus ring.
    /// Explicit `.glass` gives every icon a separate capsule on newer systems.
    func jinSystemToolbarButton() -> some View {
        buttonStyle(.automatic)
    }

    /// A model selector shares the system toolbar treatment with other items.
    @ViewBuilder
    func jinLabeledToolbarButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.automatic)
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
                if window.toolbarStyle != .unifiedCompact {
                    window.toolbarStyle = .unifiedCompact
            }
        }
    }
}
#endif
