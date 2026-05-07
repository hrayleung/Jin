import Collections
import Foundation

extension CodexAppServerAdapter {
    nonisolated static func codexToolActivityFromGenericItem(
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
}
