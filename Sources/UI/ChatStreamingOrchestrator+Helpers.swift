import CryptoKit
import Foundation

extension ChatStreamingOrchestrator {

    // MARK: - Agent Approval Helpers

    static func agentToolNeedsApproval(
        functionName: String,
        arguments: [String: AnyCodable],
        controls: AgentModeControls,
        approvalKey: String?,
        approvalStore: AgentApprovalSessionStore
    ) async -> Bool {
        if controls.bypassPermissions { return false }
        if let approvalKey, await approvalStore.isApproved(key: approvalKey) {
            return false
        }

        let raw = arguments.mapValues { $0.value }

        switch functionName {
        case AgentToolHub.shellExecuteFunctionName:
            guard let command = raw["command"] as? String else { return true }
            return !AgentCommandAllowlist.isCommandAllowed(
                command,
                allowedPrefixes: controls.allowedCommandPrefixes
            )
        case AgentToolHub.fileReadFunctionName:
            return !controls.autoApproveFileReads
        case AgentToolHub.fileWriteFunctionName, AgentToolHub.fileEditFunctionName:
            return true
        case AgentToolHub.globSearchFunctionName, AgentToolHub.grepSearchFunctionName:
            return false
        default:
            return true
        }
    }

    static func makeAgentApprovalRequest(
        functionName: String,
        arguments: [String: AnyCodable],
        controls: AgentModeControls
    ) -> AgentApprovalRequest {
        let raw = arguments.mapValues { $0.value }

        switch functionName {
        case AgentToolHub.shellExecuteFunctionName:
            let command = raw["command"] as? String ?? "(unknown)"
            let cwd = (raw["working_directory"] as? String)
                ?? (raw["workingDirectory"] as? String)
                ?? (raw["cwd"] as? String)
                ?? controls.workingDirectory
            return AgentApprovalRequest(kind: .shellCommand(command: command, cwd: cwd))

        case AgentToolHub.fileWriteFunctionName:
            let path = raw["path"] as? String ?? "(unknown)"
            let content = raw["content"] as? String ?? ""
            let preview = String(content.prefix(2048))
            return AgentApprovalRequest(kind: .fileWrite(path: path, preview: preview))

        case AgentToolHub.fileEditFunctionName:
            let path = raw["path"] as? String ?? "(unknown)"
            let oldText = raw["old_text"] as? String ?? ""
            let newText = raw["new_text"] as? String ?? ""
            return AgentApprovalRequest(kind: .fileEdit(
                path: path,
                oldText: String(oldText.prefix(2048)),
                newText: String(newText.prefix(2048))
            ))

        default:
            return AgentApprovalRequest(kind: .shellCommand(command: "(unknown)", cwd: nil))
        }
    }

    // MARK: - Session Key Generation

    static func agentApprovalSessionKey(
        functionName: String,
        arguments: [String: AnyCodable],
        controls: AgentModeControls
    ) -> String? {
        let raw = arguments.mapValues { $0.value }

        switch functionName {
        case AgentToolHub.shellExecuteFunctionName:
            guard let command = normalizedStringValue(raw["command"] ?? raw["cmd"]) else { return nil }
            let cwd = normalizedStringValue(raw["working_directory"] ?? raw["workingDirectory"] ?? raw["cwd"])
                ?? controls.workingDirectory
                ?? ""
            return "shell:\(cwd):\(command)"

        case AgentToolHub.fileReadFunctionName:
            guard let path = normalizedStringValue(raw["path"] ?? raw["file"] ?? raw["file_path"] ?? raw["filePath"]) else { return nil }
            let offset = normalizedStringValue(raw["offset"] ?? raw["line_offset"] ?? raw["start_line"]) ?? ""
            let limit = normalizedStringValue(raw["limit"] ?? raw["line_count"] ?? raw["max_lines"]) ?? ""
            return "file_read:\(path):\(offset):\(limit)"

        case AgentToolHub.fileWriteFunctionName:
            guard let path = normalizedStringValue(raw["path"] ?? raw["file"] ?? raw["file_path"] ?? raw["filePath"]),
                  let content = normalizedStringValue(raw["content"] ?? raw["text"] ?? raw["data"]) else {
                return nil
            }
            return "file_write:\(path):\(sha256Hex(content))"

        case AgentToolHub.fileEditFunctionName:
            guard let path = normalizedStringValue(raw["path"] ?? raw["file"] ?? raw["file_path"] ?? raw["filePath"]),
                  let oldText = normalizedStringValue(raw["old_text"] ?? raw["oldText"] ?? raw["old_string"] ?? raw["search"]),
                  let newText = normalizedStringValue(raw["new_text"] ?? raw["newText"] ?? raw["new_string"] ?? raw["replace"]) else {
                return nil
            }
            return "file_edit:\(path):\(sha256Hex(oldText)):\(sha256Hex(newText))"

        default:
            return nil
        }
    }

    // MARK: - Hashing

    private static func normalizedStringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let int as Int:
            return String(int)
        case let double as Double:
            return String(Int(double))
        default:
            return nil
        }
    }

    private static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
