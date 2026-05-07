import Foundation

extension ClaudeManagedAgentStreamParsingSupport {
    static func makeCustomToolCall(
        from object: [String: JSONValue],
        tools: [ToolDefinition]
    ) -> ToolCall? {
        guard let eventID = customToolEventID(from: object),
              let toolName = namedToolName(from: object) else {
            return nil
        }

        guard tools.contains(where: { $0.name == toolName }) else { return nil }

        return ToolCall(
            id: eventID,
            name: toolName,
            arguments: toolArguments(from: object),
            providerContext: providerContext(
                from: object,
                underlyingToolUseID: customUnderlyingToolUseID(from: object)
            )
        )
    }

    static func appendCustomToolCallEvents(
        from object: [String: JSONValue],
        tools: [ToolDefinition],
        events: inout [StreamEvent]
    ) {
        guard let toolCall = makeCustomToolCall(from: object, tools: tools) else {
            return
        }

        events.append(.toolCallStart(toolCall))
        events.append(.toolCallEnd(toolCall))
    }

    static func customToolEventID(from object: [String: JSONValue]) -> String? {
        object.string(at: ["id"])
            ?? object.string(at: ["custom_tool_use_id"])
            ?? object.string(at: ["tool_use_id"])
    }

    static func customUnderlyingToolUseID(from object: [String: JSONValue]) -> String? {
        object.string(at: ["custom_tool_use_id"]) ?? object.string(at: ["tool_use_id"])
    }
}
