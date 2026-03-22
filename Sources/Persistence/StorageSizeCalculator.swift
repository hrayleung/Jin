import Foundation

enum StorageCategory: String, CaseIterable, Identifiable {
    case attachments
    case database
    case networkLogs
    case mcpData
    case speechModels

    var id: String { rawValue }

    var label: String {
        switch self {
        case .attachments: return "Attachments"
        case .database: return "Database"
        case .networkLogs: return "Network Logs"
        case .mcpData: return "MCP Server Data"
        case .speechModels: return "Speech Models"
        }
    }

    var systemImage: String {
        switch self {
        case .attachments: return "paperclip"
        case .database: return "cylinder"
        case .networkLogs: return "doc.text"
        case .mcpData: return "server.rack"
        case .speechModels: return "waveform"
        }
    }

    var description: String {
        switch self {
        case .attachments: return "Images, videos, audio, and files from conversations."
        case .database: return "Chat history, assistants, and provider configurations."
        case .networkLogs: return "HTTP/WebSocket debug trace files."
        case .mcpData: return "Node isolation directories for MCP servers."
        case .speechModels: return "On-device WhisperKit and TTSKit models."
        }
    }

    var isClearable: Bool {
        switch self {
        case .database: return false
        default: return true
        }
    }
}

struct StorageCategorySnapshot: Identifiable, Sendable {
    let category: StorageCategory
    let byteCount: Int64
    let fileCount: Int
    let url: URL?

    var id: String { category.id }
}

actor StorageSizeCalculator {
    private let fileManager = FileManager.default

    func calculateAll() -> [StorageCategorySnapshot] {
        StorageCategory.allCases.map { category in
            let url = directoryURL(for: category)
            let (bytes, count) = directorySize(at: url)
            return StorageCategorySnapshot(
                category: category,
                byteCount: bytes,
                fileCount: count,
                url: url
            )
        }
    }

    func clearCategory(_ category: StorageCategory) async throws {
        guard category.isClearable else { return }

        // Network logs must be cleared through the logger to reset in-flight state
        if category == .networkLogs {
            try await NetworkDebugLogger.shared.clearLogs()
            return
        }

        guard let url = directoryURL(for: category),
              fileManager.fileExists(atPath: url.path) else { return }

        // Hard guard: never allow deleting the raw Application Support root
        if let appSupport = try? AppDataLocations.applicationSupportDirectory(fileManager: fileManager),
           url == appSupport {
            return
        }

        try fileManager.removeItem(at: url)

        // Recreate the directory for categories that expect it to exist
        switch category {
        case .attachments, .mcpData:
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        case .speechModels, .database, .networkLogs:
            break
        }
    }

    // MARK: - Directory URLs

    private func directoryURL(for category: StorageCategory) -> URL? {
        switch category {
        case .attachments:
            return try? AppDataLocations.attachmentsDirectoryURL(fileManager: fileManager)
        case .database:
            return try? AppDataLocations.databaseDirectoryURL(fileManager: fileManager)
        case .networkLogs:
            return try? AppDataLocations.networkTraceDirectoryURL(fileManager: fileManager)
        case .mcpData:
            return try? AppDataLocations.mcpRuntimeDirectoryURL(fileManager: fileManager)
        case .speechModels:
            return speechModelsURL()
        }
    }

    private func speechModelsURL() -> URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
    }

    // MARK: - Size Calculation

    private func directorySize(at url: URL?) -> (bytes: Int64, fileCount: Int) {
        guard let url, fileManager.fileExists(atPath: url.path) else {
            return (0, 0)
        }

        // For the database category, only count SwiftData files in Application Support
        if url == (try? AppDataLocations.databaseDirectoryURL(fileManager: fileManager)) {
            return swiftDataFileSize(in: url)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0)
        }

        var totalBytes: Int64 = 0
        var count = 0

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            totalBytes += Int64(values.fileSize ?? 0)
            count += 1
        }

        return (totalBytes, count)
    }

    private func swiftDataFileSize(in appSupportDir: URL) -> (bytes: Int64, fileCount: Int) {
        let storeFiles = [
            "default.store",
            "default.store-shm",
            "default.store-wal"
        ]

        var totalBytes: Int64 = 0
        var count = 0

        for filename in storeFiles {
            let fileURL = appSupportDir.appendingPathComponent(filename)
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                totalBytes += Int64(size)
                count += 1
            }
        }

        return (totalBytes, count)
    }
}
