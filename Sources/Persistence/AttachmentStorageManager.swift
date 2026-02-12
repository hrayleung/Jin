import Foundation

/// Attachment storage manager for file-based attachments
actor AttachmentStorageManager {
    struct StoredAttachment: Sendable {
        let id: UUID
        let filename: String
        let mimeType: String
        let fileURL: URL
    }

    private let fileManager = FileManager.default
    private let baseURL: URL

    init() throws {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        baseURL = appSupport
            .appendingPathComponent("Jin", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)

        if !fileManager.fileExists(atPath: baseURL.path) {
            try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        }
    }

    /// Save attachment and return file URL
    func saveAttachment(data: Data, filename: String, mimeType: String) throws -> StoredAttachment {
        let id = UUID()
        let fileExtension = fileExtension(for: mimeType) ?? (filename as NSString).pathExtension
        let fileURL = baseURL.appendingPathComponent("\(id.uuidString).\(fileExtension)")

        try data.write(to: fileURL)

        return StoredAttachment(id: id, filename: filename, mimeType: mimeType, fileURL: fileURL)
    }

    /// Save attachment by copying a file URL (preferred for larger files)
    func saveAttachment(from sourceURL: URL, filename: String, mimeType: String) throws -> StoredAttachment {
        let id = UUID()
        let fileExtension = fileExtension(for: mimeType) ?? sourceURL.pathExtension
        let fileURL = baseURL.appendingPathComponent("\(id.uuidString).\(fileExtension)")

        try fileManager.copyItem(at: sourceURL, to: fileURL)

        return StoredAttachment(id: id, filename: filename, mimeType: mimeType, fileURL: fileURL)
    }

    /// Load attachment data
    func loadAttachment(_ attachment: StoredAttachment) throws -> Data {
        try Data(contentsOf: attachment.fileURL)
    }

    /// Delete attachment file
    func deleteAttachment(_ attachment: StoredAttachment) throws {
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
        case "video/mp4":
            return "mp4"
        case "video/webm":
            return "webm"
        case "video/quicktime":
            return "mov"
        default:
            return nil
        }
    }
}
