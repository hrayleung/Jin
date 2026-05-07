import Foundation
import UniformTypeIdentifiers

extension AttachmentImportPipeline {
    static func importSingle(from sourceURL: URL, storage: AttachmentStorageManager) async -> Result<DraftAttachment, AttachmentImportError> {
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

    static func saveAttachmentFile(
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
}
