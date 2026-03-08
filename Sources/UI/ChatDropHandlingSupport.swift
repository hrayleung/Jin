import Foundation
import AppKit
import UniformTypeIdentifiers

enum ChatDropHandlingSupport {

    struct DropResult {
        var fileURLs: [URL] = []
        var textChunks: [String] = []
        var errors: [String] = []
    }

    static func persistDroppedFileRepresentation(_ temporaryURL: URL) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JinDroppedFiles", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let filename = temporaryURL.lastPathComponent.isEmpty ? "Attachment" : temporaryURL.lastPathComponent
        let stableURL = dir.appendingPathComponent("\(UUID().uuidString)-\(filename)")
        try FileManager.default.copyItem(at: temporaryURL, to: stableURL)
        return stableURL
    }

    static func processDropProviders(
        _ providers: [NSItemProvider],
        completion: @escaping @Sendable (DropResult) -> Void
    ) -> Bool {
        guard !providers.isEmpty else { return false }

        var didScheduleWork = false
        let group = DispatchGroup()
        let lock = NSLock()

        var droppedFileURLs: [URL] = []
        var droppedTextChunks: [String] = []
        var errors: [String] = []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                didScheduleWork = true
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    if let url = AttachmentImportPipeline.urlFromItemProviderItem(item) {
                        lock.lock()
                        if url.isFileURL {
                            droppedFileURLs.append(url)
                        } else {
                            droppedTextChunks.append(url.absoluteString)
                        }
                        lock.unlock()
                        group.leave()
                        return
                    }

                    if let representationTypeID = AttachmentImportPipeline.preferredFileRepresentationTypeIdentifier(from: provider.registeredTypeIdentifiers) {
                        provider.loadFileRepresentation(forTypeIdentifier: representationTypeID) { url, fallbackError in
                            defer { group.leave() }

                            guard let url else {
                                if let fallbackError {
                                    lock.lock()
                                    errors.append(fallbackError.localizedDescription)
                                    lock.unlock()
                                } else if let error {
                                    lock.lock()
                                    errors.append(error.localizedDescription)
                                    lock.unlock()
                                }
                                return
                            }

                            do {
                                let stableURL = try persistDroppedFileRepresentation(url)
                                lock.lock()
                                droppedFileURLs.append(stableURL)
                                lock.unlock()
                            } catch {
                                lock.lock()
                                errors.append(error.localizedDescription)
                                lock.unlock()
                            }
                        }
                        return
                    }

                    if let error {
                        lock.lock()
                        errors.append(error.localizedDescription)
                        lock.unlock()
                    }

                    group.leave()
                }
                continue
            }

            if provider.canLoadObject(ofClass: NSImage.self) {
                didScheduleWork = true
                group.enter()
                _ = provider.loadObject(ofClass: NSImage.self) { object, error in
                    defer { group.leave() }

                    guard let image = object as? NSImage else {
                        if let error {
                            lock.lock()
                            errors.append(error.localizedDescription)
                            lock.unlock()
                        }
                        return
                    }

                    guard let tempURL = AttachmentImportPipeline.writeTemporaryPNG(from: image) else {
                        lock.lock()
                        errors.append("Failed to read dropped image.")
                        lock.unlock()
                        return
                    }

                    lock.lock()
                    droppedFileURLs.append(tempURL)
                    lock.unlock()
                }
                continue
            }

            if provider.canLoadObject(ofClass: URL.self) {
                didScheduleWork = true
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { object, error in
                    defer { group.leave() }

                    if let url = object {
                        lock.lock()
                        if url.isFileURL {
                            droppedFileURLs.append(url)
                        } else {
                            droppedTextChunks.append(url.absoluteString)
                        }
                        lock.unlock()
                        return
                    }

                    if let error {
                        lock.lock()
                        errors.append(error.localizedDescription)
                        lock.unlock()
                    }
                }
                continue
            }

            if provider.canLoadObject(ofClass: NSString.self) {
                didScheduleWork = true
                group.enter()
                _ = provider.loadObject(ofClass: NSString.self) { object, error in
                    defer { group.leave() }

                    if let text = object as? String {
                        let parsed = AttachmentImportPipeline.parseDroppedString(text)
                        lock.lock()
                        droppedFileURLs.append(contentsOf: parsed.fileURLs)
                        droppedTextChunks.append(contentsOf: parsed.textChunks)
                        lock.unlock()
                        return
                    }

                    if let error {
                        lock.lock()
                        errors.append(error.localizedDescription)
                        lock.unlock()
                    }
                }
                continue
            }

            let representationTypeID = AttachmentImportPipeline.preferredFileRepresentationTypeIdentifier(from: provider.registeredTypeIdentifiers)
            if let representationTypeID {
                didScheduleWork = true
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: representationTypeID) { url, error in
                    defer { group.leave() }

                    guard let url else {
                        if let error {
                            lock.lock()
                            errors.append(error.localizedDescription)
                            lock.unlock()
                        }
                        return
                    }

                    do {
                        let stableURL = try persistDroppedFileRepresentation(url)
                        lock.lock()
                        droppedFileURLs.append(stableURL)
                        lock.unlock()
                    } catch {
                        lock.lock()
                        errors.append(error.localizedDescription)
                        lock.unlock()
                    }
                }
                continue
            }
        }

        guard didScheduleWork else { return false }

        let finalizeLock = NSLock()
        var didFinalize = false

        group.notify(queue: .main) {
            finalizeLock.lock()
            guard !didFinalize else {
                finalizeLock.unlock()
                return
            }
            didFinalize = true
            finalizeLock.unlock()

            lock.lock()
            let result = DropResult(
                fileURLs: Array(Set(droppedFileURLs)),
                textChunks: droppedTextChunks,
                errors: errors
            )
            lock.unlock()

            completion(result)
        }

        return true
    }

    static func importAttachments(
        from urls: [URL],
        currentAttachmentCount: Int,
        maxAttachments: Int
    ) async -> (attachments: [DraftAttachment], errors: [String]) {
        guard !urls.isEmpty else { return ([], []) }

        let remainingSlots = max(0, maxAttachments - currentAttachmentCount)
        guard remainingSlots > 0 else {
            return ([], ["You can attach up to \(maxAttachments) files per message."])
        }

        let urlsToImport = Array(urls.prefix(remainingSlots))

        let (newAttachments, errors) = await Task.detached(priority: .userInitiated) {
            await AttachmentImportPipeline.importInBackground(from: urlsToImport)
        }.value

        return (newAttachments, errors)
    }

    static func appendTextChunksToComposer(
        _ textChunks: [String],
        currentText: String
    ) -> String? {
        let insertion = textChunks
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !insertion.isEmpty else { return nil }

        if currentText.isEmpty {
            return insertion
        } else {
            let separator = currentText.hasSuffix("\n") ? "" : "\n"
            return currentText + separator + insertion
        }
    }
}
