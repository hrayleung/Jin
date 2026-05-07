import AppKit
import SwiftUI

extension DroppableTextEditor {
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let textBinding: Binding<String>
        private let isDropTargetedBinding: Binding<Bool>
        private let isFocusedBinding: Binding<Bool>
        private let onDropFileURLs: ([URL]) -> Bool
        private let onDropImages: ([NSImage]) -> Bool
        private let onSubmit: () -> Void
        private let onCancel: () -> Bool
        private let onContentHeightChanged: ((CGFloat) -> Void)?
        private var onInterceptKeyDown: ((UInt16) -> Bool)?

        init(
            text: Binding<String>,
            isDropTargeted: Binding<Bool>,
            isFocused: Binding<Bool>,
            onDropFileURLs: @escaping ([URL]) -> Bool,
            onDropImages: @escaping ([NSImage]) -> Bool,
            onSubmit: @escaping () -> Void,
            onCancel: @escaping () -> Bool,
            onContentHeightChanged: ((CGFloat) -> Void)? = nil,
            onInterceptKeyDown: ((UInt16) -> Bool)? = nil
        ) {
            textBinding = text
            isDropTargetedBinding = isDropTargeted
            isFocusedBinding = isFocused
            self.onDropFileURLs = onDropFileURLs
            self.onDropImages = onDropImages
            self.onSubmit = onSubmit
            self.onCancel = onCancel
            self.onContentHeightChanged = onContentHeightChanged
            self.onInterceptKeyDown = onInterceptKeyDown
        }

        func updateInterceptor(_ interceptor: ((UInt16) -> Bool)?) {
            onInterceptKeyDown = interceptor
        }

        func interceptKeyDown(_ keyCode: UInt16) -> Bool {
            onInterceptKeyDown?(keyCode) ?? false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            textBinding.wrappedValue = textView.string
            reportContentHeight(textView)
        }

        func reportContentHeight(_ textView: NSTextView) {
            guard let onContentHeightChanged else { return }
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let insets = textView.textContainerInset
            let height = usedRect.height + insets.height * 2
            onContentHeightChanged(height)
        }

        func setDropTargeted(_ isTargeted: Bool) {
            if isDropTargetedBinding.wrappedValue != isTargeted {
                isDropTargetedBinding.wrappedValue = isTargeted
            }
        }

        func setFocused(_ isFocused: Bool) {
            if isFocusedBinding.wrappedValue != isFocused {
                isFocusedBinding.wrappedValue = isFocused
            }
        }

        func performPaste(_ pasteboard: NSPasteboard) -> Bool {
            handlePasteboard(pasteboard, allowFilePromises: false)
        }

        func submit() {
            onSubmit()
        }

        func cancel() -> Bool {
            onCancel()
        }

        func performDrop(_ draggingInfo: NSDraggingInfo) -> Bool {
            handlePasteboard(draggingInfo.draggingPasteboard, allowFilePromises: true)
        }

        private func handlePasteboard(_ pasteboard: NSPasteboard, allowFilePromises: Bool) -> Bool {
            // Always check file URLs first. When a file is copied from Finder,
            // the pasteboard contains both the file URL and the app icon as a
            // TIFF image. Checking images first would mistake the icon for content.
            let fileURLs = PasteboardDropSupport.readFileURLs(from: pasteboard)
            if !fileURLs.isEmpty {
                return onDropFileURLs(fileURLs)
            }

            let inferredFileURLs = PasteboardDropSupport.readFileURLsFromURLAndTextRepresentations(from: pasteboard)
            if !inferredFileURLs.isEmpty {
                return onDropFileURLs(inferredFileURLs)
            }

            let images = PasteboardDropSupport.readImages(from: pasteboard)
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
