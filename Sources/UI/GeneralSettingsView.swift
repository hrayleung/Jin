import SwiftUI
#if os(macOS)
import AppKit
#endif

struct HideWindowToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(WindowToolbarHider())
    }

    private struct WindowToolbarHider: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            let view = ToolbarObservingView()
            return view
        }
        func updateNSView(_ nsView: NSView, context: Context) {
            (nsView as? ToolbarObservingView)?.hideToolbar()
        }
    }

    private final class ToolbarObservingView: NSView {
        private var windowObservation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            hideToolbar()

            // Observe in case NavigationSplitView re-creates the toolbar
            windowObservation = observe(\.window?.toolbar, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.hideToolbar()
                }
            }
        }

        func hideToolbar() {
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = ""
            if let toolbar = window.toolbar {
                toolbar.isVisible = false
            }
        }
    }
}
