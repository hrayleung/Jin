import AppKit
import SwiftUI

/// Settings pages supply their own heading. Keep the native titlebar's
/// controls and safe area, while letting the sidebar and page backgrounds
/// continue through it. Hiding the toolbar itself also hides window controls
/// on some macOS versions.
struct JinSettingsWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SettingsWindowView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? SettingsWindowView)?.apply()
    }

    private final class SettingsWindowView: NSView {
        private weak var observedWindow: NSWindow?
        private var titleVisibilityObservation: NSKeyValueObservation?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if observedWindow !== window {
                titleVisibilityObservation?.invalidate()
                titleVisibilityObservation = nil
                observedWindow = window
                // SwiftUI restores the Settings window title after destination
                // changes, even when the representable's size hasn't changed.
                titleVisibilityObservation = window?.observe(\.titleVisibility, options: [.new]) { [weak self] _, change in
                    guard change.newValue != .hidden else { return }
                    self?.apply()
                }
            }
            apply()
        }

        override func layout() {
            super.layout()
            apply()
        }

        func apply() {
            guard let window else { return }
            if window.titleVisibility != .hidden {
                window.titleVisibility = .hidden
            }
            if !window.titlebarAppearsTransparent {
                window.titlebarAppearsTransparent = true
            }
            if window.titlebarSeparatorStyle != .none {
                window.titlebarSeparatorStyle = .none
            }
        }
    }
}
