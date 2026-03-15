import Foundation
import os.log

/// Manages automatic backup and recovery of the SwiftData store files.
///
/// Backups are stored in `~/Library/Application Support/Jin/Backups/`
/// and pruned to keep only the most recent copies.
///
/// Recovery flow (called during app init):
/// 1. Create ModelContainer → check data integrity
/// 2. If healthy → update backup for future recovery
/// 3. If data loss detected → restore latest backup, recreate container
/// 4. If container creation fails → restore backup or start fresh
enum DatabaseBackupManager {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.example.Jin",
        category: "DatabaseBackup"
    )

    private static let fileManager = FileManager.default
    private static let maxBackups = 3

    private static let storeFileNames = [
        "default.store",
        "default.store-shm",
        "default.store-wal"
    ]

    // MARK: - Paths

    static var storeDirectory: URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    private static var backupBaseDirectory: URL? {
        guard let appSupport = storeDirectory else { return nil }
        return appSupport
            .appendingPathComponent("Jin", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
    }

    // MARK: - Backup

    /// Creates a timestamped backup of the current store files.
    /// Only backs up when the main store exceeds 32 KB (schema-only stores are skipped).
    @discardableResult
    static func createBackup() -> Bool {
        guard let storeDir = storeDirectory,
              let backupBase = backupBaseDirectory else {
            logger.warning("Cannot determine store or backup directory")
            return false
        }

        let mainStore = storeDir.appendingPathComponent("default.store")
        guard fileManager.fileExists(atPath: mainStore.path) else {
            logger.info("No store file to backup")
            return false
        }

        // Skip trivially small stores (just the schema, no user data)
        if let attrs = try? fileManager.attributesOfItem(atPath: mainStore.path),
           let size = attrs[.size] as? Int64,
           size < 32_768 {
            logger.info("Store too small to backup (\(size) bytes)")
            return false
        }

        // Use timestamp + short UUID suffix to avoid collisions when called
        // multiple times within the same second (e.g. launch + immediate quit).
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss"
        let timestamp = formatter.string(from: Date())
        let suffix = UUID().uuidString.prefix(6)
        let backupDir = backupBase.appendingPathComponent(
            "backup-\(timestamp)-\(suffix)", isDirectory: true
        )

        // If the directory already exists (extremely unlikely), skip rather than risk
        // destroying an existing backup on error cleanup.
        guard !fileManager.fileExists(atPath: backupDir.path) else {
            logger.warning("Backup directory already exists, skipping: \(backupDir.lastPathComponent)")
            return false
        }

        do {
            try fileManager.createDirectory(
                at: backupDir, withIntermediateDirectories: true
            )

            for fileName in storeFileNames {
                let source = storeDir.appendingPathComponent(fileName)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                let dest = backupDir.appendingPathComponent(fileName)
                try fileManager.copyItem(at: source, to: dest)
            }

            pruneOldBackups()
            logger.info("Backup created: \(backupDir.lastPathComponent)")
            return true
        } catch {
            logger.error("Backup failed: \(error.localizedDescription)")
            // Only clean up if we created this directory ourselves just now.
            // The existence-check guard above ensures we never reach here for
            // a pre-existing directory, so this removal is safe.
            try? fileManager.removeItem(at: backupDir)
            return false
        }
    }

    // MARK: - Restore

    /// Replaces current store files with the most recent backup.
    ///
    /// Uses a staging directory so the current store is only removed after the
    /// backup files have been successfully copied, avoiding a half-restored state
    /// if the copy fails partway through.
    @discardableResult
    static func restoreLatestBackup() -> Bool {
        guard let storeDir = storeDirectory,
              let backupDir = latestBackupDirectory() else {
            logger.warning("No backup available to restore")
            return false
        }

        logger.info("Attempting restore from \(backupDir.lastPathComponent)")

        let backupMainStore = backupDir.appendingPathComponent("default.store")
        guard fileManager.fileExists(atPath: backupMainStore.path) else {
            logger.error("Backup missing required file: default.store")
            return false
        }

        // Stage: copy backup files into a temp directory first
        let stagingDir = storeDir.appendingPathComponent(
            "restore-staging-\(UUID().uuidString)", isDirectory: true
        )
        let rollbackDir = storeDir.appendingPathComponent(
            "restore-rollback-\(UUID().uuidString)", isDirectory: true
        )

        do {
            try fileManager.createDirectory(
                at: stagingDir, withIntermediateDirectories: true
            )

            for fileName in storeFileNames {
                let source = backupDir.appendingPathComponent(fileName)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                let dest = stagingDir.appendingPathComponent(fileName)
                try fileManager.copyItem(at: source, to: dest)
            }

            let stagedMainStore = stagingDir.appendingPathComponent("default.store")
            guard fileManager.fileExists(atPath: stagedMainStore.path) else {
                logger.error("Restore staging missing required file: default.store")
                try? fileManager.removeItem(at: stagingDir)
                return false
            }
        } catch {
            logger.error("Restore staging failed: \(error.localizedDescription)")
            try? fileManager.removeItem(at: stagingDir)
            return false
        }

        // Swap: move current files to a rollback directory, then move staged files into place.
        // If anything fails, roll back to the pre-restore state and keep the rollback directory
        // only if we cannot fully restore the original files.
        var movedCurrentFileNames: [String] = []
        var movedStagedFileNames: [String] = []

        do {
            try fileManager.createDirectory(
                at: rollbackDir, withIntermediateDirectories: true
            )

            for fileName in storeFileNames {
                let current = storeDir.appendingPathComponent(fileName)
                guard fileManager.fileExists(atPath: current.path) else { continue }
                let rollbackFile = rollbackDir.appendingPathComponent(fileName)
                try fileManager.moveItem(at: current, to: rollbackFile)
                movedCurrentFileNames.append(fileName)
            }

            for fileName in storeFileNames {
                let staged = stagingDir.appendingPathComponent(fileName)
                guard fileManager.fileExists(atPath: staged.path) else { continue }

                let dest = storeDir.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: dest.path) {
                    throw NSError(
                        domain: "DatabaseBackupManager",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Destination already exists for \(fileName)"
                        ]
                    )
                }

                try fileManager.moveItem(at: staged, to: dest)
                movedStagedFileNames.append(fileName)
            }

            try? fileManager.removeItem(at: stagingDir)
            try? fileManager.removeItem(at: rollbackDir)
            logger.info("Restore succeeded from \(backupDir.lastPathComponent)")
            return true
        } catch {
            logger.error("Restore swap failed: \(error.localizedDescription)")

            for fileName in movedStagedFileNames {
                let restoredFile = storeDir.appendingPathComponent(fileName)
                try? fileManager.removeItem(at: restoredFile)
            }

            for fileName in movedCurrentFileNames {
                let rollbackFile = rollbackDir.appendingPathComponent(fileName)
                guard fileManager.fileExists(atPath: rollbackFile.path) else { continue }
                let dest = storeDir.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: dest.path) {
                    try? fileManager.removeItem(at: dest)
                }
                try? fileManager.moveItem(at: rollbackFile, to: dest)
            }

            try? fileManager.removeItem(at: stagingDir)

            let rollbackNeeded = movedCurrentFileNames.contains { fileName in
                let dest = storeDir.appendingPathComponent(fileName)
                return !fileManager.fileExists(atPath: dest.path)
            }

            if rollbackNeeded {
                logger.warning("Restore rollback incomplete — leaving \(rollbackDir.lastPathComponent) for manual recovery")
            } else {
                try? fileManager.removeItem(at: rollbackDir)
            }

            return false
        }
    }

    // MARK: - Clean Slate

    /// Deletes all current store files so a fresh database can be created.
    /// This is a last resort when both normal creation and backup restore fail.
    static func deleteCurrentStore() {
        guard let storeDir = storeDirectory else { return }
        for fileName in storeFileNames {
            let file = storeDir.appendingPathComponent(fileName)
            try? fileManager.removeItem(at: file)
        }
        logger.warning("Deleted current store files (clean slate)")
    }

    // MARK: - Query

    /// Returns `true` if at least one backup directory exists.
    static var hasBackup: Bool {
        latestBackupDirectory() != nil
    }

    // MARK: - Private

    private static func latestBackupDirectory() -> URL? {
        guard let base = backupBaseDirectory,
              fileManager.fileExists(atPath: base.path) else {
            return nil
        }

        let contents = (try? fileManager.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents
            .filter { $0.lastPathComponent.hasPrefix("backup-") }
            .sorted { a, b in
                let aDate = (try? a.resourceValues(forKeys: [.creationDateKey]))?
                    .creationDate ?? .distantPast
                let bDate = (try? b.resourceValues(forKeys: [.creationDateKey]))?
                    .creationDate ?? .distantPast
                return aDate > bDate
            }
            .first
    }

    private static func pruneOldBackups() {
        guard let base = backupBaseDirectory,
              fileManager.fileExists(atPath: base.path) else {
            return
        }

        let contents = (try? fileManager.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let backups = contents
            .filter { $0.lastPathComponent.hasPrefix("backup-") }
            .sorted { a, b in
                let aDate = (try? a.resourceValues(forKeys: [.creationDateKey]))?
                    .creationDate ?? .distantPast
                let bDate = (try? b.resourceValues(forKeys: [.creationDateKey]))?
                    .creationDate ?? .distantPast
                return aDate > bDate
            }

        guard backups.count > maxBackups else { return }
        for old in backups.dropFirst(maxBackups) {
            try? fileManager.removeItem(at: old)
        }
    }
}
