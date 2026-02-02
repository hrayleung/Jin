import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DroppableTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isDropTargeted: Bool

    let font: NSFont
    let onDropFileURLs: ([URL]) -> Bool
    let onDropImages: ([NSImage]) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isDropTargeted: $isDropTargeted,
            onDropFileURLs: onDropFileURLs,
            onDropImages: onDropImages
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = DroppableNSTextView()
        textView.delegate = context.coordinator
        textView.font = font
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 2, height: 6)
        textView.string = text

        textView.onDragTargetedChanged = { isTargeted in
            context.coordinator.setDropTargeted(isTargeted)
        }
        textView.onPerformDrop = { draggingInfo in
            context.coordinator.performDrop(draggingInfo)
        }

        let readableTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        textView.registerForDraggedTypes(
            readableTypes + [
                .fileURL,
                .URL,
                .string,
                .tiff,
                .png,
                NSPasteboard.PasteboardType(UTType.jpeg.identifier)
            ]
        )

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

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        if textView.font != font {
            textView.font = font
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let textBinding: Binding<String>
        private let isDropTargetedBinding: Binding<Bool>
        private let onDropFileURLs: ([URL]) -> Bool
        private let onDropImages: ([NSImage]) -> Bool

        init(
            text: Binding<String>,
            isDropTargeted: Binding<Bool>,
            onDropFileURLs: @escaping ([URL]) -> Bool,
            onDropImages: @escaping ([NSImage]) -> Bool
        ) {
            textBinding = text
            isDropTargetedBinding = isDropTargeted
            self.onDropFileURLs = onDropFileURLs
            self.onDropImages = onDropImages
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            textBinding.wrappedValue = textView.string
        }

        func setDropTargeted(_ isTargeted: Bool) {
            if isDropTargetedBinding.wrappedValue != isTargeted {
                isDropTargetedBinding.wrappedValue = isTargeted
            }
        }

        func performDrop(_ draggingInfo: NSDraggingInfo) -> Bool {
            let pasteboard = draggingInfo.draggingPasteboard

            if handleFilePromises(in: pasteboard) {
                return true
            }

            let fileURLs = readFileURLs(from: pasteboard)
            if !fileURLs.isEmpty {
                return onDropFileURLs(fileURLs)
            }

            let images = readImages(from: pasteboard)
            if !images.isEmpty {
                return onDropImages(images)
            }

            let strings = readStrings(from: pasteboard)
            if !strings.isEmpty {
                let parsed = strings
                    .map(ChatView.parseDroppedString)
                    .reduce(into: (fileURLs: [URL](), textChunks: [String]())) { accum, item in
                        accum.fileURLs.append(contentsOf: item.fileURLs)
                        accum.textChunks.append(contentsOf: item.textChunks)
                    }

                if !parsed.fileURLs.isEmpty {
                    return onDropFileURLs(parsed.fileURLs)
                }
            }

            return false
        }

        private func handleFilePromises(in pasteboard: NSPasteboard) -> Bool {
            guard let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
                  !receivers.isEmpty else {
                return false
            }

            let destinationDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("JinFilePromises", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

            let queue = OperationQueue()
            queue.qualityOfService = .userInitiated
            queue.maxConcurrentOperationCount = 1

            let lock = NSLock()
            var promisedFileURLs: [URL] = []
            var completedCount = 0

            let handler = onDropFileURLs

            for receiver in receivers {
                var didComplete = false
                receiver.receivePromisedFiles(atDestination: destinationDir, options: [:], operationQueue: queue) { url, error in
                    lock.lock()
                    defer { lock.unlock() }

                    guard !didComplete else { return }
                    didComplete = true
                    completedCount += 1

                    if error == nil {
                        promisedFileURLs.append(url)
                    }

                    if completedCount == receivers.count, !promisedFileURLs.isEmpty {
                        DispatchQueue.main.async { [promisedFileURLs] in
                            _ = handler(promisedFileURLs)
                        }
                    }
                }
            }

            return true
        }

        private func readFileURLs(from pasteboard: NSPasteboard) -> [URL] {
            let objects = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [NSURL] ?? []
            return objects.map { $0 as URL }
        }

        private func readImages(from pasteboard: NSPasteboard) -> [NSImage] {
            let objects = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] ?? []
            return objects
        }

        private func readStrings(from pasteboard: NSPasteboard) -> [String] {
            var strings: [String] = []

            if let items = pasteboard.pasteboardItems {
                for item in items {
                    if let value = item.string(forType: .string) {
                        strings.append(value)
                    } else if let value = item.string(forType: .fileURL) {
                        strings.append(value)
                    }
                }
            }

            if let value = pasteboard.string(forType: .string) {
                strings.append(value)
            }

            return strings
        }
    }
}

private final class DroppableNSTextView: NSTextView {
    var onDragTargetedChanged: ((Bool) -> Void)?
    var onPerformDrop: ((NSDraggingInfo) -> Bool)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragTargetedChanged?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragTargetedChanged?(false)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onDragTargetedChanged?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDragTargetedChanged?(false)

        if let handled = onPerformDrop?(sender), handled {
            return true
        }

        return super.performDragOperation(sender)
    }
}
