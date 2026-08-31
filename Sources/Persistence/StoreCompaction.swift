import Foundation

/// Reclaims the disk space that deleted chats leave behind.
///
/// SwiftData deleting a row only moves its pages onto SQLite's free list: the
/// store file never shrinks, and the deleted message text stays readable in
/// those pages until something happens to overwrite them. Only `VACUUM`
/// rebuilds the file, and it needs exclusive access — so a delete just *marks*
/// the store, and the next launch does the work before the container opens.
enum StoreCompaction {
    private static let pendingDefaultsKey = "storage.compactionPending"

    /// Don't rewrite a large file to win back a sliver. Both gates must pass.
    static let minimumReclaimableBytes: Int64 = 16 * 1024 * 1024
    static let minimumFreeFraction = 0.15

    static func markPending(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: pendingDefaultsKey)
    }

    static func isPending(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: pendingDefaultsKey)
    }

    static func clearPending(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: pendingDefaultsKey)
    }

    static func shouldCompact(stats: SQLiteSpaceStats?) -> Bool {
        guard let stats else { return false }
        return stats.reclaimableBytes >= minimumReclaimableBytes
            && stats.freeFraction >= minimumFreeFraction
    }

    /// Runs at launch, before SwiftData opens the store. Never throws: a
    /// failed compaction must not stop the app from starting.
    @discardableResult
    static func performPendingCompaction(
        storeURL: URL,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> Bool {
        guard isPending(defaults: defaults) else { return false }
        guard fileManager.fileExists(atPath: storeURL.path) else {
            clearPending(defaults: defaults)
            return false
        }

        let before = SQLiteDatabaseSupport.spaceStats(at: storeURL)
        guard shouldCompact(stats: before) else {
            // Nothing worth reclaiming — clear the flag so we don't re-measure
            // on every launch until the next delete.
            clearPending(defaults: defaults)
            return false
        }

        do {
            try SQLiteDatabaseSupport.vacuum(at: storeURL)
            clearPending(defaults: defaults)
            if let before {
                NSLog(
                    "Jin storage: compacted store, reclaimed ~%.1f MB of %.1f MB",
                    Double(before.reclaimableBytes) / 1_048_576,
                    Double(before.totalBytes) / 1_048_576
                )
            }
            return true
        } catch {
            // Leave the flag set so the next launch retries.
            NSLog("Jin storage warning: store compaction failed: %@", error.localizedDescription)
            return false
        }
    }
}
