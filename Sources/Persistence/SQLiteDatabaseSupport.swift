import Foundation
import SQLite3

struct SQLiteIntegrityResult: Sendable {
    let passed: Bool
    let detail: String
}

/// Page accounting for the store file. Deleting rows only moves their pages
/// onto SQLite's free list — the file never shrinks and the old bytes stay
/// readable until something overwrites them. `VACUUM` is what actually
/// returns the space and drops the stale content.
struct SQLiteSpaceStats: Sendable, Equatable {
    let pageSize: Int64
    let pageCount: Int64
    let freeListCount: Int64

    var totalBytes: Int64 { pageCount * pageSize }
    var reclaimableBytes: Int64 { freeListCount * pageSize }

    var freeFraction: Double {
        guard pageCount > 0 else { return 0 }
        return Double(freeListCount) / Double(pageCount)
    }
}

enum SQLiteDatabaseSupport {
    static func onlineBackup(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: destinationDirectory.path) {
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        var sourceDB: OpaquePointer?
        var destinationDB: OpaquePointer?

        defer {
            sqlite3_close(sourceDB)
            sqlite3_close(destinationDB)
        }

        guard sqlite3_open_v2(sourceURL.path, &sourceDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw SQLiteError.openFailed(path: sourceURL.path, message: message(for: sourceDB))
        }
        guard sqlite3_open_v2(destinationURL.path, &destinationDB, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw SQLiteError.openFailed(path: destinationURL.path, message: message(for: destinationDB))
        }
        sqlite3_busy_timeout(sourceDB, 5_000)
        sqlite3_busy_timeout(destinationDB, 5_000)

        guard let backup = sqlite3_backup_init(destinationDB, "main", sourceDB, "main") else {
            throw SQLiteError.backupFailed(message: message(for: destinationDB))
        }
        defer { sqlite3_backup_finish(backup) }

        var busyRetryCount = 0
        while true {
            let result = sqlite3_backup_step(backup, 256)
            switch result {
            case SQLITE_DONE:
                return
            case SQLITE_OK:
                busyRetryCount = 0
            case SQLITE_BUSY, SQLITE_LOCKED:
                busyRetryCount += 1
                guard busyRetryCount <= 50 else {
                    throw SQLiteError.backupFailed(
                        message: backupMessage(result: result, source: sourceDB, destination: destinationDB)
                    )
                }
                sqlite3_sleep(100)
            default:
                throw SQLiteError.backupFailed(
                    message: backupMessage(result: result, source: sourceDB, destination: destinationDB)
                )
            }
        }
    }

    static func checkpointWAL(at databaseURL: URL) {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { return }
        sqlite3_exec(database, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
    }

    static func spaceStats(at databaseURL: URL) -> SQLiteSpaceStats? {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return nil
        }

        guard let pageSize = scalarValue(database, "PRAGMA page_size;"),
              let pageCount = scalarValue(database, "PRAGMA page_count;"),
              let freeListCount = scalarValue(database, "PRAGMA freelist_count;") else {
            return nil
        }

        return SQLiteSpaceStats(pageSize: pageSize, pageCount: pageCount, freeListCount: freeListCount)
    }

    /// Rewrites the database, returning free pages to the filesystem.
    ///
    /// Must run with no other connection attached: SQLite needs a write lock
    /// for the whole rebuild, so this is only safe before SwiftData opens its
    /// container (see `AppSnapshotManager.evaluateCurrentStoreForStartup`).
    static func vacuum(at databaseURL: URL) throws {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }

        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw SQLiteError.openFailed(path: databaseURL.path, message: message(for: database))
        }
        sqlite3_busy_timeout(database, 10_000)

        // Fold the WAL back into the main file first, otherwise VACUUM has to
        // contend with it and can leave the reclaimed pages in the WAL.
        sqlite3_exec(database, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)

        guard sqlite3_exec(database, "VACUUM;", nil, nil, nil) == SQLITE_OK else {
            throw SQLiteError.vacuumFailed(message: message(for: database))
        }
        sqlite3_exec(database, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
    }

    private static func scalarValue(_ database: OpaquePointer?, _ sql: String) -> Int64? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return sqlite3_column_int64(statement, 0)
    }

    static func quickCheck(at databaseURL: URL) -> SQLiteIntegrityResult {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }

        if sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            sqlite3_close(database)
            database = nil
            guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
                return SQLiteIntegrityResult(passed: false, detail: message(for: database))
            }
        }
        sqlite3_busy_timeout(database, 5_000)

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, "PRAGMA quick_check(1);", -1, &statement, nil) == SQLITE_OK else {
            return SQLiteIntegrityResult(passed: false, detail: message(for: database))
        }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else {
            return SQLiteIntegrityResult(passed: false, detail: "SQLite quick_check returned no result.")
        }

        let detail = String(cString: text)
        return SQLiteIntegrityResult(
            passed: detail.caseInsensitiveCompare("ok") == .orderedSame,
            detail: detail
        )
    }

    static func removeStoreArtifacts(at storeURL: URL, fileManager: FileManager = .default) {
        let parentDirectory = storeURL.deletingLastPathComponent()
        let urls = [
            storeURL,
            parentDirectory.appendingPathComponent("\(storeURL.lastPathComponent)-shm", isDirectory: false),
            parentDirectory.appendingPathComponent("\(storeURL.lastPathComponent)-wal", isDirectory: false)
        ]

        for url in urls {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func message(for database: OpaquePointer?) -> String {
        guard let message = sqlite3_errmsg(database) else { return "Unknown SQLite error." }
        return String(cString: message)
    }

    private static func backupMessage(
        result: Int32,
        source: OpaquePointer?,
        destination: OpaquePointer?
    ) -> String {
        var parts = [
            "SQLite result \(result) (\(String(cString: sqlite3_errstr(result))))"
        ]
        let sourceMessage = message(for: source)
        if sourceMessage != "not an error" {
            parts.append("source: \(sourceMessage)")
        }
        let destinationMessage = message(for: destination)
        if destinationMessage != "not an error" {
            parts.append("destination: \(destinationMessage)")
        }
        return parts.joined(separator: "; ")
    }
}

enum SQLiteError: LocalizedError {
    case openFailed(path: String, message: String)
    case backupFailed(message: String)
    case vacuumFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let path, let message):
            return "Failed to open SQLite database at \(path): \(message)"
        case .backupFailed(let message):
            return "SQLite online backup failed: \(message)"
        case .vacuumFailed(let message):
            return "SQLite VACUUM failed: \(message)"
        }
    }
}
