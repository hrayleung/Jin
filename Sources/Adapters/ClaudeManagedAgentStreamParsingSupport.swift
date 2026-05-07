import Foundation

enum ClaudeManagedAgentStreamParsingSupport {
    static func parseEvent(
        _ jsonLine: String,
        state: inout ClaudeManagedAgentsStreamState,
        tools: [ToolDefinition]
    ) throws -> ClaudeManagedAgentsParsedEvent {
        guard let object = try eventObject(from: jsonLine) else {
            return ClaudeManagedAgentsParsedEvent(events: [])
        }

        let type = eventType(from: object)

        var events: [StreamEvent] = []
        var pendingInteraction: CodexInteractionRequest?

        appendSessionStateChangeIfNeeded(from: object, state: &state, events: &events)

        switch type {
        case "agent.message":
            appendMessageEvents(from: object, state: &state, events: &events)

        case "agent.tool_use", "agent.mcp_tool_use":
            recordToolUse(from: object, state: &state, events: &events)

        case "agent.tool_result":
            completeToolResult(from: object, kind: .agent, state: &state, events: &events)

        case "agent.mcp_tool_result":
            completeToolResult(from: object, kind: .mcp, state: &state, events: &events)

        case "agent.custom_tool_use":
            appendCustomToolCallEvents(from: object, tools: tools, events: &events)

        case "span.model_request_end":
            accumulateUsage(fromModelRequestEnd: object, state: &state)

        case "session.status_idle":
            if let interaction = handleIdleEvent(from: object, state: &state, events: &events) {
                pendingInteraction = interaction
                break
            }

        case "session.error":
            throw providerError(from: object)

        case "session.status_terminated", "session.deleted":
            handleTerminatedEvent(state: &state, events: &events)

        default:
            // Ignore: session.status_running, session.status_rescheduled,
            // agent.thinking, agent.thread_context_compacted,
            // span.model_request_start, echoed user.* events.
            break
        }

        return ClaudeManagedAgentsParsedEvent(
            events: events,
            pendingInteraction: pendingInteraction
        )
    }
}

struct ClaudeManagedAgentsParsedEvent {
    let events: [StreamEvent]
    let pendingInteraction: CodexInteractionRequest?

    init(
        events: [StreamEvent],
        pendingInteraction: CodexInteractionRequest? = nil
    ) {
        self.events = events
        self.pendingInteraction = pendingInteraction
    }
}

struct ClaudeManagedAgentsStreamState {
    var sessionID: String
    var didEmitMessageStart = false
    var didEmitMessageEnd = false
    var didReachIdle = false
    var currentMessageID: String?
    var accumulatedUsage: Usage?
    var pendingApprovalInteractions: [CodexInteractionRequest] = []
    var pendingSearchActivities: [String: SearchActivity] = [:]
    var pendingGenericToolActivities: [String: CodexToolActivity] = [:]
}
