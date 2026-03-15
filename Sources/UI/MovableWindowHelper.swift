#if os(macOS)
import AppKit
import SwiftUI

/// Sets `isMovableByWindowBackground = true` on the hosting NSWindow,
/// allowing the sheet to be dragged from any non-interactive area.
struct MovableWindowHelper: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = MovableWindowNSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class MovableWindowNSView: NSView {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isMovableByWindowBackground = true
    }
}
#endif
