import XCTest
import SQLite3
@testable import Jin

final class SQLiteDatabaseSupportTests: XCTestCase {
    func testOnlineBackupProducesHealthyCopy() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let sourceURL = temporaryDirectory.appendingPathComponent("source.sqlite")
        let backupURL = temporaryDirectory.appendingPathComponent("backup.sqlite")

        try createSampleDatabase(at: sourceURL)
        try SQLiteDatabaseSupport.onlineBackup(from: sourceURL, to: backupURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertEqual(readRowCount(from: backupURL), 2)
    }

    private func createSampleDatabase(at url: URL) throws {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }

        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "PRAGMA journal_mode=WAL;", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE items(id INTEGER PRIMARY KEY, value TEXT);", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "INSERT INTO items(value) VALUES ('one'), ('two');", nil, nil, nil), SQLITE_OK)
    }

    private func readRowCount(from url: URL) -> Int {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open(url.path, &database) == SQLITE_OK else { return -1 }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM items;", -1, &statement, nil) == SQLITE_OK else {
            return -1
        }
        guard sqlite3_step(statement) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int(statement, 0))
    }
}
