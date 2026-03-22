import Foundation
import SQLite3

struct SQLiteIntegrityResult: Sendable {
    let passed: Bool
    let detail: String
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

        guard let backup = sqlite3_backup_init(destinationDB, "main", sourceDB, "main") else {
            throw SQLiteError.backupFailed(message: message(for: destinationDB))
        }
        defer { sqlite3_backup_finish(backup) }

        let result = sqlite3_backup_step(backup, -1)
        guard result == SQLITE_DONE else {
            throw SQLiteError.backupFailed(message: message(for: destinationDB))
        }
    }

    static func quickCheck(at databaseURL: URL) -> SQLiteIntegrityResult {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }

        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return SQLiteIntegrityResult(passed: false, detail: message(for: database))
        }

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
}

enum SQLiteError: LocalizedError {
    case openFailed(path: String, message: String)
    case backupFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let path, let message):
            return "Failed to open SQLite database at \(path): \(message)"
        case .backupFailed(let message):
            return "SQLite online backup failed: \(message)"
        }
    }
}
