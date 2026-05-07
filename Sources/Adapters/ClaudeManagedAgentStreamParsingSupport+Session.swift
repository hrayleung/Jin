import Foundation

extension ClaudeManagedAgentStreamParsingSupport {
    static func appendSessionStateChangeIfNeeded(
        from object: [String: JSONValue],
        state: inout ClaudeManagedAgentsStreamState,
        events: inout [StreamEvent]
    ) {
        guard let sessionID = sessionID(from: object),
              sessionID != state.sessionID else {
            return
        }

        state.sessionID = sessionID
        events.append(.claudeManagedSessionState(sessionState(sessionID: sessionID, object: object)))
    }

    static func handleIdleEvent(
        from object: [String: JSONValue],
        state: inout ClaudeManagedAgentsStreamState,
        events: inout [StreamEvent]
    ) -> CodexInteractionRequest? {
        let requiredActionEventIDs = extractRequiredActionEventIDs(from: object)
        state.didReachIdle = false

        if let interaction = dequeuePendingApprovalInteraction(
            matching: requiredActionEventIDs,
            state: &state
        ) {
            events.append(.codexInteractionRequest(interaction))
            return interaction
        }

        state.didReachIdle = true
        appendMessageEndIfNeeded(state: &state, events: &events)
        appendIdleSessionEvents(from: object, state: state, events: &events)
        return nil
    }

    static func dequeuePendingApprovalInteraction(
        matching eventIDs: [String],
        state: inout ClaudeManagedAgentsStreamState
    ) -> CodexInteractionRequest? {
        guard let nextApprovalIndex = state.pendingApprovalInteractions.firstIndex(where: { interaction in
            guard let itemID = interaction.itemID else { return false }
            return eventIDs.contains(itemID)
        }) else {
            return nil
        }

        return state.pendingApprovalInteractions.remove(at: nextApprovalIndex)
    }

    static func appendIdleSessionEvents(
        from object: [String: JSONValue],
        state: ClaudeManagedAgentsStreamState,
        events: inout [StreamEvent]
    ) {
        events.append(.claudeManagedSessionState(sessionState(sessionID: state.sessionID, object: object)))
        events.append(.claudeManagedCustomToolResults([]))
    }

    static func handleTerminatedEvent(
        state: inout ClaudeManagedAgentsStreamState,
        events: inout [StreamEvent]
    ) {
        state.didReachIdle = true
        appendMessageEndIfNeeded(state: &state, events: &events)
    }

    static func appendMessageEndIfNeeded(
        state: inout ClaudeManagedAgentsStreamState,
        events: inout [StreamEvent]
    ) {
        if !state.didEmitMessageEnd, state.didEmitMessageStart {
            state.didEmitMessageEnd = true
            events.append(.messageEnd(usage: state.accumulatedUsage))
        }
    }

    static func sessionID(from object: [String: JSONValue]) -> String? {
        object.string(at: ["session_id"]) ?? object.string(at: ["session", "id"])
    }

    static func sessionState(
        sessionID: String,
        object: [String: JSONValue]
    ) -> ClaudeManagedAgentSessionState {
        ClaudeManagedAgentSessionState(
            remoteSessionID: sessionID,
            remoteModelID: extractRemoteModelID(from: object)
        )
    }

    static func extractRemoteModelID(from object: [String: JSONValue]) -> String? {
        normalizedTrimmedString(
            object.string(at: ["model", "id"])
                ?? object.string(at: ["session", "model", "id"])
                ?? object.string(at: ["agent", "model", "id"])
                ?? object.string(at: ["session", "agent", "model", "id"])
                ?? object.string(at: ["model_id"])
                ?? object.string(at: ["session", "model_id"])
                ?? object.string(at: ["agent", "model_id"])
                ?? object.string(at: ["model"])
        )
    }

    static func extractRequiredActionEventIDs(from object: [String: JSONValue]) -> [String] {
        guard object.string(at: ["stop_reason", "type"]) == "requires_action" else {
            return []
        }
        guard let eventIDs = object.array(at: ["stop_reason", "event_ids"]) else {
            return []
        }
        return eventIDs.compactMap(\.stringValue)
    }
}
