import SwiftUI
import AppKit

struct FileDropCaptureView: NSViewRepresentable {
    @Binding var isDropTargeted: Bool

    let onDropFileURLs: ([URL]) -> Bool
    let onDropImages: ([NSImage]) -> Bool
    let onDropTextChunks: ([String]) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isDropTargeted: $isDropTargeted,
            onDropFileURLs: onDropFileURLs,
            onDropImages: onDropImages,
            onDropTextChunks: onDropTextChunks
        )
    }

    func makeNSView(context: Context) -> DropCaptureNSView {
        let view = DropCaptureNSView()
        view.onDragTargetedChanged = { isTargeted in
            context.coordinator.setDropTargeted(isTargeted)
        }
        view.onPerformDrop = { draggingInfo in
            context.coordinator.performDrop(draggingInfo)
        }
        return view
    }

    func updateNSView(_ nsView: DropCaptureNSView, context: Context) {
        // Re-sync frame with host bounds: SwiftUI layout changes can leave
        // the inner NSView at a stale frame when autoresizingMask alone is
        // not sufficient (e.g. first layout after a hosting-view resize).
        if let host = nsView.superview, nsView.frame != host.bounds {
            nsView.frame = host.bounds
        }
        nsView.onDragTargetedChanged = { isTargeted in
            context.coordinator.setDropTargeted(isTargeted)
        }
        nsView.onPerformDrop = { draggingInfo in
            context.coordinator.performDrop(draggingInfo)
        }
    }

    final class Coordinator {
        private let isDropTargeted: Binding<Bool>
        private let onDropFileURLs: ([URL]) -> Bool
        private let onDropImages: ([NSImage]) -> Bool
        private let onDropTextChunks: ([String]) -> Bool

        init(
            isDropTargeted: Binding<Bool>,
            onDropFileURLs: @escaping ([URL]) -> Bool,
            onDropImages: @escaping ([NSImage]) -> Bool,
            onDropTextChunks: @escaping ([String]) -> Bool
        ) {
            self.isDropTargeted = isDropTargeted
            self.onDropFileURLs = onDropFileURLs
            self.onDropImages = onDropImages
            self.onDropTextChunks = onDropTextChunks
        }

        func setDropTargeted(_ isTargeted: Bool) {
            if isDropTargeted.wrappedValue != isTargeted {
                isDropTargeted.wrappedValue = isTargeted
            }
        }

        func performDrop(_ draggingInfo: NSDraggingInfo) -> Bool {
            handlePasteboard(draggingInfo.draggingPasteboard, allowFilePromises: true)
        }

        private func handlePasteboard(_ pasteboard: NSPasteboard, allowFilePromises: Bool) -> Bool {
            let fileURLs = PasteboardDropSupport.readFileURLs(from: pasteboard)
            if !fileURLs.isEmpty {
                return onDropFileURLs(fileURLs)
            }

            let parsedFromText = PasteboardDropSupport.parseTextValues(from: pasteboard)
            if !parsedFromText.fileURLs.isEmpty {
                return onDropFileURLs(parsedFromText.fileURLs)
            }
            if !parsedFromText.textChunks.isEmpty {
                return onDropTextChunks(parsedFromText.textChunks)
            }

            let images = PasteboardDropSupport.readImages(
                from: pasteboard,
                usesRawTypeFallback: false
            )
            if !images.isEmpty {
                return onDropImages(images)
            }

            if allowFilePromises, handleFilePromises(in: pasteboard) {
                return true
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

            let handler = onDropFileURLs
            let group = DispatchGroup()
            let lock = NSLock()
            var resolvedURLs: [URL] = []

            for receiver in receivers {
                group.enter()
                receiver.receivePromisedFiles(atDestination: destinationDir, options: [:], operationQueue: queue) { url, error in
                    defer { group.leave() }
                    guard error == nil else { return }
                    lock.lock()
                    resolvedURLs.append(url)
                    lock.unlock()
                }
            }

            group.notify(queue: .main) {
                guard !resolvedURLs.isEmpty else { return }
                _ = handler(resolvedURLs)
            }

            return true
        }

    }
}

final class DropCaptureNSView: NSView {
    var onDragTargetedChanged: ((Bool) -> Void)?
    var onPerformDrop: ((NSDraggingInfo) -> Bool)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        registerForDraggedTypes(PasteboardDropSupport.acceptedDraggedTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        autoresizingMask = [.width, .height]
        registerForDraggedTypes(PasteboardDropSupport.acceptedDraggedTypes)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // SwiftUI can rehost this NSView during layout/state transitions.
        // Re-register dragged types to keep drop capture stable afterwards.
        registerForDraggedTypes(PasteboardDropSupport.acceptedDraggedTypes)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAcceptDrag(sender.draggingPasteboard) else {
            onDragTargetedChanged?(false)
            return []
        }
        onDragTargetedChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAcceptDrag(sender.draggingPasteboard) else {
            onDragTargetedChanged?(false)
            return []
        }
        onDragTargetedChanged?(true)
        return .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAcceptDrag(sender.draggingPasteboard)
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
        return onPerformDrop?(sender) ?? false
    }

    private func canAcceptDrag(_ pasteboard: NSPasteboard) -> Bool {
        PasteboardDropSupport.canAcceptDrag(pasteboard)
    }
}
