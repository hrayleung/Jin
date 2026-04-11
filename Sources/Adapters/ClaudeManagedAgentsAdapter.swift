import Foundation

actor ClaudeManagedAgentsAdapter: LLMProviderAdapter {
    // Session API (`/v1/sessions/*`) — public managed-agents beta.
    private static let managedAgentsBeta = "managed-agents-2026-04-01"
    // Agent / environment catalog API (`/v1/agents`, `/v1/environments`) —
    // older `agent-api` beta. Incompatible with managed-agents; the server
    // rejects requests that include both values in a single header.
    private static let agentCatalogBeta = "agent-api-2026-03-01"

    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning, .promptCaching]

    private let apiKey: String
    private let networkManager: NetworkManager

    init(
        providerConfig: ProviderConfig,
        apiKey: String,
        networkManager: NetworkManager = NetworkManager()
    ) {
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager
    }

    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming _: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let agentID = try requiredConfiguredID(
            controls.claudeManagedAgentID,
            message: "Claude Managed Agents requires an Agent ID in the thread settings."
        )
        let environmentID = try requiredConfiguredID(
            controls.claudeManagedEnvironmentID,
            message: "Claude Managed Agents requires an Environment ID in the thread settings."
        )
        let existingSessionID = normalizedTrimmedString(controls.claudeManagedSessionID)

        let activeSessionID: String
        var startupEvents: [StreamEvent] = []

        if let existingSessionID {
            activeSessionID = existingSessionID
        } else {
            let createdSession = try await createSession(
                agentID: agentID,
                environmentID: environmentID,
                modelID: modelID,
                systemPrompt: systemPrompt(from: messages),
                tools: tools
            )
            activeSessionID = createdSession.remoteSessionID
            startupEvents.append(.claudeManagedSessionState(createdSession))
        }

        let initialRequest = try buildTurnSubmissionRequest(
            sessionID: activeSessionID,
            messages: messages,
            controls: controls
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for startupEvent in startupEvents {
                        continuation.yield(startupEvent)
                    }

                    var state = ClaudeManagedAgentsStreamState(sessionID: activeSessionID)
                    var nextEventRequest: URLRequest? = initialRequest

                    while let eventRequest = nextEventRequest {
                        nextEventRequest = nil

                        // Open the SSE stream first so the agent can push events
                        // as it processes our submitted events.
                        let streamRequest = try self.buildStreamRequest(sessionID: activeSessionID)
                        let parser = SSEParser()
                        let upstreamStream = await self.networkManager.streamRequest(
                            streamRequest,
                            parser: parser
                        )

                        // Submit the user/approval event after opening the stream.
                        try await self.submitEvent(eventRequest)

                        streamLoop: for try await sseEvent in upstreamStream {
                            switch sseEvent {
                            case .done:
                                if state.didEmitMessageStart, !state.didEmitMessageEnd {
                                    continuation.yield(.messageEnd(usage: nil))
                                    state.didEmitMessageEnd = true
                                }
                                continuation.finish()
                                return

                            case .event(_, let data):
                                let result = try Self.parseManagedAgentEvent(
                                    data,
                                    state: &state,
                                    tools: tools
                                )

                                for decodedEvent in result.events {
                                    continuation.yield(decodedEvent)
                                }

                                if let interaction = result.pendingInteraction {
                                    let response = await withTaskCancellationHandler(
                                        operation: {
                                            await interaction.waitForResponse()
                                        },
                                        onCancel: {
                                            Task {
                                                await interaction.resolve(.cancelled(message: nil))
                                            }
                                        }
                                    )
                                    nextEventRequest = try self.buildApprovalRequest(
                                        sessionID: activeSessionID,
                                        interaction: interaction,
                                        response: response
                                    )
                                    break streamLoop
                                }

                                if state.didReachIdle {
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        // `/v1/agents` lives on the agent-api beta, not managed-agents.
        let request = NetworkRequestFactory.makeRequest(
            url: try validatedURL("\(baseURL)/v1/agents"),
            method: "GET",
            headers: agentCatalogHeaders(apiKey: key)
        )

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        let adapter = AnthropicAdapter(
            providerConfig: ProviderConfig(
                id: providerConfig.id,
                name: providerConfig.name,
                type: .anthropic,
                iconID: providerConfig.iconID,
                authModeHint: providerConfig.authModeHint,
                apiKey: providerConfig.apiKey,
                serviceAccountJSON: providerConfig.serviceAccountJSON,
                baseURL: "\(baseURL)/v1",
                models: providerConfig.models,
                isEnabled: providerConfig.isEnabled
            ),
            apiKey: apiKey,
            networkManager: networkManager
        )
        return try await adapter.fetchAvailableModels()
    }

    func listAgents() async throws -> [ClaudeManagedAgentDescriptor] {
        let object = try await fetchManagedAgentsCollection(path: "/v1/agents")
        let items = Self.extractCollectionItems(from: object)

        return items.compactMap { item in
            guard let id = normalizedTrimmedString(
                item.string(at: ["id"])
                    ?? item.string(at: ["agent", "id"])
            ) else {
                return nil
            }

            let name = normalizedTrimmedString(
                item.string(at: ["name"])
                    ?? item.string(at: ["display_name"])
                    ?? item.string(at: ["agent", "name"])
                    ?? item.string(at: ["agent", "display_name"])
            ) ?? id

            let modelID = normalizedTrimmedString(
                item.string(at: ["model", "id"])
                    ?? item.string(at: ["agent", "model", "id"])
                    ?? item.string(at: ["model_id"])
                    ?? item.string(at: ["agent", "model_id"])
                    ?? item.string(at: ["agent", "model"])
                    ?? item.string(at: ["model"])
            )

            let modelDisplayName = normalizedTrimmedString(
                item.string(at: ["model", "display_name"])
                    ?? item.string(at: ["model", "name"])
                    ?? item.string(at: ["agent", "model", "display_name"])
                    ?? item.string(at: ["agent", "model", "name"])
            )

            return ClaudeManagedAgentDescriptor(
                id: id,
                name: name,
                modelID: modelID,
                modelDisplayName: modelDisplayName
            )
        }
    }

    func listEnvironments() async throws -> [ClaudeManagedEnvironmentDescriptor] {
        let object = try await fetchManagedAgentsCollection(path: "/v1/environments")
        let items = Self.extractCollectionItems(from: object)

        return items.compactMap { item in
            guard let id = normalizedTrimmedString(
                item.string(at: ["id"])
                    ?? item.string(at: ["environment", "id"])
            ) else {
                return nil
            }

            let name = normalizedTrimmedString(
                item.string(at: ["name"])
                    ?? item.string(at: ["display_name"])
                    ?? item.string(at: ["environment", "name"])
                    ?? item.string(at: ["environment", "display_name"])
            ) ?? id

            return ClaudeManagedEnvironmentDescriptor(id: id, name: name)
        }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map { tool in
            [
                "type": "custom",
                "name": tool.name,
                "description": tool.description,
                "input_schema": [
                    "type": tool.parameters.type,
                    "properties": tool.parameters.properties.mapValues { $0.toDictionary() },
                    "required": tool.parameters.required
                ]
            ]
        }
    }

    private var baseURL: String {
        providerConfig.baseURL ?? "https://api.anthropic.com"
    }

    /// Headers for the managed-agents session API (`/v1/sessions/*`).
    private func anthropicHeaders(apiKey: String) -> [String: String] {
        [
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
            "anthropic-beta": Self.managedAgentsBeta
        ]
    }

    /// Headers for the agent / environment catalog API (`/v1/agents`,
    /// `/v1/environments`). Uses a different beta and cannot be combined with
    /// `managed-agents-*` in a single request.
    private func agentCatalogHeaders(apiKey: String) -> [String: String] {
        [
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
            "anthropic-beta": Self.agentCatalogBeta
        ]
    }

    private func requiredConfiguredID(_ raw: String?, message: String) throws -> String {
        guard let value = normalizedTrimmedString(raw) else {
            throw LLMError.invalidRequest(message: message)
        }
        return value
    }

    private func createSession(
        agentID: String,
        environmentID: String,
        modelID _: String,
        systemPrompt _: String?,
        tools _: [ToolDefinition]
    ) async throws -> ClaudeManagedAgentSessionState {
        // Per managed-agents-2026-04-01 docs, `agent` accepts either the agent
        // ID string (pins the latest version) or a full agent object.
        let body: [String: Any] = [
            "agent": agentID,
            "environment_id": environmentID
        ]

        let request = try NetworkRequestFactory.makeJSONRequest(
            url: validatedURL("\(baseURL)/v1/sessions"),
            headers: anthropicHeaders(apiKey: apiKey),
            body: body
        )
        let (data, _) = try await networkManager.sendRequest(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let object = Self.dictionaryToJSONValueObject(json)
        let sessionID = normalizedTrimmedString(json?["id"] as? String)
            ?? normalizedTrimmedString((json?["session"] as? [String: Any])?["id"] as? String)
            ?? object.string(at: ["id"])
            ?? object.string(at: ["session", "id"])

        if let sessionID {
            return ClaudeManagedAgentSessionState(
                remoteSessionID: sessionID,
                remoteModelID: Self.extractRemoteModelID(from: object)
            )
        }

        throw LLMError.decodingError(
            message: "Claude Managed Agents session response did not include an id."
        )
    }

    private func fetchManagedAgentsCollection(path: String) async throws -> [String: JSONValue] {
        // `/v1/agents` and `/v1/environments` are served by the agent-api
        // beta, which is incompatible with the managed-agents header used by
        // sessions. Use the catalog-specific headers here.
        let request = NetworkRequestFactory.makeRequest(
            url: try validatedURL("\(baseURL)\(path)"),
            method: "GET",
            headers: agentCatalogHeaders(apiKey: apiKey)
        )
        let (data, _) = try await networkManager.sendRequest(request)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let object = decoded.objectValue else {
            throw LLMError.decodingError(message: "Managed Agents list response was not an object.")
        }
        return object
    }

    private func buildTurnSubmissionRequest(
        sessionID: String,
        messages: [Message],
        controls: GenerationControls
    ) throws -> URLRequest {
        let eventBodies = try buildEventBodies(messages: messages, controls: controls)
        return try makeSessionEventsRequest(sessionID: sessionID, events: eventBodies)
    }

    private func buildApprovalRequest(
        sessionID: String,
        interaction: CodexInteractionRequest,
        response: CodexInteractionResponse
    ) throws -> URLRequest {
        guard let toolUseID = interaction.itemID else {
            throw LLMError.invalidRequest(
                message: "Claude Managed Agents approval reply is missing the required event identifier."
            )
        }

        let approvalChoice: CodexApprovalChoice
        switch response {
        case .approval(let choice):
            approvalChoice = choice
        case .cancelled:
            approvalChoice = .cancel
        case .userInput:
            throw LLMError.invalidRequest(
                message: "Claude Managed Agents tool approval does not accept free-form user input."
            )
        }

        let decision: String
        switch approvalChoice {
        case .accept, .acceptForSession:
            decision = "allow"
        case .decline, .cancel:
            decision = "deny"
        }

        let event: [String: Any] = [
            "type": "user.tool_confirmation",
            "tool_use_id": toolUseID,
            "result": decision
        ]

        return try makeSessionEventsRequest(sessionID: sessionID, events: [event])
    }

    private func buildEventBodies(
        messages: [Message],
        controls: GenerationControls
    ) throws -> [[String: Any]] {
        if !controls.claudeManagedPendingCustomToolResults.isEmpty {
            return try controls.claudeManagedPendingCustomToolResults.map { result in
                var event: [String: Any] = [
                    "type": "user.custom_tool_result",
                    "custom_tool_use_id": result.eventID,
                    "is_error": result.isError
                ]
                if let sessionThreadID = normalizedTrimmedString(result.sessionThreadID) {
                    event["session_thread_id"] = sessionThreadID
                }
                event["content"] = try Self.managedAgentResultContentBlocks(result.content)
                return event
            }
        }

        if let latestUserMessage = messages.last(where: { $0.role == .user }) {
            return [[
                "type": "user.message",
                "content": try Self.managedAgentUserContentBlocks(from: latestUserMessage)
            ]]
        }

        return [[
            "type": "user.message",
            "content": [["type": "text", "text": "Continue."]]
        ]]
    }

    private func makeSessionEventsRequest(
        sessionID: String,
        events: [[String: Any]]
    ) throws -> URLRequest {
        try NetworkRequestFactory.makeJSONRequest(
            url: validatedURL("\(baseURL)/v1/sessions/\(sessionID)/events"),
            headers: anthropicHeaders(apiKey: apiKey),
            body: [
                "events": events
            ]
        )
    }

    private func submitEvent(_ request: URLRequest) async throws {
        _ = try await networkManager.sendRequest(request)
    }

    private func buildStreamRequest(sessionID: String) throws -> URLRequest {
        // Per managed-agents-2026-04-01 docs: `GET /v1/sessions/{id}/events/stream`
        var headers = anthropicHeaders(apiKey: apiKey)
        headers["Accept"] = "text/event-stream"
        return NetworkRequestFactory.makeRequest(
            url: try validatedURL("\(baseURL)/v1/sessions/\(sessionID)/events/stream"),
            method: "GET",
            headers: headers
        )
    }


    private func systemPrompt(from messages: [Message]) -> String? {
        messages.first(where: { $0.role == .system })
            .flatMap(Self.extractPlainText)
    }

    private static func extractPlainText(_ message: Message) -> String? {
        let text = message.content.compactMap { part -> String? in
            if case .text(let text) = part {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return nil
        }.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    private static func managedAgentResultContentBlocks(_ text: String) throws -> [[String: Any]] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeText = normalized.isEmpty ? "<empty_content>" : text
        return [[
            "type": "text",
            "text": safeText
        ]]
    }

    private static func managedAgentUserContentBlocks(from message: Message) throws -> [[String: Any]] {
        var blocks: [[String: Any]] = []

        for part in message.content {
            switch part {
            case .text(let text):
                blocks.append([
                    "type": "text",
                    "text": text
                ])
            case .quote(let quote):
                blocks.append([
                    "type": "text",
                    "text": quote.quotedText
                ])
            case .image(let image):
                if let block = try managedAgentImageBlock(image) {
                    blocks.append(block)
                }
            case .file(let file):
                if let block = try managedAgentFileBlock(file) {
                    blocks.append(block)
                }
            case .video(let video):
                blocks.append([
                    "type": "text",
                    "text": unsupportedVideoInputNotice(
                        video,
                        providerName: "Claude Managed Agents",
                        apiName: "Managed Agents"
                    )
                ])
            case .audio:
                blocks.append([
                    "type": "text",
                    "text": "[Audio attachment]"
                ])
            case .thinking, .redactedThinking:
                break
            }
        }

        if blocks.isEmpty {
            blocks.append([
                "type": "text",
                "text": "Continue."
            ])
        }

        return blocks
    }

    private static func managedAgentImageBlock(_ image: ImageContent) throws -> [String: Any]? {
        let data: Data?
        if let existing = image.data {
            data = existing
        } else if let url = image.url, url.isFileURL {
            data = try resolveFileData(from: url)
        } else {
            data = nil
        }

        guard let data else { return nil }

        return [
            "type": "image",
            "source": [
                "type": "base64",
                "media_type": image.mimeType,
                "data": data.base64EncodedString()
            ]
        ]
    }

    private static func managedAgentFileBlock(_ file: FileContent) throws -> [String: Any]? {
        let normalizedMIMEType = file.mimeType.lowercased()

        if normalizedMIMEType == "application/pdf" {
            let data: Data?
            if let existing = file.data {
                data = existing
            } else if let url = file.url, url.isFileURL {
                data = try resolveFileData(from: url)
            } else {
                data = nil
            }

            if let data {
                return [
                    "type": "document",
                    "source": [
                        "type": "base64",
                        "media_type": "application/pdf",
                        "data": data.base64EncodedString()
                    ]
                ]
            }
        }

        return [
            "type": "text",
            "text": AttachmentPromptRenderer.fallbackText(for: file)
        ]
    }

    private static func parseManagedAgentEvent(
        _ jsonLine: String,
        state: inout ClaudeManagedAgentsStreamState,
        tools: [ToolDefinition]
    ) throws -> ClaudeManagedAgentsParsedEvent {
        guard let data = jsonLine.data(using: .utf8) else {
            return ClaudeManagedAgentsParsedEvent(events: [])
        }

        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let object = decoded.objectValue else {
            return ClaudeManagedAgentsParsedEvent(events: [])
        }

        let type = object.string(at: ["type"])?.lowercased()
            ?? object.string(at: ["event", "type"])?.lowercased()
            ?? object.string(at: ["event_type"])?.lowercased()
            ?? ""

        var events: [StreamEvent] = []
        var pendingInteraction: CodexInteractionRequest?

        if let sessionID = object.string(at: ["session_id"]) ?? object.string(at: ["session", "id"]),
           sessionID != state.sessionID {
            state.sessionID = sessionID
            events.append(.claudeManagedSessionState(
                ClaudeManagedAgentSessionState(
                    remoteSessionID: sessionID,
                    remoteModelID: Self.extractRemoteModelID(from: object)
                )
            ))
        }

        switch type {
        case "agent.message":
            let messageID = object.string(at: ["id"]) ?? UUID().uuidString

            if !state.didEmitMessageStart {
                state.didEmitMessageStart = true
                state.currentMessageID = messageID
                events.append(.messageStart(id: messageID))
            }

            for text in extractTextContent(from: object) where !text.isEmpty {
                events.append(.contentDelta(.text(text)))
            }

        case "agent.tool_use", "agent.mcp_tool_use":
            let eventID = object.string(at: ["id"]) ?? UUID().uuidString
            let toolName = object.string(at: ["name"]) ?? "tool"
            let permission = object.string(at: ["evaluated_permission"])
            // Per docs: values are "allow" | "ask" | "deny". When missing we
            // optimistically treat it as allowed (built-in tools that don't
            // surface permission metadata).
            let requiresApproval = permission == "ask"

            if !requiresApproval {
                let inputObject = object.object(at: ["input"]) ?? [:]
                let arguments = inputObject.mapValues { AnyCodable($0.rawJSONValue) }
                if ToolSearchActivityFactory.isSearchToolName(toolName) {
                    let activity = SearchActivity(
                        id: eventID,
                        type: toolName,
                        status: .inProgress,
                        arguments: arguments
                    )
                    state.pendingSearchActivities[eventID] = activity
                    events.append(.searchActivity(activity))
                } else {
                    let activity = CodexToolActivity(
                        id: eventID,
                        toolName: toolName,
                        status: .running,
                        arguments: arguments
                    )
                    state.pendingGenericToolActivities[eventID] = activity
                    events.append(.codexToolActivity(activity))
                }
            } else {
                // Tool needs user approval — queue and present when status_idle confirms.
                if let interaction = makeToolConfirmationInteraction(from: object, sessionID: state.sessionID) {
                    state.pendingApprovalInteractions.append(interaction)
                }
            }

        case "agent.tool_result":
            // Per docs: references the agent.tool_use event via tool_use_id.
            let referencedID = object.string(at: ["tool_use_id"]) ?? ""
            if let activity = state.pendingSearchActivities[referencedID] {
                let completed = Self.completedSearchActivity(from: object, fallback: activity)
                state.pendingSearchActivities.removeValue(forKey: referencedID)
                events.append(.searchActivity(completed))
            } else if let activity = state.pendingGenericToolActivities[referencedID] {
                let completed = Self.completedGenericToolActivity(from: object, fallback: activity)
                state.pendingGenericToolActivities.removeValue(forKey: referencedID)
                events.append(.codexToolActivity(completed))
            }

        case "agent.mcp_tool_result":
            // Per docs: references the agent.mcp_tool_use event via mcp_tool_use_id.
            let referencedID = object.string(at: ["mcp_tool_use_id"]) ?? ""
            if let activity = state.pendingSearchActivities[referencedID] {
                let completed = Self.completedSearchActivity(from: object, fallback: activity)
                state.pendingSearchActivities.removeValue(forKey: referencedID)
                events.append(.searchActivity(completed))
            } else if let activity = state.pendingGenericToolActivities[referencedID] {
                let completed = Self.completedGenericToolActivity(from: object, fallback: activity)
                state.pendingGenericToolActivities.removeValue(forKey: referencedID)
                events.append(.codexToolActivity(completed))
            }

        case "agent.custom_tool_use":
            if let toolCall = makeCustomToolCall(from: object, tools: tools) {
                events.append(.toolCallStart(toolCall))
                events.append(.toolCallEnd(toolCall))
            }

        case "session.status_idle":
            let requiredActionEventIDs = extractRequiredActionEventIDs(from: object)
            state.didReachIdle = false

            if let nextApprovalIndex = state.pendingApprovalInteractions.firstIndex(where: { interaction in
                guard let itemID = interaction.itemID else { return false }
                return requiredActionEventIDs.contains(itemID)
            }) {
                let interaction = state.pendingApprovalInteractions.remove(at: nextApprovalIndex)
                events.append(.codexInteractionRequest(interaction))
                pendingInteraction = interaction
                break
            }

            state.didReachIdle = true
            if !state.didEmitMessageEnd, state.didEmitMessageStart {
                state.didEmitMessageEnd = true
                events.append(.messageEnd(usage: nil))
            }
            events.append(.claudeManagedSessionState(
                ClaudeManagedAgentSessionState(
                    remoteSessionID: state.sessionID,
                    remoteModelID: Self.extractRemoteModelID(from: object)
                )
            ))
            events.append(.claudeManagedCustomToolResults([]))

        case "session.error":
            let message = object.string(at: ["error", "message"])
                ?? object.string(at: ["message"])
                ?? "Claude Managed Agents returned an error event."
            throw LLMError.providerError(
                code: "claude_managed_agents_error",
                message: message
            )

        case "session.status_terminated", "session.deleted":
            // Session is gone — close the stream gracefully.
            state.didReachIdle = true
            if !state.didEmitMessageEnd, state.didEmitMessageStart {
                state.didEmitMessageEnd = true
                events.append(.messageEnd(usage: nil))
            }

        default:
            // Ignore: session.status_running, session.status_rescheduled,
            // agent.thinking, agent.thread_context_compacted,
            // span.model_request_start / _end, echoed user.* events.
            break
        }

        return ClaudeManagedAgentsParsedEvent(
            events: events,
            pendingInteraction: pendingInteraction
        )
    }

    private static func extractTextContent(from object: [String: JSONValue]) -> [String] {
        // agent.message: { content: [{ type: "text", text: "..." }, ...] }
        if let parts = object.array(at: ["content"]) {
            let texts = parts.compactMap { part -> String? in
                guard let partObject = part.objectValue else { return nil }
                guard partObject.string(at: ["type"]) == "text" else { return nil }
                return partObject.string(at: ["text"])
            }
            if !texts.isEmpty { return texts }
        }

        // Fallback for delta-style or flat text
        if let direct = object.string(at: ["delta", "text"]) { return [direct] }
        if let direct = object.string(at: ["text"]) { return [direct] }

        return []
    }

    private static func extractRequiredActionEventIDs(from object: [String: JSONValue]) -> [String] {
        // Per docs, stop_reason is a discriminated union. When type is
        // "requires_action", event_ids lives directly on stop_reason.
        guard object.string(at: ["stop_reason", "type"]) == "requires_action" else {
            return []
        }
        guard let eventIDs = object.array(at: ["stop_reason", "event_ids"]) else {
            return []
        }
        return eventIDs.compactMap(\.stringValue)
    }

    private static func extractCollectionItems(from object: [String: JSONValue]) -> [[String: JSONValue]] {
        if let data = object.array(at: ["data"])?.compactMap(\.objectValue), !data.isEmpty {
            return data
        }
        if let items = object.array(at: ["items"])?.compactMap(\.objectValue), !items.isEmpty {
            return items
        }
        if let agents = object.array(at: ["agents"])?.compactMap(\.objectValue), !agents.isEmpty {
            return agents
        }
        if let environments = object.array(at: ["environments"])?.compactMap(\.objectValue), !environments.isEmpty {
            return environments
        }
        return []
    }

    private static func extractRemoteModelID(from object: [String: JSONValue]) -> String? {
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

    private static func dictionaryToJSONValueObject(_ dictionary: [String: Any]?) -> [String: JSONValue] {
        guard let dictionary else { return [:] }
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary),
              let decoded = try? JSONDecoder().decode(JSONValue.self, from: data),
              let object = decoded.objectValue else {
            return [:]
        }
        return object
    }

    private static func completedSearchActivity(
        from object: [String: JSONValue],
        fallback: SearchActivity
    ) -> SearchActivity {
        let extractedSources = extractSearchSources(from: object)
        var arguments = fallback.arguments
        if !extractedSources.isEmpty {
            arguments["sources"] = AnyCodable(extractedSources)
            if let firstURL = extractedSources.first?["url"] as? String {
                arguments["url"] = AnyCodable(firstURL)
            }
            if let firstTitle = extractedSources.first?["title"] as? String {
                arguments["title"] = AnyCodable(firstTitle)
            }
        }

        return SearchActivity(
            id: fallback.id,
            type: fallback.type,
            status: object.bool(at: ["is_error"]) == true ? .failed : .completed,
            arguments: arguments
        )
    }

    private static func completedGenericToolActivity(
        from object: [String: JSONValue],
        fallback: CodexToolActivity
    ) -> CodexToolActivity {
        let output = extractToolResultOutput(from: object)
        return CodexToolActivity(
            id: fallback.id,
            toolName: fallback.toolName,
            status: object.bool(at: ["is_error"]) == true ? .failed : .completed,
            arguments: fallback.arguments,
            output: output
        )
    }

    private static func extractToolResultOutput(from object: [String: JSONValue]) -> String? {
        if let content = object.array(at: ["content"]) {
            let chunks = content.compactMap { value -> String? in
                guard let item = value.objectValue else { return nil }
                if let text = normalizedTrimmedString(item.string(at: ["text"])) {
                    return text
                }
                if let url = normalizedTrimmedString(item.string(at: ["url"])) {
                    return url
                }
                return nil
            }
            let joined = chunks.joined(separator: "\n")
            if let normalized = normalizedTrimmedString(joined) {
                return normalized
            }
        }

        if let text = normalizedTrimmedString(object.string(at: ["text"])) {
            return text
        }

        if let result = normalizedTrimmedString(object.string(at: ["result"])) {
            return result
        }

        return nil
    }

    private static func extractSearchSources(from object: [String: JSONValue]) -> [[String: Any]] {
        var sources: [[String: Any]] = []
        var seenURLs: Set<String> = []

        let candidates = object.array(at: ["content"]) ?? []
        for candidate in candidates {
            guard let contentObject = candidate.objectValue else { continue }
            if let url = normalizedTrimmedString(contentObject.string(at: ["url"])) {
                let dedupeKey = url.lowercased()
                guard !seenURLs.contains(dedupeKey) else { continue }
                seenURLs.insert(dedupeKey)
                var item: [String: Any] = ["url": url]
                if let title = normalizedTrimmedString(contentObject.string(at: ["title"])) {
                    item["title"] = title
                }
                if let snippet = normalizedTrimmedString(contentObject.string(at: ["text"]) ?? contentObject.string(at: ["snippet"])) {
                    item["snippet"] = snippet
                }
                sources.append(item)
            }
        }

        if !sources.isEmpty {
            return sources
        }

        guard let output = extractToolResultOutput(from: object) else {
            return []
        }

        let pattern = #"https?://[^\s\])>"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }
        let nsRange = NSRange(output.startIndex..<output.endIndex, in: output)
        let matches = regex.matches(in: output, options: [], range: nsRange)

        for match in matches {
            guard let range = Range(match.range, in: output) else { continue }
            let url = String(output[range])
            let dedupeKey = url.lowercased()
            guard !seenURLs.contains(dedupeKey) else { continue }
            seenURLs.insert(dedupeKey)
            sources.append(["url": url])
        }

        return sources
    }

    private static func makeToolConfirmationInteraction(
        from object: [String: JSONValue],
        sessionID: String
    ) -> CodexInteractionRequest? {
        guard let toolUseID = object.string(at: ["id"]) ?? object.string(at: ["tool_use_id"]) else {
            return nil
        }

        let command = object.string(at: ["tool_name"])
            ?? object.string(at: ["name"])
            ?? "Tool approval"
        let cwd = object.string(at: ["cwd"]) ?? object.string(at: ["working_directory"])
        let reason = object.string(at: ["reason"]) ?? object.string(at: ["message"])
        let request = CodexCommandApprovalRequest(
            command: command,
            cwd: cwd,
            reason: reason,
            actionSummaries: []
        )

        let providerContext: [String: String] = {
            var context: [String: String] = [:]
            if let sessionThreadID = object.string(at: ["session_thread_id"]) {
                context["session_thread_id"] = sessionThreadID
            }
            if let underlyingToolUseID = object.string(at: ["tool_use_id"]) {
                context["underlying_tool_use_id"] = underlyingToolUseID
            }
            return context
        }()

        return CodexInteractionRequest(
            method: "claude_managed_agents/tool_confirmation",
            threadID: sessionID,
            turnID: object.string(at: ["turn_id"]),
            itemID: toolUseID,
            kind: .commandApproval(request),
            providerContext: providerContext
        )
    }

    private static func makeCustomToolCall(
        from object: [String: JSONValue],
        tools: [ToolDefinition]
    ) -> ToolCall? {
        guard let eventID = object.string(at: ["id"])
            ?? object.string(at: ["custom_tool_use_id"])
            ?? object.string(at: ["tool_use_id"]),
            let toolName = object.string(at: ["tool_name"]) ?? object.string(at: ["name"]) else {
            return nil
        }

        guard tools.contains(where: { $0.name == toolName }) else { return nil }

        let argumentsObject = object.object(at: ["input"])
            ?? object.object(at: ["arguments"])
            ?? [:]

        let arguments = argumentsObject.mapValues { jsonValue in
            AnyCodable(jsonValue.rawJSONValue)
        }

        var providerContext: [String: String] = [:]
        if let sessionThreadID = object.string(at: ["session_thread_id"]) {
            providerContext["session_thread_id"] = sessionThreadID
        }
        if let toolUseID = object.string(at: ["custom_tool_use_id"]) ?? object.string(at: ["tool_use_id"]) {
            providerContext["underlying_tool_use_id"] = toolUseID
        }

        return ToolCall(
            id: eventID,
            name: toolName,
            arguments: arguments,
            providerContext: providerContext
        )
    }
}

private struct ClaudeManagedAgentsParsedEvent {
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

private struct ClaudeManagedAgentsStreamState {
    var sessionID: String
    var didEmitMessageStart = false
    var didEmitMessageEnd = false
    var didReachIdle = false
    var currentMessageID: String?
    var pendingApprovalInteractions: [CodexInteractionRequest] = []
    var pendingSearchActivities: [String: SearchActivity] = [:]
    var pendingGenericToolActivities: [String: CodexToolActivity] = [:]
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
