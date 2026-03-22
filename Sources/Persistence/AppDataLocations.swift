import Foundation

enum AppDataLocations {
    private static let appSupportOverrideEnvironmentKey = "JIN_APP_SUPPORT_ROOT"
    static let sharedDirectoryName = "com.jin.app"
    static let sharedPreferencesFileName = "shared-preferences.plist"
    static let snapshotManifestFileName = "manifest.json"
    static let snapshotPreferencesFileName = "preferences.plist"
    static let storeFileName = "default.store"

    static func applicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        if let override = ProcessInfo.processInfo.environment[appSupportOverrideEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            let overrideURL = URL(fileURLWithPath: override, isDirectory: true)
            if !fileManager.fileExists(atPath: overrideURL.path) {
                try fileManager.createDirectory(at: overrideURL, withIntermediateDirectories: true)
            }
            return overrideURL
        }

        return try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    static func rootDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent(sharedDirectoryName, isDirectory: true)
    }

    static func databaseDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        try rootDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("Database", isDirectory: true)
    }

    static func storeURL(fileManager: FileManager = .default) throws -> URL {
        try databaseDirectoryURL(fileManager: fileManager)
            .appendingPathComponent(storeFileName, isDirectory: false)
    }

    static func attachmentsDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        try rootDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("Attachments", isDirectory: true)
    }

    static func snapshotsDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        try rootDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("Snapshots", isDirectory: true)
    }

    static func exportsDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        try rootDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("Exports", isDirectory: true)
    }

    static func pendingRestoreDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        try rootDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("PendingRestore", isDirectory: true)
    }

    static func cacheDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        try rootDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("Cache", isDirectory: true)
    }

    static func preferencesDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        try rootDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("Preferences", isDirectory: true)
    }

    static func sharedPreferencesFileURL(fileManager: FileManager = .default) throws -> URL {
        try preferencesDirectoryURL(fileManager: fileManager)
            .appendingPathComponent(sharedPreferencesFileName, isDirectory: false)
    }

    static func logsDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        try rootDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("Logs", isDirectory: true)
    }

    static func networkTraceDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        try logsDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("network-trace", isDirectory: true)
    }

    static func mcpRuntimeDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        try rootDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("MCP", isDirectory: true)
    }

    static func rtkDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        try rootDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("RTK", isDirectory: true)
    }

    static func searchRedirectCacheFileURL(fileManager: FileManager = .default) throws -> URL {
        try cacheDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("SearchRedirectURLCache.json", isDirectory: false)
    }

    static func searchPreviewCacheFileURL(fileManager: FileManager = .default) throws -> URL {
        try cacheDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("SearchSourcePreviewCache.json", isDirectory: false)
    }

    static func queuedRestoreDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        try pendingRestoreDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("QueuedRestore", isDirectory: true)
    }

    static func ensureDirectoriesExist(fileManager: FileManager = .default) throws {
        let directories = try [
            rootDirectoryURL(fileManager: fileManager),
            databaseDirectoryURL(fileManager: fileManager),
            attachmentsDirectoryURL(fileManager: fileManager),
            snapshotsDirectoryURL(fileManager: fileManager),
            exportsDirectoryURL(fileManager: fileManager),
            pendingRestoreDirectoryURL(fileManager: fileManager),
            queuedRestoreDirectoryURL(fileManager: fileManager),
            cacheDirectoryURL(fileManager: fileManager),
            preferencesDirectoryURL(fileManager: fileManager),
            logsDirectoryURL(fileManager: fileManager),
            networkTraceDirectoryURL(fileManager: fileManager),
            mcpRuntimeDirectoryURL(fileManager: fileManager),
            rtkDirectoryURL(fileManager: fileManager)
        ]

        for directory in directories {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }

    static func migrateLegacyDataIfNeeded(fileManager: FileManager = .default) throws {
        try ensureDirectoriesExist(fileManager: fileManager)

        let appSupport = try applicationSupportDirectory(fileManager: fileManager)
        let legacyJinRoot = appSupport.appendingPathComponent("Jin", isDirectory: true)
        let targetDatabase = try databaseDirectoryURL(fileManager: fileManager)

        let legacyStoreFiles = [
            storeFileName,
            "\(storeFileName)-shm",
            "\(storeFileName)-wal"
        ]

        for fileName in legacyStoreFiles {
            let legacyURL = appSupport.appendingPathComponent(fileName, isDirectory: false)
            let targetURL = targetDatabase.appendingPathComponent(fileName, isDirectory: false)
            try moveItemIfNeeded(from: legacyURL, to: targetURL, fileManager: fileManager)
        }

        let legacyMappings: [(URL, URL)] = try [
            (
                legacyJinRoot.appendingPathComponent("Attachments", isDirectory: true),
                attachmentsDirectoryURL(fileManager: fileManager)
            ),
            (
                legacyJinRoot.appendingPathComponent("Backups", isDirectory: true),
                snapshotsDirectoryURL(fileManager: fileManager)
            ),
            (
                legacyJinRoot.appendingPathComponent("Logs", isDirectory: true),
                logsDirectoryURL(fileManager: fileManager)
            ),
            (
                legacyJinRoot.appendingPathComponent("MCP", isDirectory: true),
                mcpRuntimeDirectoryURL(fileManager: fileManager)
            ),
            (
                legacyJinRoot.appendingPathComponent("RTK", isDirectory: true),
                rtkDirectoryURL(fileManager: fileManager)
            ),
            (
                legacyJinRoot.appendingPathComponent("SearchRedirectURLCache.json", isDirectory: false),
                searchRedirectCacheFileURL(fileManager: fileManager)
            ),
            (
                legacyJinRoot.appendingPathComponent("SearchSourcePreviewCache.json", isDirectory: false),
                searchPreviewCacheFileURL(fileManager: fileManager)
            )
        ]

        for (legacyURL, targetURL) in legacyMappings {
            if legacyURL.hasDirectoryPath {
                try mergeDirectoryContentsIfNeeded(from: legacyURL, to: targetURL, fileManager: fileManager)
            } else {
                try moveItemIfNeeded(from: legacyURL, to: targetURL, fileManager: fileManager)
            }
        }
    }

    private static func moveItemIfNeeded(from sourceURL: URL, to destinationURL: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }
        guard !fileManager.fileExists(atPath: destinationURL.path) else { return }

        let parentDirectory = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDirectory.path) {
            try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        }

        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    private static func mergeDirectoryContentsIfNeeded(from sourceURL: URL, to destinationURL: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }
        if !fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        }

        let contents = try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for itemURL in contents {
            let isDirectory = try itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? itemURL.hasDirectoryPath
            let targetURL = destinationURL.appendingPathComponent(
                itemURL.lastPathComponent,
                isDirectory: isDirectory
            )

            if fileManager.fileExists(atPath: targetURL.path) {
                let targetIsDirectory = (try? targetURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? targetURL.hasDirectoryPath
                if isDirectory && targetIsDirectory {
                    try mergeDirectoryContentsIfNeeded(from: itemURL, to: targetURL, fileManager: fileManager)
                }
                continue
            }

            try fileManager.moveItem(at: itemURL, to: targetURL)
        }

        try? fileManager.removeItem(at: sourceURL)
    }
}
