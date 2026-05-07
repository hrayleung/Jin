import Foundation

extension CodexAppServerAdapter {
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
