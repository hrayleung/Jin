import AppKit
import UniformTypeIdentifiers

/// Static utilities for importing file attachments from various sources.
/// These methods are self-contained and do not depend on view state.
enum AttachmentImportPipeline {

    static func importInBackground(from urls: [URL]) async -> ([DraftAttachment], [String]) {
        var newAttachments: [DraftAttachment] = []
        var errors: [String] = []

        let storage: AttachmentStorageManager
        do {
            storage = try AttachmentStorageManager()
        } catch {
            return ([], ["Failed to initialize attachment storage: \(error.localizedDescription)"])
        }

        for sourceURL in urls {
            let result = await importSingle(from: sourceURL, storage: storage)
            switch result {
            case .success(let attachment):
                newAttachments.append(attachment)
            case .failure(let error):
                errors.append(error.localizedDescription)
            }
        }

        return (newAttachments, errors)
    }

    static func importRecordedAudioClip(_ clip: SpeechToTextManager.RecordedClip) async throws -> DraftAttachment {
        let storage = try AttachmentStorageManager()
        let stored = try await storage.saveAttachment(data: clip.data, filename: clip.filename, mimeType: clip.mimeType)
        return DraftAttachment(
            id: stored.id,
            filename: stored.filename,
            mimeType: stored.mimeType,
            fileURL: stored.fileURL,
            extractedText: nil
        )
    }

    static func writeTemporaryPNG(from image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            return nil
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JinDroppedImages", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let url = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    /// Persist managed images to disk so they have stable file URLs.
    static func persistImagesToDisk(_ parts: [ContentPart], dataProvider: HTTPDataProvider? = nil) async -> [ContentPart] {
        guard let storage = try? AttachmentStorageManager() else { return parts }

        var result: [ContentPart] = []
        result.reserveCapacity(parts.count)

        for part in parts {
            guard case .image(let image) = part else {
                result.append(part)
                continue
            }

            guard image.assetDisposition == .managed else {
                result.append(part)
                continue
            }

            if image.url?.isFileURL == true {
                result.append(.image(ImageContent(
                    mimeType: image.mimeType,
                    data: nil,
                    url: image.url,
                    assetDisposition: .managed
                )))
                continue
            }

            let storedURL: URL?
            if let data = image.data {
                let ext = AttachmentStorageManager.fileExtension(for: image.mimeType) ?? "png"
                let filename = "generated-image.\(ext)"
                storedURL = (try? await storage.saveAttachment(data: data, filename: filename, mimeType: image.mimeType))?.fileURL
            } else if let remoteURL = image.remoteURL {
                storedURL = await MessageMediaAssetPersistenceSupport.persistManagedRemoteImageToDisk(
                    from: remoteURL,
                    mimeType: image.mimeType,
                    dataProvider: dataProvider
                )
            } else {
                storedURL = nil
            }

            if let storedURL {
                result.append(.image(ImageContent(
                    mimeType: image.mimeType,
                    data: nil,
                    url: storedURL,
                    assetDisposition: .managed
                )))
            } else {
                result.append(part)
            }
        }

        return result
    }

    static func parseDroppedString(_ text: String) -> (fileURLs: [URL], textChunks: [String]) {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var fileURLs: [URL] = []
        var textChunks: [String] = []

        for line in lines {
            if line.hasPrefix("file://"), let url = URL(string: line), url.isFileURL {
                fileURLs.append(url)
                continue
            }

            let expanded = (line as NSString).expandingTildeInPath
            if expanded.hasPrefix("/") {
                let url = URL(fileURLWithPath: expanded)
                if isPotentialAttachmentFile(url) {
                    fileURLs.append(url)
                    continue
                }
            }

            textChunks.append(line)
        }

        return (fileURLs: fileURLs, textChunks: textChunks)
    }

    static func urlFromItemProviderItem(_ item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let url = item as? NSURL { return url as URL }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let string = item as? String { return URL(string: string) }
        if let string = item as? NSString { return URL(string: string as String) }
        return nil
    }

    /// Select a type identifier that is most likely to expose a dropped file
    /// through `NSItemProvider.loadFileRepresentation`.
    static func preferredFileRepresentationTypeIdentifier(from identifiers: [String]) -> String? {
        guard !identifiers.isEmpty else { return nil }

        if let promiseIdentifier = identifiers.first(where: { identifier in
            let lower = identifier.lowercased()
            return lower.contains("filepromise")
                || lower.contains("promised-file")
                || lower.contains("nsfilespromise")
        }) {
            return promiseIdentifier
        }

        for identifier in identifiers {
            guard let type = UTType(identifier) else { continue }
            if type.conforms(to: .text) || type.conforms(to: .url) { continue }
            if type.conforms(to: .data) || type.conforms(to: .content) {
                return identifier
            }
        }

        for identifier in identifiers {
            guard let type = UTType(identifier) else { continue }
            if type.conforms(to: .text) || type.conforms(to: .url) { continue }
            if type.conforms(to: .item) {
                return identifier
            }
        }

        return nil
    }

    nonisolated static func completionNotificationPreview(from parts: [ContentPart]) -> String? {
        let text = parts.compactMap { part -> String? in
            if case .text(let value) = part {
                return value
            }
            return nil
        }
        .joined(separator: " ")

        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(180))
    }

    static func isPotentialAttachmentFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return true }
        if ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "webp" { return true }
        if ["wav", "mp3", "m4a", "aac", "flac", "ogg", "oga", "webm"].contains(ext) { return true }
        if ["mp4", "m4v", "mov", "webm", "avi", "mkv", "mpeg", "mpg", "wmv", "flv", "3gp", "3gpp"].contains(ext) { return true }
        return documentMIMEType(for: url) != nil
    }

    static func extractedTextIfSupported(from sourceURL: URL, mimeType: String) -> String? {
        switch normalizedMIMEType(mimeType) {
        case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet":
            return SpreadsheetTextExtractor.extractText(
                fromXLSX: sourceURL,
                maxCharacters: AttachmentConstants.maxSpreadsheetExtractedCharacters
            )
        case "text/plain", "text/markdown", "text/x-markdown",
             "text/csv", "text/tab-separated-values",
             "application/json", "application/xml", "text/xml":
            return readTextFile(
                at: sourceURL,
                maxCharacters: AttachmentConstants.maxSpreadsheetExtractedCharacters
            )
        default:
            return nil
        }
    }

    // MARK: - Private Helpers

    private static func importSingle(from sourceURL: URL, storage: AttachmentStorageManager) async -> Result<DraftAttachment, AttachmentImportError> {
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard sourceURL.isFileURL else {
            return .failure(AttachmentImportError(message: "Unsupported item: \(sourceURL.lastPathComponent)"))
        }

        let filename = sourceURL.lastPathComponent.isEmpty ? "Attachment" : sourceURL.lastPathComponent
        let resourceValues = try? sourceURL.resourceValues(forKeys: [.isDirectoryKey])
        if resourceValues?.isDirectory == true {
            return .failure(AttachmentImportError(message: "\(filename): folders are not supported."))
        }

        guard let type = UTType(filenameExtension: sourceURL.pathExtension.lowercased()) else {
            if let convertedURL = convertImageFileToTemporaryPNG(at: sourceURL) {
                let base = (filename as NSString).deletingPathExtension
                let outputName = base.isEmpty ? "Image.png" : "\(base).png"
                return await saveConvertedPNG(convertedURL, storage: storage, filename: outputName)
            }
            return .failure(AttachmentImportError(message: "\(filename): unsupported file type."))
        }

        if type.conforms(to: .pdf) {
            return await saveAttachmentFile(from: sourceURL, filename: filename, mimeType: "application/pdf", storage: storage)
        }

        if type.conforms(to: .movie) {
            guard let mimeType = normalizedVideoMIMEType(for: type, sourceURL: sourceURL) else {
                return .failure(AttachmentImportError(message: "\(filename): unsupported video format. Use MP4/MOV/WebM/AVI/MKV/MPEG/WMV/FLV/3GP."))
            }
            return await saveAttachmentFile(from: sourceURL, filename: filename, mimeType: mimeType, storage: storage)
        }

        if type.conforms(to: .audio) {
            guard let mimeType = normalizedAudioMIMEType(for: type, sourceURL: sourceURL) else {
                return .failure(AttachmentImportError(message: "\(filename): unsupported audio format. Use WAV/MP3/M4A/AAC/FLAC/OGG/WebM."))
            }
            return await saveAttachmentFile(from: sourceURL, filename: filename, mimeType: mimeType, storage: storage)
        }

        if type.conforms(to: .image) {
            return await importImage(from: sourceURL, type: type, filename: filename, storage: storage)
        }

        if let mimeType = documentMIMEType(for: sourceURL) {
            return await saveAttachmentFile(from: sourceURL, filename: filename, mimeType: mimeType, storage: storage)
        }

        return .failure(AttachmentImportError(message: "\(filename): unsupported file type."))
    }

    private static func saveAttachmentFile(
        from sourceURL: URL,
        filename: String,
        mimeType: String,
        storage: AttachmentStorageManager
    ) async -> Result<DraftAttachment, AttachmentImportError> {
        do {
            let entity = try await storage.saveAttachment(from: sourceURL, filename: filename, mimeType: mimeType)
            return .success(
                DraftAttachment(
                    id: entity.id,
                    filename: entity.filename,
                    mimeType: entity.mimeType,
                    fileURL: entity.fileURL,
                    extractedText: extractedTextIfSupported(from: sourceURL, mimeType: mimeType)
                )
            )
        } catch {
            return .failure(AttachmentImportError(message: "\(filename): failed to import (\(error.localizedDescription))."))
        }
    }

    private static func importImage(
        from sourceURL: URL,
        type: UTType,
        filename: String,
        storage: AttachmentStorageManager
    ) async -> Result<DraftAttachment, AttachmentImportError> {
        let supported: Set<String> = ["image/png", "image/jpeg", "image/webp"]

        if let rawMimeType = type.preferredMIMEType {
            let mimeType = (rawMimeType == "image/jpg") ? "image/jpeg" : rawMimeType
            if supported.contains(mimeType) {
                return await saveAttachmentFile(from: sourceURL, filename: filename, mimeType: mimeType, storage: storage)
            }
        }

        guard let convertedURL = convertImageFileToTemporaryPNG(at: sourceURL) else {
            let rawMimeType = type.preferredMIMEType ?? "unknown"
            return .failure(AttachmentImportError(message: "\(filename): unsupported image format (\(rawMimeType)). Use PNG/JPEG/WebP."))
        }

        let base = (filename as NSString).deletingPathExtension
        let outputName = base.isEmpty ? "Image.png" : "\(base).png"
        return await saveConvertedPNG(convertedURL, storage: storage, filename: outputName)
    }

    private static func convertImageFileToTemporaryPNG(at url: URL) -> URL? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return writeTemporaryPNG(from: image)
    }

    private static func normalizedVideoMIMEType(for type: UTType, sourceURL: URL) -> String? {
        if let raw = type.preferredMIMEType?.lowercased(), raw.hasPrefix("video/") {
            return raw
        }

        switch sourceURL.pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        case "avi": return "video/x-msvideo"
        case "mkv": return "video/x-matroska"
        case "mpeg", "mpg": return "video/mpeg"
        case "wmv": return "video/x-ms-wmv"
        case "flv": return "video/x-flv"
        case "3gp", "3gpp": return "video/3gpp"
        default: return nil
        }
    }

    private static func normalizedAudioMIMEType(for type: UTType, sourceURL: URL) -> String? {
        if let raw = type.preferredMIMEType?.lowercased(), raw.hasPrefix("audio/") {
            switch raw {
            case "audio/x-wav": return "audio/wav"
            case "audio/mp4", "audio/x-m4a": return "audio/m4a"
            default: return raw
            }
        }

        switch sourceURL.pathExtension.lowercased() {
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/m4a"
        case "aac": return "audio/aac"
        case "flac": return "audio/flac"
        case "ogg", "oga": return "audio/ogg"
        case "webm": return "audio/webm"
        default: return nil
        }
    }

    private static func documentMIMEType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "doc":  return "application/msword"
        case "odt":  return "application/vnd.oasis.opendocument.text"
        case "rtf":  return "application/rtf"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "xls":  return "application/vnd.ms-excel"
        case "csv":  return "text/csv"
        case "tsv":  return "text/tab-separated-values"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "ppt":  return "application/vnd.ms-powerpoint"
        case "txt":  return "text/plain"
        case "md", "markdown": return "text/markdown"
        case "json": return "application/json"
        case "html", "htm": return "text/html"
        case "xml":  return "application/xml"
        default:     return nil
        }
    }

    private static func readTextFile(at sourceURL: URL, maxCharacters: Int) -> String? {
        guard let data = try? Data(contentsOf: sourceURL) else { return nil }

        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .ascii,
            .isoLatin1
        ]

        for encoding in encodings {
            guard var text = String(data: data, encoding: encoding) else { continue }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if text.count > maxCharacters {
                text = String(text.prefix(maxCharacters))
                text.append("\n\n[Truncated]")
            }
            return text
        }

        return nil
    }

    private static func saveConvertedPNG(
        _ pngURL: URL,
        storage: AttachmentStorageManager,
        filename: String
    ) async -> Result<DraftAttachment, AttachmentImportError> {
        do {
            let entity = try await storage.saveAttachment(from: pngURL, filename: filename, mimeType: "image/png")
            try? FileManager.default.removeItem(at: pngURL)
            return .success(
                DraftAttachment(
                    id: entity.id,
                    filename: entity.filename,
                    mimeType: entity.mimeType,
                    fileURL: entity.fileURL,
                    extractedText: nil
                )
            )
        } catch {
            return .failure(AttachmentImportError(message: "\(filename): failed to import (\(error.localizedDescription))."))
        }
    }
}
