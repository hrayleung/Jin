import AppKit
import SwiftUI

struct DroppableTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isDropTargeted: Bool
    @Binding var isFocused: Bool

    let placeholder: String?
    let font: NSFont
    let useCommandEnterToSubmit: Bool
    let onDropFileURLs: ([URL]) -> Bool
    let onDropImages: ([NSImage]) -> Bool
    let onSubmit: () -> Void
    let onCancel: () -> Bool
    let onContentHeightChanged: ((CGFloat) -> Void)?
    /// Optional key event interceptor. Return `true` to consume the event (prevents default handling).
    let onInterceptKeyDown: ((UInt16) -> Bool)?

    init(
        text: Binding<String>,
        isDropTargeted: Binding<Bool>,
        isFocused: Binding<Bool>,
        placeholder: String? = nil,
        font: NSFont,
        useCommandEnterToSubmit: Bool = false,
        onDropFileURLs: @escaping ([URL]) -> Bool,
        onDropImages: @escaping ([NSImage]) -> Bool,
        onSubmit: @escaping () -> Void,
        onCancel: @escaping () -> Bool,
        onContentHeightChanged: ((CGFloat) -> Void)? = nil,
        onInterceptKeyDown: ((UInt16) -> Bool)? = nil
    ) {
        _text = text
        _isDropTargeted = isDropTargeted
        _isFocused = isFocused
        self.placeholder = placeholder
        self.font = font
        self.useCommandEnterToSubmit = useCommandEnterToSubmit
        self.onDropFileURLs = onDropFileURLs
        self.onDropImages = onDropImages
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.onContentHeightChanged = onContentHeightChanged
        self.onInterceptKeyDown = onInterceptKeyDown
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isDropTargeted: $isDropTargeted,
            isFocused: $isFocused,
            onDropFileURLs: onDropFileURLs,
            onDropImages: onDropImages,
            onSubmit: onSubmit,
            onCancel: onCancel,
            onContentHeightChanged: onContentHeightChanged,
            onInterceptKeyDown: onInterceptKeyDown
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = DroppableNSTextView()
        textView.delegate = context.coordinator
        textView.placeholder = placeholder
        textView.font = font
        textView.useCommandEnterToSubmit = useCommandEnterToSubmit
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 2, height: 1)
        textView.textContainer?.lineFragmentPadding = 0
        textView.string = text

        textView.onDragTargetedChanged = { isTargeted in
            context.coordinator.setDropTargeted(isTargeted)
        }
        textView.onPerformDrop = { draggingInfo in
            context.coordinator.performDrop(draggingInfo)
        }
        textView.onFocusChanged = { isFocused in
            context.coordinator.setFocused(isFocused)
        }
        textView.onPerformPasteboard = { pasteboard in
            context.coordinator.performPaste(pasteboard)
        }
        textView.onSubmit = {
            context.coordinator.submit()
        }
        textView.onCancel = {
            context.coordinator.cancel()
        }
        textView.onInterceptKeyDown = { keyCode in
            context.coordinator.interceptKeyDown(keyCode)
        }

        textView.registerForDraggedTypes(PasteboardDropSupport.acceptedDraggedTypes)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        // Report initial content height after layout
        DispatchQueue.main.async {
            context.coordinator.reportContentHeight(textView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? DroppableNSTextView else { return }

        context.coordinator.updateInterceptor(onInterceptKeyDown)

        if textView.useCommandEnterToSubmit != useCommandEnterToSubmit {
            textView.useCommandEnterToSubmit = useCommandEnterToSubmit
        }

        if textView.syncExternalTextIfNeeded(text) {
            context.coordinator.reportContentHeight(textView)
        }

        if textView.font != font {
            textView.font = font
            textView.needsDisplay = true
        }

        if textView.placeholder != placeholder {
            textView.placeholder = placeholder
        }

        textView.setProgrammaticFocusRequested(isFocused)
    }
}
