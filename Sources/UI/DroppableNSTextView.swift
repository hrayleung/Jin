import AppKit

final class DroppableNSTextView: NSTextView {
    var onDragTargetedChanged: ((Bool) -> Void)?
    var onPerformDrop: ((NSDraggingInfo) -> Bool)?
    var onFocusChanged: ((Bool) -> Void)?
    var onPerformPasteboard: ((NSPasteboard) -> Bool)?
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Bool)?
    var onInterceptKeyDown: ((UInt16) -> Bool)?
    var useCommandEnterToSubmit = false
    private var isProgrammaticFocusRequested = false
    var placeholder: String? {
        didSet { needsDisplay = true }
    }

    func setProgrammaticFocusRequested(_ requested: Bool) {
        isProgrammaticFocusRequested = requested
        if requested {
            applyProgrammaticFocusIfNeeded()
        }
    }

    @discardableResult
    func syncExternalTextIfNeeded(_ text: String) -> Bool {
        // IME composition uses marked text in the text storage. Replacing the
        // string while marked text is active discards the in-progress candidate.
        guard !hasMarkedText() else { return false }
        guard string != text else { return false }

        let preservedSelectedRanges = selectedRanges
        string = text
        selectedRanges = preservedSelectedRanges
        needsDisplay = true
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyProgrammaticFocusIfNeeded()
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome {
            onFocusChanged?(true)
            needsDisplay = true
        }
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            onFocusChanged?(false)
            needsDisplay = true
        }
        return didResign
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty, let placeholder, let font else { return }

        let insetX = textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0)
        let insetY = textContainerInset.height
        let placeholderRect = NSRect(
            x: insetX,
            y: insetY,
            width: max(0, bounds.width - insetX - textContainerInset.width),
            height: max(font.ascender - font.descender, font.pointSize)
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.placeholderTextColor
        ]

        (placeholder as NSString).draw(in: placeholderRect, withAttributes: attributes)
    }

    override func paste(_ sender: Any?) {
        if performCustomPaste(using: .general) {
            return
        }
        super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if performCustomPaste(using: .general) {
            return
        }
        super.pasteAsPlainText(sender)
    }

    override func pasteAsRichText(_ sender: Any?) {
        if performCustomPaste(using: .general) {
            return
        }
        super.pasteAsRichText(sender)
    }

    override func readSelection(from pboard: NSPasteboard) -> Bool {
        if performCustomPaste(using: pboard) {
            return true
        }
        return super.readSelection(from: pboard)
    }

    override func readSelection(from pboard: NSPasteboard, type typeName: NSPasteboard.PasteboardType) -> Bool {
        if performCustomPaste(using: pboard) {
            return true
        }
        return super.readSelection(from: pboard, type: typeName)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown,
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers == [.command], performCustomPaste(using: .general) {
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    private func performCustomPaste(using pasteboard: NSPasteboard) -> Bool {
        if onPerformPasteboard?(pasteboard) == true {
            return true
        }
        return false
    }

    private func submitAfterCurrentEvent() {
        // Let IME/text-system updates settle before sending so stale text does not reappear.
        DispatchQueue.main.async { [weak self] in
            self?.onSubmit?()
        }
    }

    override func keyDown(with event: NSEvent) {
        // Give the interceptor first chance to handle the event (e.g. slash command popup navigation).
        if onInterceptKeyDown?(event.keyCode) == true {
            return
        }

        // Escape
        if event.keyCode == 53, onCancel?() == true {
            return
        }

        // Return / Enter
        if event.keyCode == 36 || event.keyCode == 76 {
            if hasMarkedText() {
                super.keyDown(with: event)
                return
            }

            if useCommandEnterToSubmit {
                // In expanded mode: Cmd+Enter sends, plain Enter inserts newline.
                if event.modifierFlags.contains(.command) {
                    submitAfterCurrentEvent()
                    return
                }
                super.keyDown(with: event)
                return
            }

            // Default mode: Enter sends, Shift+Enter inserts newline.
            if event.modifierFlags.contains(.shift) {
                super.keyDown(with: event)
                return
            }

            submitAfterCurrentEvent()
            return
        }

        super.keyDown(with: event)
    }

    @discardableResult
    private func applyProgrammaticFocusIfNeeded() -> Bool {
        guard isProgrammaticFocusRequested, let window else { return false }
        guard window.firstResponder !== self else { return true }
        return window.makeFirstResponder(self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let prefersDefaultHandling = shouldUseDefaultTextDropHandling(for: sender)
        onDragTargetedChanged?(prefersDefaultHandling)
        return prefersDefaultHandling ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let prefersDefaultHandling = shouldUseDefaultTextDropHandling(for: sender)
        onDragTargetedChanged?(prefersDefaultHandling)
        return prefersDefaultHandling ? .copy : []
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        shouldUseDefaultTextDropHandling(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragTargetedChanged?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDragTargetedChanged?(false)
        super.draggingEnded(sender)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onDragTargetedChanged?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDragTargetedChanged?(false)

        if let handled = onPerformDrop?(sender), handled {
            return true
        }

        if shouldUseDefaultTextDropHandling(for: sender) {
            return super.performDragOperation(sender)
        }

        // Let parent SwiftUI `.onDrop` handlers process non-text payloads.
        return false
    }

    private func shouldUseDefaultTextDropHandling(for draggingInfo: NSDraggingInfo) -> Bool {
        PasteboardDropSupport.shouldUseDefaultTextDropHandling(
            for: draggingInfo.draggingPasteboard
        )
    }
}
