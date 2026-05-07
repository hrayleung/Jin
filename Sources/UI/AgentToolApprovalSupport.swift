import Foundation

enum AgentToolApprovalSupport {
    private static let previewLimit = 2048

    static func needsApproval(
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

        let raw = AgentToolArgumentParser.rawArguments(arguments)

        switch functionName {
        case AgentToolNames.shellExecute:
            guard let command = AgentToolArgumentParser.stringArg(raw, keys: AgentToolArgumentKeys.command) else {
                return true
            }
            return !AgentCommandAllowlist.isCommandAllowed(
                command,
                allowedPrefixes: controls.allowedCommandPrefixes
            )
        case AgentToolNames.fileRead:
            return !controls.autoApproveFileReads
        case AgentToolNames.fileWrite, AgentToolNames.fileEdit:
            return true
        case AgentToolNames.globSearch, AgentToolNames.grepSearch:
            return false
        default:
            return true
        }
    }

    static func makeRequest(
        functionName: String,
        arguments: [String: AnyCodable],
        controls: AgentModeControls
    ) -> AgentApprovalRequest {
        let raw = AgentToolArgumentParser.rawArguments(arguments)

        switch functionName {
        case AgentToolNames.shellExecute:
            let command = AgentToolArgumentParser.stringArg(raw, keys: AgentToolArgumentKeys.command) ?? "(unknown)"
            let cwd = AgentToolArgumentParser.stringArg(raw, keys: AgentToolArgumentKeys.workingDirectory)
                ?? controls.workingDirectory
            return AgentApprovalRequest(kind: .shellCommand(command: command, cwd: cwd))

        case AgentToolNames.fileWrite:
            let path = AgentToolArgumentParser.stringArg(raw, keys: AgentToolArgumentKeys.filePath)
                ?? "(unknown)"
            let content = AgentToolArgumentParser.rawStringArg(raw, keys: AgentToolArgumentKeys.fileContent) ?? ""
            return AgentApprovalRequest(kind: .fileWrite(path: path, preview: preview(content)))

        case AgentToolNames.fileEdit:
            let path = AgentToolArgumentParser.stringArg(raw, keys: AgentToolArgumentKeys.filePath)
                ?? "(unknown)"
            let oldText = AgentToolArgumentParser.rawStringArg(raw, keys: AgentToolArgumentKeys.fileEditOldText) ?? ""
            let newText = AgentToolArgumentParser.rawStringArg(raw, keys: AgentToolArgumentKeys.fileEditNewText) ?? ""
            return AgentApprovalRequest(kind: .fileEdit(
                path: path,
                oldText: preview(oldText),
                newText: preview(newText)
            ))

        default:
            return AgentApprovalRequest(kind: .shellCommand(command: "(unknown)", cwd: nil))
        }
    }

    static func sessionKey(
        functionName: String,
        arguments: [String: AnyCodable],
        controls: AgentModeControls
    ) -> String? {
        let raw = AgentToolArgumentParser.rawArguments(arguments)

        switch functionName {
        case AgentToolNames.shellExecute:
            guard let command = AgentToolArgumentParser.normalizedStringArg(raw, keys: AgentToolArgumentKeys.command) else {
                return nil
            }
            let cwd = AgentToolArgumentParser.normalizedStringArg(raw, keys: AgentToolArgumentKeys.workingDirectory)
                ?? controls.workingDirectory
                ?? ""
            return "shell:\(cwd):\(command)"

        case AgentToolNames.fileRead:
            guard let path = AgentToolArgumentParser.normalizedStringArg(raw, keys: AgentToolArgumentKeys.filePath) else {
                return nil
            }
            let offset = AgentToolArgumentParser.normalizedStringArg(raw, keys: AgentToolArgumentKeys.fileReadOffset) ?? ""
            let limit = AgentToolArgumentParser.normalizedStringArg(raw, keys: AgentToolArgumentKeys.fileReadLimit) ?? ""
            return "file_read:\(path):\(offset):\(limit)"

        case AgentToolNames.fileWrite:
            guard let path = AgentToolArgumentParser.normalizedStringArg(raw, keys: AgentToolArgumentKeys.filePath),
                  let content = AgentToolArgumentParser.normalizedStringArg(raw, keys: AgentToolArgumentKeys.fileContent) else {
                return nil
            }
            return "file_write:\(path):\(SHA256HexDigest.string(content))"

        case AgentToolNames.fileEdit:
            guard let path = AgentToolArgumentParser.normalizedStringArg(raw, keys: AgentToolArgumentKeys.filePath),
                  let oldText = AgentToolArgumentParser.normalizedStringArg(raw, keys: AgentToolArgumentKeys.fileEditOldText),
                  let newText = AgentToolArgumentParser.normalizedStringArg(raw, keys: AgentToolArgumentKeys.fileEditNewText) else {
                return nil
            }
            return "file_edit:\(path):\(SHA256HexDigest.string(oldText)):\(SHA256HexDigest.string(newText))"

        default:
            return nil
        }
    }

    private static func preview(_ value: String) -> String {
        String(value.prefix(previewLimit))
    }

}
