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
        private var fullscreenObservers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            hideToolbar()

            // Observe in case NavigationSplitView re-creates the toolbar
            windowObservation = observe(\.window?.toolbar, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.hideToolbar()
                }
            }

            observeFullscreen()
        }

        deinit {
            let center = NotificationCenter.default
            fullscreenObservers.forEach { center.removeObserver($0) }
        }

        private func observeFullscreen() {
            let center = NotificationCenter.default
            fullscreenObservers.forEach { center.removeObserver($0) }
            fullscreenObservers.removeAll()
            let reapplyChrome: (Notification) -> Void = { [weak self] notification in
                guard
                    let self,
                    let observedWindow = notification.object as? NSWindow,
                    let currentWindow = self.window,
                    observedWindow === currentWindow
                else {
                    return
                }

                self.hideToolbar()
                // AppKit may re-apply fullscreen title bar traits after this notification.
                DispatchQueue.main.async { [weak self] in
                    self?.hideToolbar()
                }
            }

            fullscreenObservers.append(
                center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: nil, queue: .main, using: reapplyChrome)
            )
            fullscreenObservers.append(
                center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main, using: reapplyChrome)
            )
        }

        func hideToolbar() {
            guard let window else { return }
            applyWindowChrome(for: window)
            window.titleVisibility = .hidden
            window.title = ""
            window.isMovableByWindowBackground = true
            // Ensure AppKit doesn't keep an extra top content border when entering full screen.
            window.setContentBorderThickness(0, for: .minY)
            // Remove the auto toolbar entirely; hiding it can still reserve top layout space.
            if window.toolbar != nil {
                window.toolbar = nil
            }
        }

        private func applyWindowChrome(for window: NSWindow) {
            let isFullScreen = window.styleMask.contains(.fullScreen)
            if isFullScreen {
                // Keep fullscreen top chrome opaque so sidebar separators do not bleed into the drop-down bar.
                window.styleMask.remove(.fullSizeContentView)
            } else {
                // Merge the title-bar region into app content so custom sidebar chrome can sit flush at the top.
                window.styleMask.insert(.fullSizeContentView)
            }
            window.titlebarAppearsTransparent = !isFullScreen
        }
    }
}
