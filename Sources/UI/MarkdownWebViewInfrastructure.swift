import SwiftUI
import WebKit

/// Per-window drop forwarding reference. Each ChatView creates one and
/// injects it into the environment so that all MarkdownWKWebView instances
/// within that window forward drops to the correct attachment pipeline.
final class DropForwarderRef {
    var onDragTargetChanged: ((Bool) -> Void)?
    var onPerformDrop: ((NSDraggingInfo) -> Bool)?
}

private struct DropForwarderRefKey: EnvironmentKey {
    static let defaultValue: DropForwarderRef? = nil
}

extension EnvironmentValues {
    var dropForwarderRef: DropForwarderRef? {
        get { self[DropForwarderRefKey.self] }
        set { self[DropForwarderRefKey.self] = newValue }
    }
}

final class MarkdownWKWebView: WKWebView {
    var contentHeight: CGFloat = 0
    var selectionSnapshot: MessageSelectionSnapshot?
    var onQuoteSelection: ((MessageSelectionSnapshot) -> Void)?
    var onCreateHighlight: ((MessageSelectionSnapshot) -> Void)?
    var onRemoveHighlights: (([UUID]) -> Void)?

    // Drop forwarding — set per-instance via the SwiftUI environment so
    // each window's WKWebView instances forward drops to the correct
    // ChatView's attachment pipeline. Using a weak reference avoids
    // retaining stale state if the ChatView is torn down.
    weak var dropForwarderRef: DropForwarderRef?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard dropForwarderRef != nil else { return [] }
        dropForwarderRef?.onDragTargetChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropForwarderRef != nil ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropForwarderRef?.onDragTargetChanged?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropForwarderRef != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropForwarderRef?.onDragTargetChanged?(false)
        return dropForwarderRef?.onPerformDrop?(sender) ?? false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        dropForwarderRef?.onDragTargetChanged?(false)
        // Intentionally do NOT call super — WKWebView's default
        // implementation sends drag data to the WebContent process.
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        dropForwarderRef?.onDragTargetChanged?(false)
        // Intentionally do NOT call super — prevents WKWebView
        // from finalizing the drop in the WebContent process.
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: super.intrinsicContentSize.width, height: contentHeight)
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        nextResponder?.scrollWheel(with: event)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.items.removeAll { $0.identifier == .init("WKMenuItemIdentifierReload") }
        guard let selectionSnapshot, !selectionSnapshot.isEmpty else { return }

        if !menu.items.isEmpty, menu.items.last?.isSeparatorItem == false {
            menu.addItem(.separator())
        }

        let quoteItem = NSMenuItem(title: "Quote", action: #selector(quoteSelection), keyEquivalent: "")
        quoteItem.target = self
        quoteItem.image = NSImage(systemSymbolName: "quote.opening", accessibilityDescription: nil)
        menu.addItem(quoteItem)

        let highlightItem = NSMenuItem(title: "Highlight", action: #selector(highlightSelection), keyEquivalent: "")
        highlightItem.target = self
        highlightItem.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: nil)
        menu.addItem(highlightItem)

        if !selectionSnapshot.matchingHighlightIDs.isEmpty {
            let removeItem = NSMenuItem(title: "Remove Highlight", action: #selector(removeHighlightsForSelection), keyEquivalent: "")
            removeItem.target = self
            removeItem.image = NSImage(systemSymbolName: "minus.circle", accessibilityDescription: nil)
            menu.addItem(removeItem)
        }

        let copyItem = NSMenuItem(title: "Copy Selection", action: #selector(copySelectionText), keyEquivalent: "")
        copyItem.target = self
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        menu.addItem(copyItem)
    }

    override func keyDown(with event: NSEvent) {
        nextResponder?.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        nextResponder?.keyUp(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        nextResponder?.flagsChanged(with: event)
    }

    @objc private func quoteSelection() {
        guard let selectionSnapshot else { return }
        onQuoteSelection?(selectionSnapshot)
    }

    @objc private func highlightSelection() {
        guard let selectionSnapshot else { return }
        onCreateHighlight?(selectionSnapshot)
    }

    @objc private func removeHighlightsForSelection() {
        guard let selectionSnapshot else { return }
        onRemoveHighlights?(selectionSnapshot.matchingHighlightIDs)
    }

    @objc private func copySelectionText() {
        guard let text = selectionSnapshot?.selectedText,
              !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
