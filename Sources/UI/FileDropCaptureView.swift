import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
            let fileURLs = readFileURLs(from: pasteboard)
            if !fileURLs.isEmpty {
                return onDropFileURLs(fileURLs)
            }

            let images = readImages(from: pasteboard)
            if !images.isEmpty {
                return onDropImages(images)
            }

            let parsedFromText = parseTextValues(from: pasteboard)
            if !parsedFromText.fileURLs.isEmpty {
                return onDropFileURLs(parsedFromText.fileURLs)
            }
            if !parsedFromText.textChunks.isEmpty {
                return onDropTextChunks(parsedFromText.textChunks)
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

        private func readFileURLs(from pasteboard: NSPasteboard) -> [URL] {
            (pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [NSURL] ?? []).map { $0 as URL }
        }

        private func readImages(from pasteboard: NSPasteboard) -> [NSImage] {
            if let objects = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
               !objects.isEmpty {
                return objects
            }

            var images: [NSImage] = []
            if let image = NSImage(pasteboard: pasteboard) {
                images.append(image)
            }

            if let items = pasteboard.pasteboardItems {
                for item in items {
                    for type in item.types {
                        guard isImageType(type),
                              let data = item.data(forType: type),
                              let image = NSImage(data: data) else { continue }
                        images.append(image)
                        break
                    }
                }
            }

            return images
        }

        private func parseTextValues(from pasteboard: NSPasteboard) -> (fileURLs: [URL], textChunks: [String]) {
            var rawValues: [String] = []

            if let value = pasteboard.string(forType: .string) {
                rawValues.append(value)
            }
            if let value = pasteboard.string(forType: .URL) {
                rawValues.append(value)
            }
            if let value = pasteboard.string(forType: .fileURL) {
                rawValues.append(value)
            }

            if let items = pasteboard.pasteboardItems {
                for item in items {
                    for type in item.types {
                        guard let utType = UTType(type.rawValue),
                              utType.conforms(to: .text),
                              let text = item.string(forType: type) else { continue }
                        rawValues.append(text)
                    }
                }
            }

            var fileURLs: [URL] = []
            var textChunks: [String] = []
            var seenFiles = Set<String>()
            var seenText = Set<String>()

            func appendFileURL(_ url: URL) {
                guard url.isFileURL else { return }
                let key = url.standardizedFileURL.path
                guard seenFiles.insert(key).inserted else { return }
                fileURLs.append(url)
            }

            for value in rawValues {
                let parsed = AttachmentImportPipeline.parseDroppedString(value)
                for url in parsed.fileURLs {
                    appendFileURL(url)
                }
                for text in parsed.textChunks {
                    guard seenText.insert(text).inserted else { continue }
                    textChunks.append(text)
                }
            }

            let rawURLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL] ?? [])
                .map { $0 as URL }
            for url in rawURLs {
                appendFileURL(url)
            }

            return (fileURLs, textChunks)
        }

        private func isImageType(_ type: NSPasteboard.PasteboardType) -> Bool {
            if let utType = UTType(type.rawValue), utType.conforms(to: .image) {
                return true
            }

            return type == .png || type == .tiff
        }
    }
}

final class DropCaptureNSView: NSView {
    var onDragTargetedChanged: ((Bool) -> Void)?
    var onPerformDrop: ((NSDraggingInfo) -> Bool)?
    private static let acceptedDraggedTypes: [NSPasteboard.PasteboardType] =
        NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) } + [
            .fileURL,
            .URL,
            .string,
            .tiff,
            .png,
            NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        registerForDraggedTypes(Self.acceptedDraggedTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        autoresizingMask = [.width, .height]
        registerForDraggedTypes(Self.acceptedDraggedTypes)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // SwiftUI can rehost this NSView during layout/state transitions.
        // Re-register dragged types to keep drop capture stable afterwards.
        registerForDraggedTypes(Self.acceptedDraggedTypes)
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
        guard let types = pasteboard.types, !types.isEmpty else { return false }

        let accepted = Set(Self.acceptedDraggedTypes)
        for type in types where accepted.contains(type) {
            return true
        }

        for type in types {
            guard let utType = UTType(type.rawValue) else { continue }
            if utType.conforms(to: .fileURL)
                || utType.conforms(to: .url)
                || utType.conforms(to: .text)
                || utType.conforms(to: .image)
                || utType.conforms(to: .data)
                || utType.conforms(to: .item) {
                return true
            }
        }

        return false
    }
}
