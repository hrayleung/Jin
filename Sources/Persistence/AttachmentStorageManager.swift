import Foundation

/// Attachment storage manager for file-based attachments
actor AttachmentStorageManager {
    private let fileManager = FileManager.default
    private let baseURL: URL

    init() throws {
        // Get Application Support directory
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        baseURL = appSupport
            .appendingPathComponent("LLMChat", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)

        // Create attachments directory if needed
        if !fileManager.fileExists(atPath: baseURL.path) {
            try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        }
    }

    /// Save attachment and return file URL
    func saveAttachment(data: Data, filename: String, mimeType: String) throws -> AttachmentEntity {
        let id = UUID()
        let fileExtension = fileExtension(for: mimeType) ?? (filename as NSString).pathExtension
        let fileURL = baseURL.appendingPathComponent("\(id.uuidString).\(fileExtension)")

        try data.write(to: fileURL)

        return AttachmentEntity(
            id: id,
            filename: filename,
            mimeType: mimeType,
            fileURL: fileURL
        )
    }

    /// Load attachment data
    func loadAttachment(_ attachment: AttachmentEntity) throws -> Data {
        try Data(contentsOf: attachment.fileURL)
    }

    /// Delete attachment file
    func deleteAttachment(_ attachment: AttachmentEntity) throws {
        if fileManager.fileExists(atPath: attachment.fileURL.path) {
            try fileManager.removeItem(at: attachment.fileURL)
        }
    }

    /// Delete all attachments (cleanup)
    func deleteAllAttachments() throws {
        if fileManager.fileExists(atPath: baseURL.path) {
            try fileManager.removeItem(at: baseURL)
            try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Private

    private func fileExtension(for mimeType: String) -> String? {
        switch mimeType {
        case "image/jpeg", "image/jpg":
            return "jpg"
        case "image/png":
            return "png"
        case "image/webp":
            return "webp"
        case "application/pdf":
            return "pdf"
        case "audio/mp3", "audio/mpeg":
            return "mp3"
        case "audio/wav":
            return "wav"
        default:
            return nil
        }
    }
}
