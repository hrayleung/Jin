import XCTest
@testable import Jin

final class DataSettingsSupportTests: XCTestCase {
    func testTotalBytesSumsSnapshotByteCounts() {
        let snapshots = [
            StorageCategorySnapshot(category: .attachments, byteCount: 120, fileCount: 2, url: nil),
            StorageCategorySnapshot(category: .networkLogs, byteCount: 80, fileCount: 1, url: nil),
            StorageCategorySnapshot(category: .speechModels, byteCount: 0, fileCount: 0, url: nil)
        ]

        XCTAssertEqual(DataSettingsSupport.totalBytes(in: snapshots), 200)
        XCTAssertEqual(DataSettingsSupport.totalBytes(in: []), 0)
    }

    func testClearConfirmationTitleUsesCategoryWhenAvailable() {
        XCTAssertEqual(
            DataSettingsSupport.clearConfirmationTitle(category: .attachments),
            "Clear Attachments?"
        )
        XCTAssertEqual(
            DataSettingsSupport.clearConfirmationTitle(category: nil),
            "Clear Data?"
        )
    }

    func testClearConfirmationMessagesMatchStorageCategories() {
        XCTAssertEqual(
            DataSettingsSupport.clearConfirmationMessage(for: .attachments, byteCount: 1024),
            "This will delete all attachment files (1 KB). Chat messages will remain but embedded media will no longer display."
        )
        XCTAssertEqual(
            DataSettingsSupport.clearConfirmationMessage(for: .networkLogs, byteCount: 0),
            "This will delete all network debug trace files (0 bytes)."
        )
        XCTAssertEqual(
            DataSettingsSupport.clearConfirmationMessage(for: .chatDiagnostics, byteCount: 0),
            "This will delete all chat diagnostic timing logs (0 bytes)."
        )
        XCTAssertEqual(
            DataSettingsSupport.clearConfirmationMessage(for: .mcpData, byteCount: 0),
            "This will delete all MCP server isolation directories (0 bytes). They will be recreated as needed."
        )
        XCTAssertEqual(
            DataSettingsSupport.clearConfirmationMessage(for: .speechModels, byteCount: 0),
            "This will delete all downloaded on-device speech models (0 bytes). They will need to be re-downloaded to use again."
        )
        XCTAssertEqual(
            DataSettingsSupport.clearConfirmationMessage(for: .database, byteCount: 0),
            ""
        )
    }

    func testDeleteAllChatsConfirmationPluralizesChatCount() {
        XCTAssertEqual(
            DataSettingsSupport.deleteAllChatsConfirmationMessage(chatCount: 1),
            "This will permanently delete all 1 chat across all assistants. This cannot be undone."
        )
        XCTAssertEqual(
            DataSettingsSupport.deleteAllChatsConfirmationMessage(chatCount: 2),
            "This will permanently delete all 2 chats across all assistants. This cannot be undone."
        )
        XCTAssertEqual(
            DataSettingsSupport.deleteAllChatsConfirmationMessage(chatCount: 0),
            "This will permanently delete all 0 chats across all assistants. This cannot be undone."
        )
    }

    func testRecoveryPackFilenameUsesPOSIXDateFormat() {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = timeZone
        components.year = 2026
        components.month = 9
        components.day = 9
        let date = components.date!

        XCTAssertEqual(
            DataSettingsSupport.recoveryPackFilename(for: date, timeZone: timeZone),
            "Jin-2026-09-09.jinbackup"
        )
    }

    func testRecoveryPackStatusMessages() {
        XCTAssertEqual(DataSettingsSupport.exportStartedMessage, "Exporting recovery pack…")
        XCTAssertEqual(
            DataSettingsSupport.exportSuccessMessage(fileName: "Jin-2026-05-05.jinbackup"),
            "Exported recovery pack to Jin-2026-05-05.jinbackup."
        )
        XCTAssertEqual(
            DataSettingsSupport.exportFailureMessage(errorDescription: "No permission"),
            "Export failed: No permission"
        )
        XCTAssertEqual(DataSettingsSupport.importStartedMessage, "Validating and queuing recovery pack…")
        XCTAssertEqual(
            DataSettingsSupport.importSuccessMessage,
            "Recovery pack queued. Jin will restart to apply it."
        )
        XCTAssertEqual(
            DataSettingsSupport.importFailureMessage(errorDescription: "Bad archive"),
            "Import failed: Bad archive"
        )
    }

    func testShellQuotedWrapsAndEscapesSingleQuotes() {
        XCTAssertEqual(DataSettingsSupport.shellQuoted("/Applications/Jin.app"), "'/Applications/Jin.app'")
        XCTAssertEqual(DataSettingsSupport.shellQuoted("/tmp/Jin Beta.app"), "'/tmp/Jin Beta.app'")
        XCTAssertEqual(DataSettingsSupport.shellQuoted("/tmp/Jin's.app"), "'/tmp/Jin'\\''s.app'")
        XCTAssertEqual(DataSettingsSupport.shellQuoted(""), "''")
    }
}
