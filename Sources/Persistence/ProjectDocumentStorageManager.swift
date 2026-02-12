import Foundation

/// Manages file storage for project documents on disk.
actor ProjectDocumentStorageManager {
    struct StoredDocument: Sendable {
        let id: UUID
        let filename: String
        let mimeType: String
        let fileURL: URL
        let fileSizeBytes: Int64
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
            .appendingPathComponent("LLMChat", isDirectory: true)
            .appendingPathComponent("ProjectDocuments", isDirectory: true)

        if !fileManager.fileExists(atPath: baseURL.path) {
            try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        }
    }

    /// Save a document by copying from a source URL into the project's storage directory.
    func saveDocument(
        from sourceURL: URL,
        filename: String,
        mimeType: String,
        projectID: String
    ) throws -> StoredDocument {
        let projectDir = baseURL.appendingPathComponent(projectID, isDirectory: true)
        if !fileManager.fileExists(atPath: projectDir.path) {
            try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
        }

        let id = UUID()
        let fileExtension = sourceURL.pathExtension.isEmpty
            ? fileExtension(for: mimeType) ?? "bin"
            : sourceURL.pathExtension
        let destinationURL = projectDir.appendingPathComponent("\(id.uuidString).\(fileExtension)")

        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        let fileSize = (attributes[.size] as? Int64) ?? 0

        return StoredDocument(
            id: id,
            filename: filename,
            mimeType: mimeType,
            fileURL: destinationURL,
            fileSizeBytes: fileSize
        )
    }

    /// Save a document from raw data.
    func saveDocument(
        data: Data,
        filename: String,
        mimeType: String,
        projectID: String
    ) throws -> StoredDocument {
        let projectDir = baseURL.appendingPathComponent(projectID, isDirectory: true)
        if !fileManager.fileExists(atPath: projectDir.path) {
            try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
        }

        let id = UUID()
        let ext = fileExtension(for: mimeType) ?? (filename as NSString).pathExtension
        let destinationURL = projectDir.appendingPathComponent("\(id.uuidString).\(ext)")

        try data.write(to: destinationURL)

        return StoredDocument(
            id: id,
            filename: filename,
            mimeType: mimeType,
            fileURL: destinationURL,
            fileSizeBytes: Int64(data.count)
        )
    }

    /// Delete a single document file.
    func deleteDocument(at fileURL: URL) throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    /// Delete all documents for a project.
    func deleteProjectDocuments(projectID: String) throws {
        let projectDir = baseURL.appendingPathComponent(projectID, isDirectory: true)
        if fileManager.fileExists(atPath: projectDir.path) {
            try fileManager.removeItem(at: projectDir)
        }
    }

    // MARK: - Private

    private func fileExtension(for mimeType: String) -> String? {
        switch mimeType {
        case "application/pdf":
            return "pdf"
        case "text/plain":
            return "txt"
        case "text/markdown":
            return "md"
        case "application/json":
            return "json"
        case "text/csv":
            return "csv"
        case "text/html":
            return "html"
        case "text/xml", "application/xml":
            return "xml"
        default:
            return nil
        }
    }
}
