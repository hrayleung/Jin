import SwiftUI
#if os(macOS)
import AppKit
#endif

struct MainWindowChromeLayout: Equatable {
    var extendsContentIntoTitlebar = false
    var titlebarLeadingInset: CGFloat = 0

    static let zero = MainWindowChromeLayout()

    func leadingPadding(baseline: CGFloat, avoidsTitlebarControls: Bool) -> CGFloat {
        guard avoidsTitlebarControls else { return baseline }
        return max(baseline, titlebarLeadingInset)
    }
}

struct HideWindowToolbarCompatModifier: ViewModifier {
    @Binding var chromeLayout: MainWindowChromeLayout

    @ViewBuilder
    func body(content: Content) -> some View {
        // Apply the AppKit toolbar hider on all supported macOS versions.
        // NavigationSplitView can recreate an empty toolbar, which introduces
        // a top inset and desynchronizes sidebar/detail heights.
        content.modifier(WindowChromeObserverModifier(chromeLayout: $chromeLayout))
    }
}

extension View {
    func hideWindowToolbarCompat() -> some View {
        hideWindowToolbarCompat(chromeLayout: .constant(.zero))
    }

    func hideWindowToolbarCompat(chromeLayout: Binding<MainWindowChromeLayout>) -> some View {
        modifier(HideWindowToolbarCompatModifier(chromeLayout: chromeLayout))
    }

    @ViewBuilder
    func mainWindowToolbarChromeCompat() -> some View {
        mainWindowToolbarChromeCompat(chromeLayout: .constant(.zero))
    }

    @ViewBuilder
    func mainWindowToolbarChromeCompat(chromeLayout: Binding<MainWindowChromeLayout>) -> some View {
        if #available(macOS 15.0, *) {
            self
                .toolbar(removing: .title)
                .hideWindowToolbarCompat(chromeLayout: chromeLayout)
        } else {
            self.hideWindowToolbarCompat(chromeLayout: chromeLayout)
        }
    }
}

private struct WindowChromeObserverModifier: ViewModifier {
    @Binding var chromeLayout: MainWindowChromeLayout

    func body(content: Content) -> some View {
        content
            .background(WindowChromeObserverView(chromeLayout: $chromeLayout))
    }

    private struct WindowChromeObserverView: NSViewRepresentable {
        @Binding var chromeLayout: MainWindowChromeLayout

        func makeNSView(context: Context) -> NSView {
            let view = ToolbarObservingView()
            view.onChromeLayoutChange = { chromeLayout in
                updateChromeLayout(chromeLayout)
            }
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            guard let nsView = nsView as? ToolbarObservingView else { return }
            nsView.onChromeLayoutChange = { chromeLayout in
                updateChromeLayout(chromeLayout)
            }
        }

        private func updateChromeLayout(_ layout: MainWindowChromeLayout) {
            guard chromeLayout != layout else { return }
            DispatchQueue.main.async {
                guard chromeLayout != layout else { return }
                chromeLayout = layout
            }
        }
    }

    private final class ToolbarObservingView: NSView {
        private static let fallbackTitlebarLeadingInset: CGFloat = 78
        private static let titlebarLeadingPadding: CGFloat = 12

        private weak var observedWindow: NSWindow?
        private var toolbarObservation: NSKeyValueObservation?
        private var fullscreenObservers: [NSObjectProtocol] = []
        private var lastChromeLayout = MainWindowChromeLayout.zero
        var onChromeLayoutChange: (MainWindowChromeLayout) -> Void = { _ in }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installObserversForCurrentWindowIfNeeded()
        }

        override func layout() {
            super.layout()
            guard let window else { return }
            applyWindowChrome(for: window)
        }

        deinit {
            toolbarObservation?.invalidate()
            let center = NotificationCenter.default
            fullscreenObservers.forEach { center.removeObserver($0) }
        }

        private func installObserversForCurrentWindowIfNeeded() {
            guard let window else { return }
            guard observedWindow !== window else {
                applyConfiguredWindowChrome()
                return
            }

            toolbarObservation?.invalidate()
            observedWindow = window
            applyWindowChrome(for: window)

            // NavigationSplitView can recreate a default toolbar during state
            // updates. Remove it immediately to avoid visible top-area jumps.
            toolbarObservation = window.observe(\.toolbar, options: [.new]) { [weak self] observedWindow, _ in
                guard let self else { return }
                self.applyWindowChrome(for: observedWindow)
                // AppKit may reapply toolbar/titlebar traits in the next cycle.
                DispatchQueue.main.async { [weak self, weak observedWindow] in
                    guard let self, let observedWindow else { return }
                    self.applyWindowChrome(for: observedWindow)
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

                self.applyWindowChrome(for: observedWindow)
                // AppKit may re-apply fullscreen title bar traits after this notification.
                DispatchQueue.main.async { [weak self, weak observedWindow] in
                    guard let self, let observedWindow else { return }
                    self.applyWindowChrome(for: observedWindow)
                }
            }

            fullscreenObservers.append(
                center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main, using: reapplyChrome)
            )
            fullscreenObservers.append(
                center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main, using: reapplyChrome)
            )
        }

        private func applyConfiguredWindowChrome() {
            guard let window else { return }
            applyWindowChrome(for: window)
        }

        private func applyWindowChrome(for window: NSWindow) {
            applyWindowStyle(for: window)
            if window.titleVisibility != .hidden {
                window.titleVisibility = .hidden
            }
            if !window.isMovableByWindowBackground {
                window.isMovableByWindowBackground = true
            }
            // Clear any residual `.minY` content border AppKit may preserve during
            // fullscreen transitions. Standard windows do not support `.maxY`.
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
            publishChromeLayout(for: window)
        }

        private func applyWindowStyle(for window: NSWindow) {
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

        private func publishChromeLayout(for window: NSWindow) {
            let layout = chromeLayout(for: window)
            guard layout != lastChromeLayout else { return }
            lastChromeLayout = layout
            onChromeLayoutChange(layout)
        }

        private func chromeLayout(for window: NSWindow) -> MainWindowChromeLayout {
            guard !window.styleMask.contains(.fullScreen) else {
                return .zero
            }

            let titlebarButtons = [
                window.standardWindowButton(.closeButton),
                window.standardWindowButton(.miniaturizeButton),
                window.standardWindowButton(.zoomButton)
            ]
            .compactMap { $0 }

            guard !titlebarButtons.isEmpty else {
                return MainWindowChromeLayout(
                    extendsContentIntoTitlebar: true,
                    titlebarLeadingInset: Self.fallbackTitlebarLeadingInset
                )
            }

            let buttonUnion = titlebarButtons.reduce(into: NSRect.null) { partialResult, button in
                let buttonFrame = button.convert(button.bounds, to: nil)
                partialResult = partialResult.isNull ? buttonFrame : partialResult.union(buttonFrame)
            }

            guard !buttonUnion.isNull else {
                return MainWindowChromeLayout(
                    extendsContentIntoTitlebar: true,
                    titlebarLeadingInset: Self.fallbackTitlebarLeadingInset
                )
            }

            let leadingInset = max(
                Self.fallbackTitlebarLeadingInset,
                buttonUnion.maxX + Self.titlebarLeadingPadding
            )

            return MainWindowChromeLayout(
                extendsContentIntoTitlebar: true,
                titlebarLeadingInset: ceil(leadingInset)
            )
        }
    }
}
