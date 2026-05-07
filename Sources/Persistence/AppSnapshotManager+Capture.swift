import Foundation

extension AppSnapshotManager {
    private static let maximumAutomaticSnapshots = 10

    static func buildSnapshotBundle(
        in bundleDirectory: URL,
        reason: SnapshotReason,
        isAutomatic: Bool,
        allowUnhealthy: Bool
    ) throws -> SnapshotSummary? {
        let storeURL = try AppDataLocations.storeURL()
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return nil }

        let snapshotID = UUID().uuidString.lowercased()
        let databaseDirectory = bundleDirectory.appendingPathComponent("Database", isDirectory: true)
        let destinationStoreURL = databaseDirectory.appendingPathComponent(AppDataLocations.storeFileName, isDirectory: false)

        try FileManager.default.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        try SQLiteDatabaseSupport.onlineBackup(from: storeURL, to: destinationStoreURL)

        let preferencesDirectory = bundleDirectory.appendingPathComponent("Preferences", isDirectory: true)
        let preferencesURL = preferencesDirectory.appendingPathComponent(
            AppDataLocations.snapshotPreferencesFileName,
            isDirectory: false
        )
        let livePreferencesDirectory = try AppDataLocations.preferencesDirectoryURL()
        if FileManager.default.fileExists(atPath: livePreferencesDirectory.path) {
            try SnapshotFileOperations.copyDirectoryContents(from: livePreferencesDirectory, to: preferencesDirectory)
        } else {
            try FileManager.default.createDirectory(at: preferencesDirectory, withIntermediateDirectories: true)
        }
        let preferencesData = try AppPreferencesSnapshotStore.snapshotPreferenceData()
        try preferencesData.write(to: preferencesURL, options: .atomic)

        let liveAttachmentsURL = try AppDataLocations.attachmentsDirectoryURL()
        let snapshotAttachmentsURL = bundleDirectory.appendingPathComponent("Attachments", isDirectory: true)
        let hasAttachments = FileManager.default.fileExists(atPath: liveAttachmentsURL.path)
        if hasAttachments {
            try SnapshotFileOperations.copyDirectoryContents(from: liveAttachmentsURL, to: snapshotAttachmentsURL)
        }

        let integrity = SQLiteDatabaseSupport.quickCheck(at: destinationStoreURL)
        if !integrity.passed && !allowUnhealthy {
            return nil
        }

        let counts: SnapshotCoreCounts
        if let snapshotContainer = try? PersistenceContainerFactory.makeContainer(storeURL: destinationStoreURL) {
            counts = PersistenceContainerFactory.fetchCoreCounts(in: snapshotContainer)
        } else if allowUnhealthy {
            counts = SnapshotCoreCounts(conversations: 0, messages: 0, providers: 0, assistants: 0, mcpServers: 0)
        } else {
            return nil
        }

        let isHealthy = integrity.passed && !counts.isSeedLike && !counts.isEmpty
        let manifest = SnapshotManifest(
            id: snapshotID,
            createdAt: Date(),
            reason: reason,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
            schemaVersion: 1,
            includesSecrets: true,
            isAutomatic: isAutomatic,
            isHealthy: isHealthy,
            isLegacy: false,
            integrityDetail: integrity.detail,
            counts: counts,
            hasAttachments: hasAttachments,
            hasPreferences: true,
            note: nil
        )
        let manifestURL = bundleDirectory.appendingPathComponent(AppDataLocations.snapshotManifestFileName, isDirectory: false)
        try SnapshotManifestCoding.encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        return SnapshotSummary(manifest: manifest, directoryURL: bundleDirectory)
    }

    @discardableResult
    static func captureAutomaticSnapshot(
        reason: SnapshotReason,
        isAutomatic: Bool = true,
        allowUnhealthy: Bool = false
    ) throws -> SnapshotSummary? {
        let stagingDirectory = try makeStagingSnapshotDirectory()
        guard let summary = try buildSnapshotBundle(
            in: stagingDirectory,
            reason: reason,
            isAutomatic: isAutomatic,
            allowUnhealthy: allowUnhealthy
        ) else {
            try? FileManager.default.removeItem(at: stagingDirectory)
            return nil
        }

        let finalDirectory = try AppDataLocations.snapshotsDirectoryURL()
            .appendingPathComponent(snapshotDirectoryName(for: summary.manifest), isDirectory: true)
        if FileManager.default.fileExists(atPath: finalDirectory.path) {
            try FileManager.default.removeItem(at: finalDirectory)
        }
        try FileManager.default.moveItem(at: stagingDirectory, to: finalDirectory)

        let publishedSummary = SnapshotSummary(manifest: summary.manifest, directoryURL: finalDirectory)
        if isAutomatic {
            pruneAutomaticSnapshots()
        }
        return publishedSummary
    }

    static func latestHealthySnapshot() -> SnapshotSummary? {
        listSnapshots().first(where: { $0.manifest.isHealthy })
    }

    static func listSnapshots() -> [SnapshotSummary] {
        guard let snapshotsDirectory = try? AppDataLocations.snapshotsDirectoryURL(),
              FileManager.default.fileExists(atPath: snapshotsDirectory.path) else {
            return []
        }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: snapshotsDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents.compactMap { directoryURL in
            let manifestURL = directoryURL.appendingPathComponent(AppDataLocations.snapshotManifestFileName, isDirectory: false)
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? SnapshotManifestCoding.decoder.decode(SnapshotManifest.self, from: data) else {
                return nil
            }
            return SnapshotSummary(
                manifest: normalizedManifest(manifest, snapshotDirectory: directoryURL),
                directoryURL: directoryURL
            )
        }
        .sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }

    private static func snapshotDirectoryName(for manifest: SnapshotManifest) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: manifest.createdAt)
            .replacingOccurrences(of: ":", with: "")
        return "snapshot-\(timestamp)-\(manifest.id.prefix(8))"
    }

    private static func makeStagingSnapshotDirectory() throws -> URL {
        let stagingDirectory = try AppDataLocations.snapshotsDirectoryURL()
            .appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        if FileManager.default.fileExists(atPath: stagingDirectory.path) {
            try FileManager.default.removeItem(at: stagingDirectory)
        }
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        return stagingDirectory
    }

    private static func pruneAutomaticSnapshots() {
        let automaticSnapshots = listSnapshots().filter(\.manifest.isAutomatic)
        guard automaticSnapshots.count > maximumAutomaticSnapshots else { return }

        let protectedSnapshotID = latestHealthySnapshot()?.id
        for snapshot in automaticSnapshots.dropFirst(maximumAutomaticSnapshots) {
            if snapshot.id == protectedSnapshotID {
                continue
            }
            try? FileManager.default.removeItem(at: snapshot.directoryURL)
        }
    }
}
