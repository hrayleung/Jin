import Foundation

enum DataSettingsSupport {
    static func totalBytes(in snapshots: [StorageCategorySnapshot]) -> Int64 {
        snapshots.reduce(0) { $0 + $1.byteCount }
    }

    static func clearConfirmationTitle(category: StorageCategory?) -> String {
        guard let category else {
            return "Clear Data?"
        }
        return "Clear \(category.label)?"
    }

    static func clearConfirmationMessage(for category: StorageCategory, byteCount: Int64) -> String {
        switch category {
        case .attachments:
            return "\(deleteAllMessage("attachment files", byteCount: byteCount)) Chat messages will remain but embedded media will no longer display."
        case .networkLogs:
            return deleteAllMessage("network debug trace files", byteCount: byteCount)
        case .chatDiagnostics:
            return deleteAllMessage("chat diagnostic timing logs", byteCount: byteCount)
        case .mcpData:
            return "\(deleteAllMessage("MCP server isolation directories", byteCount: byteCount)) They will be recreated as needed."
        case .database:
            return ""
        }
    }

    static func deleteAllChatsConfirmationMessage(chatCount: Int) -> String {
        "This will permanently delete all \(chatCount) \(chatNoun(for: chatCount)) across all assistants. This cannot be undone."
    }

    static func recoveryPackFilename(for date: Date, timeZone: TimeZone = .current) -> String {
        "Jin-\(recoveryPackDateFormatter(timeZone: timeZone).string(from: date)).jinbackup"
    }

    static let exportStartedMessage = "Exporting recovery pack…"

    static func exportSuccessMessage(fileName: String) -> String {
        "Exported recovery pack to \(fileName)."
    }

    static func exportFailureMessage(errorDescription: String) -> String {
        "Export failed: \(errorDescription)"
    }

    static let importStartedMessage = "Validating and queuing recovery pack…"
    static let importSuccessMessage = "Recovery pack queued. Jin will restart to apply it."

    static func importFailureMessage(errorDescription: String) -> String {
        "Import failed: \(errorDescription)"
    }

    static func shellQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func recoveryPackDateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func deleteAllMessage(_ itemName: String, byteCount: Int64) -> String {
        let size = DataSettingsFormatting.formattedSize(byteCount)
        return "This will delete all \(itemName) (\(size))."
    }

    private static func chatNoun(for count: Int) -> String {
        count == 1 ? "chat" : "chats"
    }
}
