import Foundation
import SQLite3
import XCTest
@testable import Jin

final class MultiModelChatRemovalStoreMigrationTests: XCTestCase {
    func testMigrationCopiesActiveThreadConfigAndDropsInactiveThreadMessages() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jin-multi-model-removal-\(UUID().uuidString).store", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let database = try openDatabase(at: storeURL)
        defer { sqlite3_close(database) }

        try createLegacyTables(in: database)

        let activeThreadID = UUID()
        let inactiveThreadID = UUID()
        try execute(
            """
            INSERT INTO ZCONVERSATIONENTITY
                (Z_PK, ZPROVIDERID, ZMODELID, ZMODELCONFIGDATA, ZACTIVETHREADID)
            VALUES
                (1, 'legacy-provider', 'legacy-model', X'00', ?)
            """,
            in: database,
            uuidBinding: activeThreadID
        )
        try execute(
            """
            INSERT INTO ZCONVERSATIONMODELTHREADENTITY
                (Z_PK, ZCONVERSATION, ZID, ZPROVIDERID, ZMODELID, ZMODELCONFIGDATA,
                 ZISSELECTED, ZISPRIMARY, ZLASTACTIVATEDAT, ZDISPLAYORDER, ZCREATEDAT)
            VALUES
                (1, 1, ?, 'active-provider', 'active-model', X'0102', 1, 0, 20, 0, 10),
                (2, 1, ?, 'inactive-provider', 'inactive-model', X'0304', 0, 1, 30, 1, 11)
            """,
            in: database,
            uuidBindings: [activeThreadID, inactiveThreadID]
        )
        try execute(
            """
            INSERT INTO ZMESSAGEENTITY (Z_PK, ZCONVERSATION, ZCONTEXTTHREADID)
            VALUES
                (1, 1, ?),
                (2, 1, ?),
                (3, 1, NULL)
            """,
            in: database,
            uuidBindings: [activeThreadID, inactiveThreadID]
        )
        try execute(
            """
            INSERT INTO ZMESSAGEHIGHLIGHTENTITY (Z_PK, ZMESSAGE)
            VALUES
                (1, 1),
                (2, 2)
            """,
            in: database
        )

        try MultiModelChatRemovalStoreMigration.migrateStoreIfNeeded(at: storeURL)

        XCTAssertEqual(try stringValue("SELECT ZPROVIDERID FROM ZCONVERSATIONENTITY WHERE Z_PK = 1", in: database), "active-provider")
        XCTAssertEqual(try stringValue("SELECT ZMODELID FROM ZCONVERSATIONENTITY WHERE Z_PK = 1", in: database), "active-model")
        XCTAssertEqual(try stringValue("SELECT HEX(ZMODELCONFIGDATA) FROM ZCONVERSATIONENTITY WHERE Z_PK = 1", in: database), "0102")
        XCTAssertEqual(try intValue("SELECT COUNT(*) FROM ZMESSAGEENTITY", in: database), 2)
        XCTAssertEqual(try intValue("SELECT COUNT(*) FROM ZMESSAGEENTITY WHERE Z_PK = 1", in: database), 1)
        XCTAssertEqual(try intValue("SELECT COUNT(*) FROM ZMESSAGEENTITY WHERE Z_PK = 2", in: database), 0)
        XCTAssertEqual(try intValue("SELECT COUNT(*) FROM ZMESSAGEENTITY WHERE Z_PK = 3", in: database), 1)
        XCTAssertEqual(try intValue("SELECT COUNT(*) FROM ZMESSAGEHIGHLIGHTENTITY WHERE ZMESSAGE = 2", in: database), 0)
    }

    func testMigrationFallsBackToSelectedThreadWhenActiveThreadIsMissing() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jin-multi-model-removal-fallback-\(UUID().uuidString).store", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let database = try openDatabase(at: storeURL)
        defer { sqlite3_close(database) }

        try createLegacyTables(in: database)

        let missingThreadID = UUID()
        let selectedThreadID = UUID()
        let otherThreadID = UUID()
        try execute(
            """
            INSERT INTO ZCONVERSATIONENTITY
                (Z_PK, ZPROVIDERID, ZMODELID, ZMODELCONFIGDATA, ZACTIVETHREADID)
            VALUES
                (1, 'legacy-provider', 'legacy-model', X'00', ?)
            """,
            in: database,
            uuidBinding: missingThreadID
        )
        try execute(
            """
            INSERT INTO ZCONVERSATIONMODELTHREADENTITY
                (Z_PK, ZCONVERSATION, ZID, ZPROVIDERID, ZMODELID, ZMODELCONFIGDATA,
                 ZISSELECTED, ZISPRIMARY, ZLASTACTIVATEDAT, ZDISPLAYORDER, ZCREATEDAT)
            VALUES
                (1, 1, ?, 'selected-provider', 'selected-model', X'0506', 1, 0, 20, 1, 10),
                (2, 1, ?, 'other-provider', 'other-model', X'0708', 0, 1, 30, 0, 11)
            """,
            in: database,
            uuidBindings: [selectedThreadID, otherThreadID]
        )
        try execute(
            """
            INSERT INTO ZMESSAGEENTITY (Z_PK, ZCONVERSATION, ZCONTEXTTHREADID)
            VALUES
                (1, 1, ?),
                (2, 1, ?)
            """,
            in: database,
            uuidBindings: [selectedThreadID, otherThreadID]
        )

        try MultiModelChatRemovalStoreMigration.migrateStoreIfNeeded(at: storeURL)

        XCTAssertEqual(try stringValue("SELECT ZPROVIDERID FROM ZCONVERSATIONENTITY WHERE Z_PK = 1", in: database), "selected-provider")
        XCTAssertEqual(try stringValue("SELECT ZMODELID FROM ZCONVERSATIONENTITY WHERE Z_PK = 1", in: database), "selected-model")
        XCTAssertEqual(try intValue("SELECT COUNT(*) FROM ZMESSAGEENTITY WHERE Z_PK = 1", in: database), 1)
        XCTAssertEqual(try intValue("SELECT COUNT(*) FROM ZMESSAGEENTITY WHERE Z_PK = 2", in: database), 0)
    }

    private func createLegacyTables(in database: OpaquePointer) throws {
        try execute(
            """
            CREATE TABLE ZCONVERSATIONENTITY (
                Z_PK INTEGER PRIMARY KEY,
                ZPROVIDERID VARCHAR,
                ZMODELID VARCHAR,
                ZMODELCONFIGDATA BLOB,
                ZACTIVETHREADID BLOB
            );
            CREATE TABLE ZCONVERSATIONMODELTHREADENTITY (
                Z_PK INTEGER PRIMARY KEY,
                ZCONVERSATION INTEGER,
                ZID BLOB,
                ZPROVIDERID VARCHAR,
                ZMODELID VARCHAR,
                ZMODELCONFIGDATA BLOB,
                ZISSELECTED INTEGER,
                ZISPRIMARY INTEGER,
                ZLASTACTIVATEDAT TIMESTAMP,
                ZDISPLAYORDER INTEGER,
                ZCREATEDAT TIMESTAMP
            );
            CREATE TABLE ZMESSAGEENTITY (
                Z_PK INTEGER PRIMARY KEY,
                ZCONVERSATION INTEGER,
                ZCONTEXTTHREADID BLOB
            );
            CREATE TABLE ZMESSAGEHIGHLIGHTENTITY (
                Z_PK INTEGER PRIMARY KEY,
                ZMESSAGE INTEGER
            );
            """,
            in: database
        )
    }

    private func openDatabase(at url: URL) throws -> OpaquePointer {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            throw XCTSkip("Unable to open SQLite test database: \(message)")
        }
        return database
    }

    private func execute(
        _ sql: String,
        in database: OpaquePointer,
        uuidBinding: UUID
    ) throws {
        try execute(sql, in: database, uuidBindings: [uuidBinding])
    }

    private func execute(
        _ sql: String,
        in database: OpaquePointer,
        uuidBindings: [UUID] = []
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return try execute(sql, in: database)
        }
        defer { sqlite3_finalize(statement) }

        for (index, uuid) in uuidBindings.enumerated() {
            let data = data(for: uuid) as NSData
            sqlite3_bind_blob(
                statement,
                Int32(index + 1),
                data.bytes,
                Int32(data.length),
                unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            )
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteTestError.message(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func execute(_ sql: String, in database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw SQLiteTestError.message(message)
        }
    }

    private func stringValue(_ sql: String, in database: OpaquePointer) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteTestError.message(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: value)
    }

    private func intValue(_ sql: String, in database: OpaquePointer) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteTestError.message(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteTestError.message("No row returned")
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func data(for uuid: UUID) -> Data {
        var uuid = uuid.uuid
        return withUnsafeBytes(of: &uuid) { Data($0) }
    }

    private enum SQLiteTestError: Error {
        case message(String)
    }
}
