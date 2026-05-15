import Foundation

extension ClaudeManagedAgentsAdapter {
    func requiredConfiguredID(_ raw: String?, message: String) throws -> String {
        guard let value = normalizedTrimmedString(raw) else {
            throw LLMError.invalidRequest(message: message)
        }
        return value
    }

    func createSession(
        agentID: String,
        environmentID: String,
        modelID _: String,
        systemPrompt _: String?,
        tools _: [ToolDefinition]
    ) async throws -> ClaudeManagedAgentSessionState {
        let request = try NetworkRequestFactory.makeJSONRequest(
            url: managedAgentsBetaURL("/v1/sessions"),
            headers: anthropicHeaders(apiKey: apiKey),
            body: ClaudeManagedAgentRequestSupport.sessionCreationBody(
                agentID: agentID,
                environmentID: environmentID
            )
        )
        let (data, _) = try await networkManager.sendRequest(request)
        return try ClaudeManagedAgentRequestSupport.sessionState(from: data)
    }

    func buildTurnSubmissionRequest(
        sessionID: String,
        messages: [Message],
        controls: GenerationControls
    ) throws -> URLRequest {
        let eventBodies = try ClaudeManagedAgentRequestSupport.eventBodies(
            messages: messages,
            controls: controls
        )
        return try makeSessionEventsRequest(sessionID: sessionID, events: eventBodies)
    }

    func buildApprovalRequest(
        sessionID: String,
        interaction: ManagedAgentInteractionRequest,
        response: ManagedAgentInteractionResponse
    ) throws -> URLRequest {
        let event = try ClaudeManagedAgentRequestSupport.approvalEvent(
            from: interaction,
            response: response
        )
        return try makeSessionEventsRequest(sessionID: sessionID, events: [event])
    }

    func makeSessionEventsRequest(
        sessionID: String,
        events: [[String: Any]]
    ) throws -> URLRequest {
        try NetworkRequestFactory.makeJSONRequest(
            url: managedAgentsBetaURL("/v1/sessions/\(sessionID)/events"),
            headers: anthropicHeaders(apiKey: apiKey),
            body: ClaudeManagedAgentRequestSupport.sessionEventsBody(events: events)
        )
    }

    func submitEvent(_ request: URLRequest) async throws {
        _ = try await networkManager.sendRequest(request)
    }

    func buildStreamRequest(sessionID: String) throws -> URLRequest {
        // Per managed-agents-2026-04-01 docs: `GET /v1/sessions/{id}/events/stream`
        var headers = anthropicHeaders(apiKey: apiKey)
        headers["Accept"] = "text/event-stream"
        return NetworkRequestFactory.makeRequest(
            url: try managedAgentsBetaURL("/v1/sessions/\(sessionID)/events/stream"),
            method: "GET",
            headers: headers
        )
    }

}
