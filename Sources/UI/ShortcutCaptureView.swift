#if os(macOS)
import AppKit
import SwiftUI

struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var isFirstResponder: Bool
    let onCapture: (AppShortcutBinding) -> Void
    let onClear: () -> Void
    let onValidationError: (String) -> Void

    func makeNSView(context: Context) -> CaptureNSView {
        let view = CaptureNSView()
        view.onCapture = onCapture
        view.onClear = onClear
        view.onValidationError = onValidationError
        return view
    }

    func updateNSView(_ nsView: CaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onClear = onClear
        nsView.onValidationError = onValidationError
        guard isFirstResponder, nsView.window?.firstResponder !== nsView else { return }
        nsView.window?.makeFirstResponder(nsView)
    }

    final class CaptureNSView: NSView {
        var onCapture: ((AppShortcutBinding) -> Void)?
        var onClear: (() -> Void)?
        var onValidationError: ((String) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard event.type == .keyDown else { return false }
            return handleKeyEvent(event)
        }

        override func keyDown(with event: NSEvent) {
            _ = handleKeyEvent(event)
        }

        @discardableResult
        private func handleKeyEvent(_ event: NSEvent) -> Bool {
            let modifiers = AppShortcutModifiers(eventFlags: event.modifierFlags.intersection(.deviceIndependentFlagsMask))

            if modifiers.isEmpty && (event.keyCode == 51 || event.keyCode == 117) {
                onClear?()
                return true
            }

            guard modifiers.includesCommandKey else {
                NSSound.beep()
                onValidationError?("Please include Command (⌘).")
                return true
            }

            guard let key = AppShortcutKey(event: event) else {
                NSSound.beep()
                onValidationError?("This key is not supported.")
                return true
            }

            onCapture?(AppShortcutBinding(key: key, modifiers: modifiers))
            return true
        }
    }
}
#endif
