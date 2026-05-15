import Foundation

extension ClaudeManagedAgentsAdapter {
    struct ActiveManagedAgentSession {
        let id: String
        let startupEvents: [StreamEvent]
    }

    enum ManagedAgentStreamAction {
        case continueStreaming
        case submit(URLRequest)
        case finish
    }

    func resolveSession(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition]
    ) async throws -> ActiveManagedAgentSession {
        let agentID = try requiredConfiguredID(
            controls.claudeManagedAgentID,
            message: "Claude Managed Agents requires an Agent ID in the thread settings."
        )
        let environmentID = try requiredConfiguredID(
            controls.claudeManagedEnvironmentID,
            message: "Claude Managed Agents requires an Environment ID in the thread settings."
        )

        if let existingSessionID = normalizedTrimmedString(controls.claudeManagedSessionID) {
            return ActiveManagedAgentSession(id: existingSessionID, startupEvents: [])
        }

        let createdSession = try await createSession(
            agentID: agentID,
            environmentID: environmentID,
            modelID: modelID,
            systemPrompt: ClaudeManagedAgentRequestSupport.systemPrompt(from: messages),
            tools: tools
        )
        return ActiveManagedAgentSession(
            id: createdSession.remoteSessionID,
            startupEvents: [.claudeManagedSessionState(createdSession)]
        )
    }

    func makeManagedAgentStream(
        session: ActiveManagedAgentSession,
        initialRequest: URLRequest,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for startupEvent in session.startupEvents {
                        continuation.yield(startupEvent)
                    }

                    try await runManagedAgentEventLoop(
                        sessionID: session.id,
                        initialRequest: initialRequest,
                        tools: tools,
                        continuation: continuation
                    )
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

    func runManagedAgentEventLoop(
        sessionID: String,
        initialRequest: URLRequest,
        tools: [ToolDefinition],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var state = ClaudeManagedAgentsStreamState(sessionID: sessionID)
        var nextEventRequest: URLRequest? = initialRequest

        while let eventRequest = nextEventRequest {
            nextEventRequest = nil

            let upstreamStream = try await openStreamThenSubmitEvent(
                sessionID: sessionID,
                eventRequest: eventRequest
            )

            streamLoop: for try await sseEvent in upstreamStream {
                let action = try await handleManagedAgentStreamEvent(
                    sseEvent,
                    sessionID: sessionID,
                    state: &state,
                    tools: tools,
                    continuation: continuation
                )

                switch action {
                case .continueStreaming:
                    continue

                case .submit(let request):
                    nextEventRequest = request
                    break streamLoop

                case .finish:
                    continuation.finish()
                    return
                }
            }
        }

        continuation.finish()
    }

    func handleManagedAgentStreamEvent(
        _ sseEvent: SSEEvent,
        sessionID: String,
        state: inout ClaudeManagedAgentsStreamState,
        tools: [ToolDefinition],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws -> ManagedAgentStreamAction {
        switch sseEvent {
        case .done:
            yieldOpenMessageEndIfNeeded(state: &state, continuation: continuation)
            return .finish

        case .event(_, let data):
            let result = try ClaudeManagedAgentStreamParsingSupport.parseEvent(
                data,
                state: &state,
                tools: tools
            )

            for decodedEvent in result.events {
                continuation.yield(decodedEvent)
            }

            if let interaction = result.pendingInteraction {
                let response = await waitForInteractionResponse(interaction)
                let request = try buildApprovalRequest(
                    sessionID: sessionID,
                    interaction: interaction,
                    response: response
                )
                return .submit(request)
            }

            return state.didReachIdle ? .finish : .continueStreaming
        }
    }

    func openStreamThenSubmitEvent(
        sessionID: String,
        eventRequest: URLRequest
    ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        // Open the SSE stream first so the agent can push events as it processes
        // our submitted events.
        let streamRequest = try buildStreamRequest(sessionID: sessionID)
        let upstreamStream = await networkManager.streamRequest(
            streamRequest,
            parser: SSEParser()
        )

        try await submitEvent(eventRequest)
        return upstreamStream
    }

    func waitForInteractionResponse(
        _ interaction: ManagedAgentInteractionRequest
    ) async -> ManagedAgentInteractionResponse {
        await withTaskCancellationHandler(
            operation: {
                await interaction.waitForResponse()
            },
            onCancel: {
                Task {
                    await interaction.resolve(.cancelled(message: nil))
                }
            }
        )
    }

    func yieldOpenMessageEndIfNeeded(
        state: inout ClaudeManagedAgentsStreamState,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) {
        guard state.didEmitMessageStart, !state.didEmitMessageEnd else { return }
        continuation.yield(.messageEnd(usage: state.accumulatedUsage))
        state.didEmitMessageEnd = true
    }
}
