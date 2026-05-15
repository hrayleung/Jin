import Foundation

extension ClaudeManagedAgentStreamParsingSupport {
    static func recordToolUse(
        from object: [String: JSONValue],
        state: inout ClaudeManagedAgentsStreamState,
        events: inout [StreamEvent]
    ) {
        let eventID = toolEventID(from: object) ?? UUID().uuidString
        let toolName = toolName(from: object)

        if toolUseRequiresApproval(from: object) {
            guard let interaction = makeToolConfirmationInteraction(from: object, sessionID: state.sessionID) else {
                return
            }
            state.pendingApprovalInteractions.append(interaction)
        } else {
            recordAllowedToolUse(
                eventID: eventID,
                toolName: toolName,
                object: object,
                state: &state,
                events: &events
            )
        }
    }

    static func recordAllowedToolUse(
        eventID: String,
        toolName: String,
        object: [String: JSONValue],
        state: inout ClaudeManagedAgentsStreamState,
        events: inout [StreamEvent]
    ) {
        let arguments = toolArguments(from: object)
        if ToolSearchActivityFactory.isSearchToolName(toolName) {
            let activity = SearchActivity(
                id: eventID,
                type: toolName,
                status: .inProgress,
                arguments: arguments
            )
            state.pendingSearchActivities[eventID] = activity
            events.append(.searchActivity(activity))
        }
    }

    static func toolUseRequiresApproval(from object: [String: JSONValue]) -> Bool {
        // Per docs: values are "allow" | "ask" | "deny". When missing we
        // optimistically treat it as allowed for built-in tools that do not
        // surface permission metadata.
        object.string(at: ["evaluated_permission"]) == "ask"
    }

    static func makeToolConfirmationInteraction(
        from object: [String: JSONValue],
        sessionID: String
    ) -> ManagedAgentInteractionRequest? {
        guard let toolUseID = approvalToolUseID(from: object) else {
            return nil
        }

        let command = toolName(from: object)
        let cwd = object.string(at: ["cwd"]) ?? object.string(at: ["working_directory"])
        let reason = object.string(at: ["reason"]) ?? object.string(at: ["message"])
        let request = ManagedAgentCommandApprovalRequest(
            command: command,
            cwd: cwd,
            reason: reason,
            actionSummaries: []
        )

        return ManagedAgentInteractionRequest(
            method: "claude_managed_agents/tool_confirmation",
            threadID: sessionID,
            turnID: object.string(at: ["turn_id"]),
            itemID: toolUseID,
            kind: .commandApproval(request),
            providerContext: providerContext(from: object, underlyingToolUseID: object.string(at: ["tool_use_id"]))
        )
    }

    static func approvalToolUseID(from object: [String: JSONValue]) -> String? {
        object.string(at: ["id"]) ?? object.string(at: ["tool_use_id"])
    }
}
