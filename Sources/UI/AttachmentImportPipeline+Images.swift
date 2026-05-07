import AppKit
import UniformTypeIdentifiers

extension AttachmentImportPipeline {
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

    static func importImage(
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

    static func convertImageFileToTemporaryPNG(at url: URL) -> URL? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return writeTemporaryPNG(from: image)
    }

    static func saveConvertedPNG(
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
