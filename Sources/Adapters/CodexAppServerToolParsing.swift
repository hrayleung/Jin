import Collections
import Foundation

// MARK: - Codex Tool Activity Parsing

extension CodexAppServerAdapter {

    nonisolated static func codexToolActivityFromDynamicToolCall(
        item: [String: JSONValue],
        method: String,
        params: [String: JSONValue],
        fallbackTurnID: String?
    ) -> CodexToolActivity? {
        guard let toolName = dynamicToolCallName(from: item) else {
            return nil
        }
        guard !isLikelyWebSearchTool(named: toolName) else {
            return nil
        }

        let id = codexToolActivityID(from: item, params: params, fallbackTurnID: fallbackTurnID, toolName: toolName)
        let status = codexToolActivityStatus(from: item, method: method)
        let arguments = codexToolActivityArguments(from: item)
        let output = codexToolActivityOutput(from: item)

        return CodexToolActivity(
            id: id,
            toolName: toolName,
            status: status,
            arguments: arguments,
            output: output
        )
    }

    nonisolated static func codexToolActivityFromCodexItem(
        item: [String: JSONValue],
        method: String,
        params: [String: JSONValue],
        fallbackTurnID: String?
    ) -> CodexToolActivity? {
        let itemType = item.string(at: ["type"]) ?? ""

        let nonToolTypes: Set<String> = [
            "webSearch",
            "agentMessage",
            "reasoning",
            "enteredReviewMode",
            "exitedReviewMode",
            "contextCompaction",
            "",
        ]
        if nonToolTypes.contains(itemType) {
            return nil
        }

        if itemType == "dynamicToolCall" {
            return codexToolActivityFromDynamicToolCall(
                item: item,
                method: method,
                params: params,
                fallbackTurnID: fallbackTurnID
            )
        }

        return codexToolActivityFromGenericItem(
            item: item,
            itemType: itemType,
            method: method,
            params: params,
            fallbackTurnID: fallbackTurnID
        )
    }

    // MARK: - Generic Item Tool Activity

    private nonisolated static func codexToolActivityFromGenericItem(
        item: [String: JSONValue],
        itemType: String,
        method: String,
        params: [String: JSONValue],
        fallbackTurnID: String?
    ) -> CodexToolActivity? {
        let id = codexToolActivityID(
            from: item,
            params: params,
            fallbackTurnID: fallbackTurnID,
            toolName: itemType
        )

        let toolName = genericItemToolName(item: item, itemType: itemType)
        let status = codexToolActivityStatus(from: item, method: method)
        let arguments = genericItemArguments(item: item, itemType: itemType)
        let output = genericItemOutput(item: item, itemType: itemType)

        return CodexToolActivity(
            id: id,
            toolName: toolName,
            status: status,
            arguments: arguments,
            output: output
        )
    }

    private nonisolated static func genericItemToolName(
        item: [String: JSONValue],
        itemType: String
    ) -> String {
        switch itemType {
        case "commandExecution":
            return trimmedValue(item.string(at: ["command"]))
                .map { cmd in
                    let first = cmd.components(separatedBy: .whitespaces).first ?? cmd
                    return first.count > 40 ? String(first.prefix(37)) + "..." : first
                }
                ?? "shell"
        case "fileChange":
            if let changes = item.array(at: ["changes"]),
               let firstPath = changes.first?.objectValue?.string(at: ["path"]) {
                let filename = (firstPath as NSString).lastPathComponent
                let kind = changes.first?.objectValue?.string(at: ["kind"]) ?? "edit"
                return "\(kind): \(filename)"
            }
            return "file change"
        case "mcpToolCall":
            if let server = trimmedValue(item.string(at: ["server"])),
               let tool = trimmedValue(item.string(at: ["tool"])) {
                return "\(server)/\(tool)"
            }
            return trimmedValue(item.string(at: ["tool"])) ?? "mcp tool"
        case "collabToolCall":
            return trimmedValue(item.string(at: ["tool"])) ?? "collab tool"
        case "imageView":
            return "image view"
        default:
            return trimmedValue(
                item.string(at: ["tool"])
                    ?? item.string(at: ["name"])
                    ?? item.string(at: ["tool", "name"])
            ) ?? itemType
        }
    }

    private nonisolated static func genericItemArguments(
        item: [String: JSONValue],
        itemType: String
    ) -> [String: AnyCodable] {
        var arguments: [String: AnyCodable] = [:]

        switch itemType {
        case "commandExecution":
            if let command = trimmedValue(item.string(at: ["command"])) {
                arguments["command"] = AnyCodable(command)
            }
            if let cwd = trimmedValue(item.string(at: ["cwd"])) {
                arguments["cwd"] = AnyCodable(cwd)
            }
            if let exitCode = item.int(at: ["exitCode"]) {
                arguments["exitCode"] = AnyCodable(exitCode)
            }

        case "fileChange":
            if let changes = item.array(at: ["changes"]) {
                var paths = OrderedSet<String>()
                for change in changes {
                    if let obj = change.objectValue,
                       let path = trimmedValue(obj.string(at: ["path"])) {
                        paths.append(path)
                    }
                }
                if !paths.isEmpty {
                    arguments["paths"] = AnyCodable(Array(paths))
                }
            }

        case "mcpToolCall":
            if let server = trimmedValue(item.string(at: ["server"])) {
                arguments["server"] = AnyCodable(server)
            }
            if let tool = trimmedValue(item.string(at: ["tool"])) {
                arguments["tool"] = AnyCodable(tool)
            }
            if let argsObj = item.object(at: ["arguments"]) {
                for (key, value) in argsObj {
                    arguments[key] = AnyCodable(jsonValueToAny(value))
                }
            }

        case "collabToolCall":
            if let tool = trimmedValue(item.string(at: ["tool"])) {
                arguments["tool"] = AnyCodable(tool)
            }
            if let prompt = trimmedValue(item.string(at: ["prompt"])) {
                arguments["prompt"] = AnyCodable(prompt)
            }

        case "imageView":
            if let path = trimmedValue(item.string(at: ["path"])) {
                arguments["path"] = AnyCodable(path)
            }

        default:
            if let argsObj = item.object(at: ["arguments"]) {
                for (key, value) in argsObj {
                    arguments[key] = AnyCodable(jsonValueToAny(value))
                }
            } else if let inputObj = item.object(at: ["input"]) {
                for (key, value) in inputObj {
                    arguments[key] = AnyCodable(jsonValueToAny(value))
                }
            }
            for key in ["command", "path", "file", "tool", "query"] {
                if arguments[key] == nil, let value = item.string(at: [key]) {
                    arguments[key] = AnyCodable(value)
                }
            }
        }

        return arguments
    }

    private nonisolated static func genericItemOutput(
        item: [String: JSONValue],
        itemType: String
    ) -> String? {
        switch itemType {
        case "commandExecution":
            return trimmedValue(item.string(at: ["aggregatedOutput"]))
                ?? trimmedValue(item.string(at: ["output"]))
        case "fileChange":
            return nil
        case "mcpToolCall":
            return trimmedValue(item.string(at: ["result"]))
                ?? trimmedValue(item.string(at: ["error"]))
        default:
            return codexToolActivityOutput(from: item)
        }
    }

    // MARK: - Shared Tool Activity Helpers

    nonisolated static func codexToolActivityID(
        from item: [String: JSONValue],
        params: [String: JSONValue],
        fallbackTurnID: String?,
        toolName: String
    ) -> String {
        if let explicitID = trimmedValue(
            item.string(at: ["id"])
                ?? item.string(at: ["callId"])
                ?? item.string(at: ["toolCallId"])
                ?? params.string(at: ["itemId"])
        ) {
            return explicitID
        }

        let turnID = trimmedValue(
            params.string(at: ["turnId"])
                ?? params.string(at: ["turn", "id"])
                ?? fallbackTurnID
        ) ?? "unknown_turn"

        var fallbackID = "codex_tool_\(turnID)_\(toolName.lowercased())"
        if let suffix = toolActivityFallbackSuffix(from: item, params: params) {
            fallbackID += "_\(suffix)"
        }
        return fallbackID
    }

    nonisolated static func codexToolActivityStatus(
        from item: [String: JSONValue],
        method: String
    ) -> CodexToolActivityStatus {
        if method == "item/completed" || method.hasSuffix("/completed") {
            return .completed
        }
        if method.hasSuffix("/failed") {
            return .failed
        }
        if method.hasSuffix("/started") || method == "item/started" {
            return .running
        }
        if method.hasSuffix("/outputDelta") || method.hasSuffix("/requestApproval") {
            return .running
        }

        if let rawStatus = trimmedValue(item.string(at: ["status"]) ?? item.string(at: ["state"])) {
            let normalized = rawStatus
                .replacingOccurrences(
                    of: "([a-z0-9])([A-Z])",
                    with: "$1_$2",
                    options: .regularExpression
                )
                .lowercased()
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
            if normalized == "in_progress" || normalized == "inprogress" {
                return .running
            }
            if normalized == "declined" {
                return .failed
            }
            return CodexToolActivityStatus(rawValue: normalized)
        }
        return .running
    }

    nonisolated static func codexToolActivityArguments(from item: [String: JSONValue]) -> [String: AnyCodable] {
        var arguments: [String: AnyCodable] = [:]

        if let argsObj = item.object(at: ["arguments"]) {
            for (key, value) in argsObj {
                arguments[key] = AnyCodable(jsonValueToAny(value))
            }
        } else if let inputObj = item.object(at: ["input"]) {
            for (key, value) in inputObj {
                arguments[key] = AnyCodable(jsonValueToAny(value))
            }
        }

        for key in ["command", "cmd", "path", "file", "filePath", "file_path", "query", "content"] {
            if arguments[key] == nil, let value = item.string(at: [key]) {
                arguments[key] = AnyCodable(value)
            }
        }

        return arguments
    }

    nonisolated static func codexToolActivityOutput(from item: [String: JSONValue]) -> String? {
        if let output = trimmedValue(item.string(at: ["output"])) {
            return output
        }
        if let result = trimmedValue(item.string(at: ["result"])) {
            return result
        }
        if let outputText = trimmedValue(item.string(at: ["output", "text"])) {
            return outputText
        }
        return nil
    }

    nonisolated static func toolActivityFallbackSuffix(
        from item: [String: JSONValue],
        params: [String: JSONValue]
    ) -> String? {
        if let sequence = item.int(at: ["sequenceNumber"]) ?? params.int(at: ["sequenceNumber"]) {
            return "seq\(sequence)"
        }
        if let outputIndex = item.int(at: ["outputIndex"]) ?? params.int(at: ["outputIndex"]) {
            return "out\(outputIndex)"
        }
        if let callIndex = item.int(at: ["callIndex"])
            ?? params.int(at: ["callIndex"])
            ?? item.int(at: ["index"])
            ?? params.int(at: ["index"]) {
            return "idx\(callIndex)"
        }
        return nil
    }

    nonisolated static func dynamicToolCallName(from item: [String: JSONValue]) -> String? {
        trimmedValue(
            item.string(at: ["name"])
                ?? item.string(at: ["toolName"])
                ?? item.string(at: ["tool"])
                ?? item.string(at: ["tool", "name"])
                ?? item.string(at: ["tool", "id"])
                ?? item.string(at: ["tool", "type"])
                ?? item.string(at: ["kind"])
        )
    }
}
