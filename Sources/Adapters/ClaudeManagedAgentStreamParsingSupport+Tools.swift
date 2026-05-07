import Foundation

extension ClaudeManagedAgentStreamParsingSupport {
    static func toolEventID(from object: [String: JSONValue]) -> String? {
        object.string(at: ["id"])
            ?? object.string(at: ["tool_use_id"])
            ?? object.string(at: ["mcp_tool_use_id"])
    }

    static func namedToolName(from object: [String: JSONValue]) -> String? {
        object.string(at: ["tool_name"]) ?? object.string(at: ["name"])
    }

    static func toolName(from object: [String: JSONValue]) -> String {
        namedToolName(from: object) ?? "tool"
    }

    static func toolArguments(from object: [String: JSONValue]) -> [String: AnyCodable] {
        let argumentsObject = object.object(at: ["input"])
            ?? object.object(at: ["arguments"])
            ?? [:]

        return argumentsObject.mapValues { AnyCodable($0.rawJSONValue) }
    }

    static func providerContext(
        from object: [String: JSONValue],
        underlyingToolUseID: String?
    ) -> [String: String] {
        var context: [String: String] = [:]
        if let sessionThreadID = object.string(at: ["session_thread_id"]) {
            context[ClaudeManagedAgentProviderContextKey.sessionThreadID] = sessionThreadID
        }
        if let underlyingToolUseID {
            context[ClaudeManagedAgentProviderContextKey.underlyingToolUseID] = underlyingToolUseID
        }
        return context
    }
}

private extension JSONValue {
    var rawJSONValue: Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return Int(value)
            }
            return value
        case .string(let value):
            return value
        case .array(let values):
            return values.map(\.rawJSONValue)
        case .object(let values):
            return values.mapValues(\.rawJSONValue)
        }
    }
}
