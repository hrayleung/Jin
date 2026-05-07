import Foundation

extension AppSnapshotManager {
    static func migrateLegacySnapshotsIfNeeded() {
        guard let snapshotsDirectory = try? AppDataLocations.snapshotsDirectoryURL(),
              let contents = try? FileManager.default.contentsOfDirectory(
                at: snapshotsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return
        }

        for legacyDirectory in contents where legacyDirectory.lastPathComponent.hasPrefix("backup-") {
            let manifestURL = legacyDirectory.appendingPathComponent(AppDataLocations.snapshotManifestFileName, isDirectory: false)
            guard !FileManager.default.fileExists(atPath: manifestURL.path) else { continue }

            let legacyStoreURL = legacyDirectory.appendingPathComponent(AppDataLocations.storeFileName, isDirectory: false)
            guard FileManager.default.fileExists(atPath: legacyStoreURL.path) else { continue }

            let integrity = SQLiteDatabaseSupport.quickCheck(at: legacyStoreURL)
            guard integrity.passed else { continue }

            let counts: SnapshotCoreCounts
            if let container = try? PersistenceContainerFactory.makeContainer(storeURL: legacyStoreURL) {
                counts = PersistenceContainerFactory.fetchCoreCounts(in: container)
            } else {
                counts = SnapshotCoreCounts(conversations: 0, messages: 0, providers: 0, assistants: 0, mcpServers: 0)
            }

            let manifest = SnapshotManifest(
                id: UUID().uuidString.lowercased(),
                createdAt: (try? legacyDirectory.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date(),
                reason: .legacyImport,
                appVersion: "legacy",
                schemaVersion: 0,
                includesSecrets: true,
                isAutomatic: true,
                isHealthy: !counts.isSeedLike && !counts.isEmpty,
                isLegacy: true,
                integrityDetail: integrity.detail,
                counts: counts,
                hasAttachments: false,
                hasPreferences: false,
                note: "Imported from legacy backup directory \(legacyDirectory.lastPathComponent)."
            )

            try? SnapshotManifestCoding.encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        }
    }

    static func normalizedManifest(
        _ manifest: SnapshotManifest,
        snapshotDirectory: URL
    ) -> SnapshotManifest {
        var isHealthy = manifest.isHealthy

        if manifest.isLegacy && (manifest.counts.isSeedLike || manifest.counts.isEmpty) {
            isHealthy = false
        }

        if SnapshotFileOperations.snapshotPrimaryStoreURL(in: snapshotDirectory) == nil {
            isHealthy = false
        }

        return SnapshotManifest(
            id: manifest.id,
            createdAt: manifest.createdAt,
            reason: manifest.reason,
            appVersion: manifest.appVersion,
            schemaVersion: manifest.schemaVersion,
            includesSecrets: manifest.includesSecrets,
            isAutomatic: manifest.isAutomatic,
            isHealthy: isHealthy,
            isLegacy: manifest.isLegacy,
            integrityDetail: manifest.integrityDetail,
            counts: manifest.counts,
            hasAttachments: manifest.hasAttachments,
            hasPreferences: manifest.hasPreferences,
            note: manifest.note
        )
    }

    static func validateSnapshotDirectory(_ snapshotDirectory: URL) throws -> SnapshotManifest {
        let manifestURL = snapshotDirectory.appendingPathComponent(AppDataLocations.snapshotManifestFileName, isDirectory: false)
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? SnapshotManifestCoding.decoder.decode(SnapshotManifest.self, from: manifestData) else {
            throw SnapshotError.invalidSnapshot("Snapshot manifest is missing or unreadable.")
        }

        guard let storeURL = SnapshotFileOperations.snapshotPrimaryStoreURL(in: snapshotDirectory) else {
            throw SnapshotError.invalidSnapshot("Snapshot database is missing.")
        }

        let integrity = SQLiteDatabaseSupport.quickCheck(at: storeURL)
        guard integrity.passed else {
            throw SnapshotError.invalidSnapshot("Snapshot integrity check failed: \(integrity.detail)")
        }

        return normalizedManifest(manifest, snapshotDirectory: snapshotDirectory)
    }
}
