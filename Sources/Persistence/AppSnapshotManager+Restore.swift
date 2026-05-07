import Foundation

extension AppSnapshotManager {
    static func restoreSnapshot(_ snapshot: SnapshotSummary) throws {
        try restoreSnapshotDirectory(snapshot.directoryURL)
    }

    static func queueSnapshotForRestore(_ snapshot: SnapshotSummary) throws {
        let queuedDirectory = try AppDataLocations.queuedRestoreDirectoryURL()
        if FileManager.default.fileExists(atPath: queuedDirectory.path) {
            try FileManager.default.removeItem(at: queuedDirectory)
        }
        try FileManager.default.createDirectory(at: queuedDirectory, withIntermediateDirectories: true)
        try SnapshotFileOperations.copyDirectoryContents(from: snapshot.directoryURL, to: queuedDirectory)
    }

    static func queueImportArchiveForRestore(from archiveURL: URL) throws {
        let extractedDirectory = try SnapshotFileOperations.extractArchiveToTemporaryDirectory(archiveURL)
        defer { try? FileManager.default.removeItem(at: extractedDirectory) }

        let packageDirectory = try SnapshotFileOperations.locateSnapshotDirectory(in: extractedDirectory)
        _ = try validateSnapshotDirectory(packageDirectory)
        let queuedDirectory = try AppDataLocations.queuedRestoreDirectoryURL()
        if FileManager.default.fileExists(atPath: queuedDirectory.path) {
            try FileManager.default.removeItem(at: queuedDirectory)
        }
        try FileManager.default.createDirectory(at: queuedDirectory, withIntermediateDirectories: true)
        try SnapshotFileOperations.copyDirectoryContents(from: packageDirectory, to: queuedDirectory)
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

        try SnapshotFileOperations.runDitto(arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", snapshot.directoryURL.path, destinationURL.path])
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

    static func restoreSnapshotDirectory(_ snapshotDirectory: URL) throws {
        let manifest = try validateSnapshotDirectory(snapshotDirectory)

        let pendingRoot = try AppDataLocations.pendingRestoreDirectoryURL()
            .appendingPathComponent("restore-\(UUID().uuidString)", isDirectory: true)
        let pendingDatabase = pendingRoot.appendingPathComponent("Database", isDirectory: true)
        try FileManager.default.createDirectory(at: pendingDatabase, withIntermediateDirectories: true)
        try SnapshotFileOperations.copySnapshotDatabaseArtifacts(from: snapshotDirectory, to: pendingDatabase)

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
            try SnapshotFileOperations.copyDirectoryContents(from: liveDatabase, to: rollbackDatabase)
        }
        if FileManager.default.fileExists(atPath: liveAttachments.path) {
            try SnapshotFileOperations.copyDirectoryContents(from: liveAttachments, to: rollbackAttachments)
        }
        if FileManager.default.fileExists(atPath: livePreferences.path) {
            try SnapshotFileOperations.copyDirectoryContents(from: livePreferences, to: rollbackPreferencesDirectory)
        }
        if let currentPreferencesData = try? AppPreferencesSnapshotStore.snapshotPreferenceData() {
            try currentPreferencesData.write(to: rollbackPreferences, options: .atomic)
        }

        do {
            try SnapshotFileOperations.replaceDirectory(at: liveDatabase, with: pendingDatabase)

            if manifest.hasAttachments {
                try SnapshotFileOperations.replaceDirectory(at: liveAttachments, with: attachmentsDirectory)
            } else if FileManager.default.fileExists(atPath: liveAttachments.path) {
                try FileManager.default.removeItem(at: liveAttachments)
            }

            if FileManager.default.fileExists(atPath: preferencesDirectory.path) {
                try SnapshotFileOperations.replaceDirectory(at: livePreferences, with: preferencesDirectory)
            }

            if FileManager.default.fileExists(atPath: preferencesURL.path) {
                AppPreferencesSnapshotStore.applyPreferenceFile(at: preferencesURL)
                SnapshotFileOperations.removeTransientPreferenceSnapshotFile(from: livePreferences)
            }
        } catch {
            if FileManager.default.fileExists(atPath: rollbackDatabase.path) {
                try? SnapshotFileOperations.replaceDirectory(at: liveDatabase, with: rollbackDatabase)
            }
            if FileManager.default.fileExists(atPath: rollbackAttachments.path) {
                try? SnapshotFileOperations.replaceDirectory(at: liveAttachments, with: rollbackAttachments)
            }
            if FileManager.default.fileExists(atPath: rollbackPreferencesDirectory.path) {
                try? SnapshotFileOperations.replaceDirectory(at: livePreferences, with: rollbackPreferencesDirectory)
            }
            if FileManager.default.fileExists(atPath: rollbackPreferences.path) {
                AppPreferencesSnapshotStore.applyPreferenceFile(at: rollbackPreferences)
                SnapshotFileOperations.removeTransientPreferenceSnapshotFile(from: livePreferences)
            }
            try? FileManager.default.removeItem(at: pendingRoot)
            throw error
        }

        try? FileManager.default.removeItem(at: pendingRoot)

        AppRuntimeProtection.automaticSnapshotsSuspended = !manifest.isHealthy
        clearAcceptedCurrentState()
    }
}
