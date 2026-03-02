import SwiftUI
#if os(macOS)
import AppKit
#endif

struct HideWindowToolbarCompatModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        // Apply the AppKit toolbar hider on all supported macOS versions.
        // NavigationSplitView can recreate an empty toolbar, which introduces
        // a top inset and desynchronizes sidebar/detail heights.
        content.modifier(HideWindowToolbarModifier())
    }
}

extension View {
    func hideWindowToolbarCompat() -> some View {
        modifier(HideWindowToolbarCompatModifier())
    }
}

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
        func updateNSView(_ nsView: NSView, context: Context) {}
    }

    private final class ToolbarObservingView: NSView {
        private weak var observedWindow: NSWindow?
        private var toolbarObservation: NSKeyValueObservation?
        private var fullscreenObservers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installObserversForCurrentWindowIfNeeded()
        }

        deinit {
            toolbarObservation?.invalidate()
            let center = NotificationCenter.default
            fullscreenObservers.forEach { center.removeObserver($0) }
        }

        private func installObserversForCurrentWindowIfNeeded() {
            guard let window else { return }
            guard observedWindow !== window else {
                hideToolbar()
                return
            }

            toolbarObservation?.invalidate()
            observedWindow = window
            hideToolbar(for: window)

            // NavigationSplitView can recreate a default toolbar during state
            // updates. Remove it immediately to avoid visible top-area jumps.
            toolbarObservation = window.observe(\.toolbar, options: [.new]) { [weak self] observedWindow, _ in
                guard let self else { return }
                self.hideToolbar(for: observedWindow)
                // AppKit may reapply toolbar/titlebar traits in the next cycle.
                DispatchQueue.main.async { [weak self, weak observedWindow] in
                    guard let self, let observedWindow else { return }
                    self.hideToolbar(for: observedWindow)
                }
            }

            observeFullscreen(for: window)
        }

        private func observeFullscreen(for window: NSWindow) {
            let center = NotificationCenter.default
            fullscreenObservers.forEach { center.removeObserver($0) }
            fullscreenObservers.removeAll()
            let reapplyChrome: (Notification) -> Void = { [weak self] notification in
                guard
                    let self,
                    let observedWindow = notification.object as? NSWindow
                else {
                    return
                }

                self.hideToolbar(for: observedWindow)
                // AppKit may re-apply fullscreen title bar traits after this notification.
                DispatchQueue.main.async { [weak self, weak observedWindow] in
                    guard let self, let observedWindow else { return }
                    self.hideToolbar(for: observedWindow)
                }
            }

            fullscreenObservers.append(
                center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main, using: reapplyChrome)
            )
            fullscreenObservers.append(
                center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main, using: reapplyChrome)
            )
        }

        func hideToolbar() {
            guard let window else { return }
            hideToolbar(for: window)
        }

        private func hideToolbar(for window: NSWindow) {
            applyWindowChrome(for: window)
            if window.titleVisibility != .hidden {
                window.titleVisibility = .hidden
            }
            if !window.title.isEmpty {
                window.title = ""
            }
            if !window.isMovableByWindowBackground {
                window.isMovableByWindowBackground = true
            }
            // Ensure AppKit doesn't keep an extra top content border when entering full screen.
            if window.contentBorderThickness(for: .minY) != 0 {
                window.setContentBorderThickness(0, for: .minY)
            }
            // Keep standard window controls visible.
            window.standardWindowButton(.closeButton)?.isHidden = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
            window.standardWindowButton(.zoomButton)?.isHidden = false
            // Remove toolbar so AppKit does not reserve an extra top strip.
            if window.toolbar != nil {
                window.toolbar = nil
            }
        }

        private func applyWindowChrome(for window: NSWindow) {
            let isFullScreen = window.styleMask.contains(.fullScreen)
            if isFullScreen {
                // Keep fullscreen top chrome opaque so sidebar separators do not bleed into the drop-down bar.
                if window.styleMask.contains(.fullSizeContentView) {
                    window.styleMask.remove(.fullSizeContentView)
                }
            } else {
                // Merge the title-bar region into app content so custom sidebar chrome can sit flush at the top.
                if !window.styleMask.contains(.fullSizeContentView) {
                    window.styleMask.insert(.fullSizeContentView)
                }
            }
            let shouldBeTransparent = !isFullScreen
            if window.titlebarAppearsTransparent != shouldBeTransparent {
                window.titlebarAppearsTransparent = shouldBeTransparent
            }
        }
    }
}
