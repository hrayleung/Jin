import Foundation
import SwiftData

enum SnapshotReason: String, Codable, Sendable {
    case launchHealthy
    case periodic
    case termination
    case manualExport
    case beforeDestructiveAction
    case importedArchive
    case legacyImport
}

struct SnapshotCoreCounts: Codable, Equatable, Sendable {
    let conversations: Int
    let messages: Int
    let providers: Int
    let assistants: Int
    let mcpServers: Int

    var total: Int {
        conversations + messages + providers + assistants + mcpServers
    }

    var isEmpty: Bool {
        total == 0
    }

    var isSeedLike: Bool {
        conversations == 0
            && messages == 0
            && assistants <= 1
            && providers <= DefaultProviderSeeds.allProviders().count
            && mcpServers <= 2
    }
}

struct SnapshotManifest: Codable, Identifiable, Sendable {
    let id: String
    let createdAt: Date
    let reason: SnapshotReason
    let appVersion: String
    let schemaVersion: Int
    let includesSecrets: Bool
    let isAutomatic: Bool
    let isHealthy: Bool
    let isLegacy: Bool
    let integrityDetail: String
    let counts: SnapshotCoreCounts
    let hasAttachments: Bool
    let hasPreferences: Bool
    let note: String?
}

struct SnapshotSummary: Identifiable, Sendable {
    let manifest: SnapshotManifest
    let directoryURL: URL

    var id: String { manifest.id }
}

struct StartupRecoveryState: Sendable {
    let issueDescription: String
    let snapshots: [SnapshotSummary]
    let canContinueCurrentState: Bool
}

enum StartupStoreEvaluation {
    case ready(ModelContainer)
    case recovery(StartupRecoveryState, ModelContainer?)
}

enum AppSnapshotManager {
    private static let acceptedCurrentStateDefaultsKey = "recovery.acceptedCurrentState"
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let maximumAutomaticSnapshots = 10

    static func evaluateCurrentStoreForStartup() throws -> StartupStoreEvaluation {
        try AppDataLocations.migrateLegacyDataIfNeeded()
        migrateLegacySnapshotsIfNeeded()

        if let queuedRestoreError = applyQueuedRestoreIfPresent() {
            NSLog("Jin recovery warning: %@", queuedRestoreError)
        }

        let storeURL = try AppDataLocations.storeURL()

        if FileManager.default.fileExists(atPath: storeURL.path) {
            let integrity = SQLiteDatabaseSupport.quickCheck(at: storeURL)

            if integrity.passed {
                do {
                    let container = try PersistenceContainerFactory.makeContainer(storeURL: storeURL)
                    let currentCounts = PersistenceContainerFactory.fetchCoreCounts(in: container)
                    let latestHealthy = latestHealthySnapshot()

                    if shouldTriggerRecovery(currentCounts: currentCounts, latestHealthySnapshot: latestHealthy?.manifest) {
                        let snapshots = listSnapshots()
                        return .recovery(
                            StartupRecoveryState(
                                issueDescription: "Jin detected possible data loss. The current database has \(currentCounts.total) items, but a recent snapshot has \(latestHealthy!.manifest.counts.total).",
                                snapshots: snapshots,
                                canContinueCurrentState: true
                            ),
                            container
                        )
                    }

                    return .ready(container)
                } catch {
                    NSLog("Jin startup warning: store failed to open: %@", error.localizedDescription)
                    let snapshots = listSnapshots()
                    if snapshots.contains(where: { $0.manifest.isHealthy }) {
                        return .recovery(
                            StartupRecoveryState(
                                issueDescription: "Jin could not open the database: \(error.localizedDescription)",
                                snapshots: snapshots,
                                canContinueCurrentState: false
                            ),
                            nil
                        )
                    }
                }
            } else {
                NSLog("Jin startup warning: integrity check failed: %@", integrity.detail)
                let snapshots = listSnapshots()
                if snapshots.contains(where: { $0.manifest.isHealthy }) {
                    return .recovery(
                        StartupRecoveryState(
                            issueDescription: "Jin's database failed its integrity check: \(integrity.detail)",
                            snapshots: snapshots,
                            canContinueCurrentState: false
                        ),
                        nil
                    )
                }
            }

            NSLog("Jin startup warning: no healthy snapshots available, starting fresh.")
        }

        SQLiteDatabaseSupport.removeStoreArtifacts(at: storeURL)
        clearAcceptedCurrentState()
        return .ready(try PersistenceContainerFactory.makeContainer(storeURL: storeURL))
    }

    static func shouldTriggerRecovery(
        currentCounts: SnapshotCoreCounts,
        latestHealthySnapshot: SnapshotManifest?
    ) -> Bool {
        guard let latestHealthySnapshot else { return false }
        guard latestHealthySnapshot.counts.total > 0 else { return false }
        if acceptedCurrentStateMatches(currentCounts) {
            return false
        }
        return currentCounts.isEmpty || currentCounts.isSeedLike
    }

    static func recordAcceptedCurrentState(_ counts: SnapshotCoreCounts) {
        guard let data = try? JSONEncoder().encode(counts) else { return }
        UserDefaults.standard.set(data, forKey: acceptedCurrentStateDefaultsKey)
    }

    static func clearAcceptedCurrentState() {
        UserDefaults.standard.removeObject(forKey: acceptedCurrentStateDefaultsKey)
    }

    private static func buildSnapshotBundle(
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
            try copyDirectoryContents(from: livePreferencesDirectory, to: preferencesDirectory)
        } else {
            try FileManager.default.createDirectory(at: preferencesDirectory, withIntermediateDirectories: true)
        }
        let preferencesData = try AppPreferencesSnapshotStore.snapshotPreferenceData()
        try preferencesData.write(to: preferencesURL, options: .atomic)

        let liveAttachmentsURL = try AppDataLocations.attachmentsDirectoryURL()
        let snapshotAttachmentsURL = bundleDirectory.appendingPathComponent("Attachments", isDirectory: true)
        let hasAttachments = FileManager.default.fileExists(atPath: liveAttachmentsURL.path)
        if hasAttachments {
            try copyDirectoryContents(from: liveAttachmentsURL, to: snapshotAttachmentsURL)
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
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

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
                  let manifest = try? decoder.decode(SnapshotManifest.self, from: data) else {
                return nil
            }
            return SnapshotSummary(
                manifest: normalizedManifest(manifest, snapshotDirectory: directoryURL),
                directoryURL: directoryURL
            )
        }
        .sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }

    static func restoreSnapshot(_ snapshot: SnapshotSummary) throws {
        try restoreSnapshotDirectory(snapshot.directoryURL)
    }

    static func queueSnapshotForRestore(_ snapshot: SnapshotSummary) throws {
        let queuedDirectory = try AppDataLocations.queuedRestoreDirectoryURL()
        if FileManager.default.fileExists(atPath: queuedDirectory.path) {
            try FileManager.default.removeItem(at: queuedDirectory)
        }
        try FileManager.default.createDirectory(at: queuedDirectory, withIntermediateDirectories: true)
        try copyDirectoryContents(from: snapshot.directoryURL, to: queuedDirectory)
    }

    static func queueImportArchiveForRestore(from archiveURL: URL) throws {
        let extractedDirectory = try extractArchiveToTemporaryDirectory(archiveURL)
        defer { try? FileManager.default.removeItem(at: extractedDirectory) }

        let packageDirectory = try locateSnapshotDirectory(in: extractedDirectory)
        _ = try validateSnapshotDirectory(packageDirectory)
        let queuedDirectory = try AppDataLocations.queuedRestoreDirectoryURL()
        if FileManager.default.fileExists(atPath: queuedDirectory.path) {
            try FileManager.default.removeItem(at: queuedDirectory)
        }
        try FileManager.default.createDirectory(at: queuedDirectory, withIntermediateDirectories: true)
        try copyDirectoryContents(from: packageDirectory, to: queuedDirectory)
    }

    static func exportRecoveryArchive(to destinationURL: URL) throws {
        let temporarySnapshotDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jin-export-\(UUID().uuidString)", isDirectory: true)
        if FileManager.default.fileExists(atPath: temporarySnapshotDirectory.path) {
            try FileManager.default.removeItem(at: temporarySnapshotDirectory)
        }
        try FileManager.default.createDirectory(at: temporarySnapshotDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporarySnapshotDirectory) }

        guard let snapshot = try buildSnapshotBundle(
            in: temporarySnapshotDirectory,
            reason: .manualExport,
            isAutomatic: false,
            allowUnhealthy: true
        ) else {
            throw SnapshotError.exportFailed("Jin could not export the current data.")
        }

        let destinationDirectory = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: destinationDirectory.path) {
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        }
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try runDitto(arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", snapshot.directoryURL.path, destinationURL.path])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationURL.path)
    }

    static func applyQueuedRestoreIfPresent() -> String? {
        guard let queuedDirectory = try? AppDataLocations.queuedRestoreDirectoryURL() else {
            return "Jin could not access the queued restore directory."
        }
        guard FileManager.default.fileExists(atPath: queuedDirectory.path) else { return nil }
        do {
            try restoreSnapshotDirectory(queuedDirectory)
            try? FileManager.default.removeItem(at: queuedDirectory)
            clearAcceptedCurrentState()
            return nil
        } catch {
            let failedDirectory = queuedDirectory.deletingLastPathComponent()
                .appendingPathComponent("Failed-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.moveItem(at: queuedDirectory, to: failedDirectory)
            return "Jin preserved your current data because the queued recovery pack failed validation: \(error.localizedDescription)"
        }
    }

    private static func restoreSnapshotDirectory(_ snapshotDirectory: URL) throws {
        let manifest = try validateSnapshotDirectory(snapshotDirectory)

        let pendingRoot = try AppDataLocations.pendingRestoreDirectoryURL()
            .appendingPathComponent("restore-\(UUID().uuidString)", isDirectory: true)
        let pendingDatabase = pendingRoot.appendingPathComponent("Database", isDirectory: true)
        try FileManager.default.createDirectory(at: pendingDatabase, withIntermediateDirectories: true)
        try copySnapshotDatabaseArtifacts(from: snapshotDirectory, to: pendingDatabase)

        let liveDatabase = try AppDataLocations.databaseDirectoryURL()
        let attachmentsDirectory = snapshotDirectory.appendingPathComponent("Attachments", isDirectory: true)
        let preferencesDirectory = snapshotDirectory.appendingPathComponent("Preferences", isDirectory: true)
        let preferencesURL = preferencesDirectory.appendingPathComponent(
            AppDataLocations.snapshotPreferencesFileName,
            isDirectory: false
        )
        let liveAttachments = try AppDataLocations.attachmentsDirectoryURL()
        let livePreferences = try AppDataLocations.preferencesDirectoryURL()

        let rollbackRoot = pendingRoot.appendingPathComponent("Rollback", isDirectory: true)
        try FileManager.default.createDirectory(at: rollbackRoot, withIntermediateDirectories: true)
        let rollbackDatabase = rollbackRoot.appendingPathComponent("Database", isDirectory: true)
        let rollbackAttachments = rollbackRoot.appendingPathComponent("Attachments", isDirectory: true)
        let rollbackPreferencesDirectory = rollbackRoot.appendingPathComponent("Preferences", isDirectory: true)
        let rollbackPreferences = rollbackRoot.appendingPathComponent(AppDataLocations.snapshotPreferencesFileName, isDirectory: false)

        if FileManager.default.fileExists(atPath: liveDatabase.path) {
            try copyDirectoryContents(from: liveDatabase, to: rollbackDatabase)
        }
        if FileManager.default.fileExists(atPath: liveAttachments.path) {
            try copyDirectoryContents(from: liveAttachments, to: rollbackAttachments)
        }
        if FileManager.default.fileExists(atPath: livePreferences.path) {
            try copyDirectoryContents(from: livePreferences, to: rollbackPreferencesDirectory)
        }
        if let currentPreferencesData = try? AppPreferencesSnapshotStore.snapshotPreferenceData() {
            try currentPreferencesData.write(to: rollbackPreferences, options: .atomic)
        }

        do {
            try replaceDirectory(at: liveDatabase, with: pendingDatabase)

            if manifest.hasAttachments {
                try replaceDirectory(at: liveAttachments, with: attachmentsDirectory)
            } else if FileManager.default.fileExists(atPath: liveAttachments.path) {
                try FileManager.default.removeItem(at: liveAttachments)
            }

            if FileManager.default.fileExists(atPath: preferencesDirectory.path) {
                try replaceDirectory(at: livePreferences, with: preferencesDirectory)
            }

            if FileManager.default.fileExists(atPath: preferencesURL.path) {
                AppPreferencesSnapshotStore.applyPreferenceFile(at: preferencesURL)
                removeTransientPreferenceSnapshotFile(from: livePreferences)
            }
        } catch {
            if FileManager.default.fileExists(atPath: rollbackDatabase.path) {
                try? replaceDirectory(at: liveDatabase, with: rollbackDatabase)
            }
            if FileManager.default.fileExists(atPath: rollbackAttachments.path) {
                try? replaceDirectory(at: liveAttachments, with: rollbackAttachments)
            }
            if FileManager.default.fileExists(atPath: rollbackPreferencesDirectory.path) {
                try? replaceDirectory(at: livePreferences, with: rollbackPreferencesDirectory)
            }
            if FileManager.default.fileExists(atPath: rollbackPreferences.path) {
                AppPreferencesSnapshotStore.applyPreferenceFile(at: rollbackPreferences)
                removeTransientPreferenceSnapshotFile(from: livePreferences)
            }
            try? FileManager.default.removeItem(at: pendingRoot)
            throw error
        }

        try? FileManager.default.removeItem(at: pendingRoot)

        AppRuntimeProtection.automaticSnapshotsSuspended = !manifest.isHealthy
        clearAcceptedCurrentState()
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

    private static func migrateLegacySnapshotsIfNeeded() {
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

            try? encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        }
    }

    private static func replaceDirectory(at liveURL: URL, with sourceURL: URL) throws {
        let stagedReplacement = sourceURL.deletingLastPathComponent()
            .appendingPathComponent("\(liveURL.lastPathComponent)-replacement-\(UUID().uuidString)", isDirectory: true)
        if FileManager.default.fileExists(atPath: stagedReplacement.path) {
            try FileManager.default.removeItem(at: stagedReplacement)
        }
        try FileManager.default.copyItem(at: sourceURL, to: stagedReplacement)

        if FileManager.default.fileExists(atPath: liveURL.path) {
            _ = try FileManager.default.replaceItemAt(
                liveURL,
                withItemAt: stagedReplacement,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            let parentDirectory = liveURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDirectory.path) {
                try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
            }
            try FileManager.default.moveItem(at: stagedReplacement, to: liveURL)
        }
    }

    private static func copyDirectoryContents(from sourceURL: URL, to destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    private static func removeTransientPreferenceSnapshotFile(from preferencesDirectory: URL) {
        let snapshotPreferenceURL = preferencesDirectory
            .appendingPathComponent(AppDataLocations.snapshotPreferencesFileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: snapshotPreferenceURL.path) else { return }
        try? FileManager.default.removeItem(at: snapshotPreferenceURL)
    }

    private static func normalizedManifest(
        _ manifest: SnapshotManifest,
        snapshotDirectory: URL
    ) -> SnapshotManifest {
        var isHealthy = manifest.isHealthy

        if manifest.isLegacy && (manifest.counts.isSeedLike || manifest.counts.isEmpty) {
            isHealthy = false
        }

        if snapshotPrimaryStoreURL(in: snapshotDirectory) == nil {
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

    private static func extractArchiveToTemporaryDirectory(_ archiveURL: URL) throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jin-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try runDitto(arguments: ["-x", "-k", archiveURL.path, temporaryDirectory.path])
        return temporaryDirectory
    }

    private static func locateSnapshotDirectory(in extractedDirectory: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: extractedDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        if let directMatch = contents.first(where: {
            FileManager.default.fileExists(
                atPath: $0.appendingPathComponent(AppDataLocations.snapshotManifestFileName, isDirectory: false).path
            )
        }) {
            return directMatch
        }

        if FileManager.default.fileExists(
            atPath: extractedDirectory.appendingPathComponent(AppDataLocations.snapshotManifestFileName, isDirectory: false).path
        ) {
            return extractedDirectory
        }

        throw SnapshotError.invalidSnapshot("Imported archive does not contain a valid Jin snapshot.")
    }

    private static func validateSnapshotDirectory(_ snapshotDirectory: URL) throws -> SnapshotManifest {
        let manifestURL = snapshotDirectory.appendingPathComponent(AppDataLocations.snapshotManifestFileName, isDirectory: false)
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? decoder.decode(SnapshotManifest.self, from: manifestData) else {
            throw SnapshotError.invalidSnapshot("Snapshot manifest is missing or unreadable.")
        }

        guard let storeURL = snapshotPrimaryStoreURL(in: snapshotDirectory) else {
            throw SnapshotError.invalidSnapshot("Snapshot database is missing.")
        }

        let integrity = SQLiteDatabaseSupport.quickCheck(at: storeURL)
        guard integrity.passed else {
            throw SnapshotError.invalidSnapshot("Snapshot integrity check failed: \(integrity.detail)")
        }

        return normalizedManifest(manifest, snapshotDirectory: snapshotDirectory)
    }

    private static func acceptedCurrentStateMatches(_ counts: SnapshotCoreCounts) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: acceptedCurrentStateDefaultsKey),
              let accepted = try? JSONDecoder().decode(SnapshotCoreCounts.self, from: data) else {
            return false
        }
        return accepted == counts
    }

    private static func snapshotPrimaryStoreURL(in snapshotDirectory: URL) -> URL? {
        let nestedStoreURL = snapshotDirectory
            .appendingPathComponent("Database", isDirectory: true)
            .appendingPathComponent(AppDataLocations.storeFileName, isDirectory: false)
        if FileManager.default.fileExists(atPath: nestedStoreURL.path) {
            return nestedStoreURL
        }

        let legacyStoreURL = snapshotDirectory
            .appendingPathComponent(AppDataLocations.storeFileName, isDirectory: false)
        if FileManager.default.fileExists(atPath: legacyStoreURL.path) {
            return legacyStoreURL
        }

        return nil
    }

    private static func copySnapshotDatabaseArtifacts(from snapshotDirectory: URL, to destinationDirectory: URL) throws {
        guard let sourceStoreURL = snapshotPrimaryStoreURL(in: snapshotDirectory) else {
            throw SnapshotError.invalidSnapshot("Snapshot database is missing.")
        }

        let sourceParentDirectory = sourceStoreURL.deletingLastPathComponent()
        let fileNames = [
            AppDataLocations.storeFileName,
            "\(AppDataLocations.storeFileName)-shm",
            "\(AppDataLocations.storeFileName)-wal"
        ]

        for fileName in fileNames {
            let sourceURL = sourceParentDirectory.appendingPathComponent(fileName, isDirectory: false)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            let destinationURL = destinationDirectory.appendingPathComponent(fileName, isDirectory: false)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func runDitto(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SnapshotError.exportFailed(message?.isEmpty == false ? message! : "ditto failed.")
        }
    }
}

enum SnapshotError: LocalizedError {
    case invalidSnapshot(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSnapshot(let message), .exportFailed(let message):
            return message
        }
    }
}

enum AppRuntimeProtection {
    static var automaticSnapshotsSuspended = false
}
