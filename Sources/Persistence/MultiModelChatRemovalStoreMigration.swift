import Foundation
import SQLite3

enum MultiModelChatRemovalStoreMigration {
    enum MigrationError: Error, LocalizedError {
        case openFailed(String)
        case sqlFailed(String)

        var errorDescription: String? {
            switch self {
            case .openFailed(let message):
                return "Failed to open legacy chat store: \(message)"
            case .sqlFailed(let message):
                return "Failed to migrate legacy multi-model chat data: \(message)"
            }
        }
    }

    static func migrateStoreIfNeeded(at storeURL: URL, fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: storeURL.path) else { return }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            storeURL.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            if let database {
                sqlite3_close(database)
            }
            throw MigrationError.openFailed(message)
        }
        defer { sqlite3_close(database) }

        try execute("PRAGMA busy_timeout = 5000", in: database)
        try execute("BEGIN IMMEDIATE TRANSACTION", in: database)
        do {
            try migrateConversationModelFields(in: database)
            try collapseInactiveThreadMessages(in: database)
            try execute("COMMIT TRANSACTION", in: database)
        } catch {
            try? execute("ROLLBACK TRANSACTION", in: database)
            throw error
        }
    }

    private static func migrateConversationModelFields(in database: OpaquePointer) throws {
        guard try tableExists("ZCONVERSATIONENTITY", in: database),
              try tableExists("ZCONVERSATIONMODELTHREADENTITY", in: database),
              try columnExists("ZACTIVETHREADID", in: "ZCONVERSATIONENTITY", database: database) else {
            return
        }

        try execute(
            """
            UPDATE ZCONVERSATIONENTITY AS conversation
            SET
                ZPROVIDERID = (
                    SELECT thread.ZPROVIDERID
                    FROM (
                        SELECT
                            ZPROVIDERID,
                            ZISSELECTED,
                            ZISPRIMARY,
                            ZLASTACTIVATEDAT,
                            ZDISPLAYORDER,
                            ZCREATEDAT,
                            Z_PK,
                            CASE
                                WHEN conversation.ZACTIVETHREADID IS NOT NULL
                                     AND ZID = conversation.ZACTIVETHREADID THEN 0
                                ELSE 1
                            END AS ZACTIVERANK
                        FROM ZCONVERSATIONMODELTHREADENTITY
                        WHERE ZCONVERSATION = conversation.Z_PK
                    ) AS thread
                    ORDER BY
                        thread.ZACTIVERANK ASC,
                        thread.ZISSELECTED DESC,
                        thread.ZISPRIMARY DESC,
                        thread.ZLASTACTIVATEDAT DESC,
                        thread.ZDISPLAYORDER ASC,
                        thread.ZCREATEDAT ASC,
                        thread.Z_PK ASC
                    LIMIT 1
                ),
                ZMODELID = (
                    SELECT thread.ZMODELID
                    FROM (
                        SELECT
                            ZMODELID,
                            ZISSELECTED,
                            ZISPRIMARY,
                            ZLASTACTIVATEDAT,
                            ZDISPLAYORDER,
                            ZCREATEDAT,
                            Z_PK,
                            CASE
                                WHEN conversation.ZACTIVETHREADID IS NOT NULL
                                     AND ZID = conversation.ZACTIVETHREADID THEN 0
                                ELSE 1
                            END AS ZACTIVERANK
                        FROM ZCONVERSATIONMODELTHREADENTITY
                        WHERE ZCONVERSATION = conversation.Z_PK
                    ) AS thread
                    ORDER BY
                        thread.ZACTIVERANK ASC,
                        thread.ZISSELECTED DESC,
                        thread.ZISPRIMARY DESC,
                        thread.ZLASTACTIVATEDAT DESC,
                        thread.ZDISPLAYORDER ASC,
                        thread.ZCREATEDAT ASC,
                        thread.Z_PK ASC
                    LIMIT 1
                ),
                ZMODELCONFIGDATA = (
                    SELECT thread.ZMODELCONFIGDATA
                    FROM (
                        SELECT
                            ZMODELCONFIGDATA,
                            ZISSELECTED,
                            ZISPRIMARY,
                            ZLASTACTIVATEDAT,
                            ZDISPLAYORDER,
                            ZCREATEDAT,
                            Z_PK,
                            CASE
                                WHEN conversation.ZACTIVETHREADID IS NOT NULL
                                     AND ZID = conversation.ZACTIVETHREADID THEN 0
                                ELSE 1
                            END AS ZACTIVERANK
                        FROM ZCONVERSATIONMODELTHREADENTITY
                        WHERE ZCONVERSATION = conversation.Z_PK
                    ) AS thread
                    ORDER BY
                        thread.ZACTIVERANK ASC,
                        thread.ZISSELECTED DESC,
                        thread.ZISPRIMARY DESC,
                        thread.ZLASTACTIVATEDAT DESC,
                        thread.ZDISPLAYORDER ASC,
                        thread.ZCREATEDAT ASC,
                        thread.Z_PK ASC
                    LIMIT 1
                )
            WHERE EXISTS (
                SELECT 1
                FROM ZCONVERSATIONMODELTHREADENTITY
                WHERE ZCONVERSATION = conversation.Z_PK
            )
            """,
            in: database
        )
    }

    private static func collapseInactiveThreadMessages(in database: OpaquePointer) throws {
        guard try tableExists("ZCONVERSATIONENTITY", in: database),
              try tableExists("ZCONVERSATIONMODELTHREADENTITY", in: database),
              try tableExists("ZMESSAGEENTITY", in: database),
              try columnExists("ZACTIVETHREADID", in: "ZCONVERSATIONENTITY", database: database),
              try columnExists("ZCONTEXTTHREADID", in: "ZMESSAGEENTITY", database: database) else {
            return
        }

        if try tableExists("ZMESSAGEHIGHLIGHTENTITY", in: database),
           try columnExists("ZMESSAGE", in: "ZMESSAGEHIGHLIGHTENTITY", database: database) {
            try execute(
                """
                DELETE FROM ZMESSAGEHIGHLIGHTENTITY
                WHERE ZMESSAGE IN (
                    SELECT message.Z_PK
                    FROM ZMESSAGEENTITY message
                    WHERE message.ZCONTEXTTHREADID IS NOT NULL
                      AND message.ZCONTEXTTHREADID != (
                          SELECT chosen.ZID
                          FROM ZCONVERSATIONMODELTHREADENTITY chosen
                          JOIN ZCONVERSATIONENTITY conversation
                            ON conversation.Z_PK = message.ZCONVERSATION
                           AND chosen.ZCONVERSATION = conversation.Z_PK
                          ORDER BY
                              CASE
                                  WHEN conversation.ZACTIVETHREADID IS NOT NULL
                                       AND chosen.ZID = conversation.ZACTIVETHREADID THEN 0
                                  ELSE 1
                              END,
                              chosen.ZISSELECTED DESC,
                              chosen.ZISPRIMARY DESC,
                              chosen.ZLASTACTIVATEDAT DESC,
                              chosen.ZDISPLAYORDER ASC,
                              chosen.ZCREATEDAT ASC,
                              chosen.Z_PK ASC
                          LIMIT 1
                      )
                )
                """,
                in: database
            )
        }

        try execute(
            """
            DELETE FROM ZMESSAGEENTITY
            WHERE ZCONTEXTTHREADID IS NOT NULL
              AND ZCONTEXTTHREADID != (
                  SELECT chosen.ZID
                  FROM ZCONVERSATIONMODELTHREADENTITY chosen
                  JOIN ZCONVERSATIONENTITY conversation
                    ON conversation.Z_PK = ZMESSAGEENTITY.ZCONVERSATION
                   AND chosen.ZCONVERSATION = conversation.Z_PK
                  ORDER BY
                      CASE
                          WHEN conversation.ZACTIVETHREADID IS NOT NULL
                               AND chosen.ZID = conversation.ZACTIVETHREADID THEN 0
                          ELSE 1
                      END,
                      chosen.ZISSELECTED DESC,
                      chosen.ZISPRIMARY DESC,
                      chosen.ZLASTACTIVATEDAT DESC,
                      chosen.ZDISPLAYORDER ASC,
                      chosen.ZCREATEDAT ASC,
                      chosen.Z_PK ASC
                  LIMIT 1
              )
            """,
            in: database
        )
    }

    private static func tableExists(_ tableName: String, in database: OpaquePointer) throws -> Bool {
        try intValue(
            for: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
            binding: tableName,
            in: database
        ) > 0
    }

    private static func columnExists(
        _ columnName: String,
        in tableName: String,
        database: OpaquePointer
    ) throws -> Bool {
        var statement: OpaquePointer?
        let sql = "PRAGMA table_info(\(tableName))"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MigrationError.sqlFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawName = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: rawName).caseInsensitiveCompare(columnName) == .orderedSame {
                return true
            }
        }

        return false
    }

    private static func intValue(
        for sql: String,
        binding: String,
        in database: OpaquePointer
    ) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MigrationError.sqlFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, binding, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw MigrationError.sqlFailed(String(cString: sqlite3_errmsg(database)))
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    private static func execute(_ sql: String, in database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw MigrationError.sqlFailed(message)
        }
    }
}
