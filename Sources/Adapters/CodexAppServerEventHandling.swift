import Foundation

// MARK: - Server Event Handling

extension CodexAppServerAdapter {

    func handleInterleavedEnvelope(
        _ envelope: JSONRPCEnvelope,
        with client: CodexWebSocketRPCClient,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        state: CodexStreamState
    ) async throws {
        if let method = envelope.method {
            if let requestID = envelope.id {
                try await handleServerRequest(
                    id: requestID,
                    method: method,
                    params: envelope.params?.objectValue,
                    with: client,
                    continuation: continuation
                )
                return
            }

            guard let params = envelope.params?.objectValue else {
                if method == "turn/completed" {
                    handleTurnCompletedWithoutParams(
                        continuation: continuation,
                        state: state
                    )
                }
                return
            }

            switch method {
            case "turn/started":
                handleTurnStarted(
                    params: params,
                    continuation: continuation,
                    state: state
                )

            case "item/started":
                handleItemStarted(
                    method: method,
                    params: params,
                    continuation: continuation,
                    state: state
                )

            case "item/agentMessage/delta":
                handleAgentMessageDelta(
                    params: params,
                    continuation: continuation,
                    state: state
                )

            case "item/reasoning/textDelta", "item/reasoning/summaryTextDelta":
                emitThinkingDelta(
                    params.string(at: ["delta"]),
                    continuation: continuation
                )

            case "item/reasoning/summaryPartAdded":
                emitThinkingDelta(
                    params.string(at: ["part", "text"]) ?? params.string(at: ["text"]),
                    continuation: continuation
                )

            case "item/completed":
                handleItemCompleted(
                    method: method,
                    params: params,
                    continuation: continuation,
                    state: state
                )

            case "item/updated":
                handleItemUpdated(
                    method: method,
                    params: params,
                    continuation: continuation,
                    state: state
                )

            case let dynamicToolMethod where dynamicToolMethod.hasPrefix("item/dynamicToolCall/"):
                handleDynamicToolNotification(
                    method: dynamicToolMethod,
                    params: params,
                    continuation: continuation,
                    state: state
                )

            case let itemSubMethod where Self.isToolSubNotification(itemSubMethod):
                handleToolSubNotification(
                    method: itemSubMethod,
                    params: params,
                    continuation: continuation,
                    state: state
                )

            case "thread/tokenUsage/updated":
                updateTokenUsage(params: params, state: state)

            case "model/rerouted":
                // Compatibility no-op for newer app-server notifications.
                // We keep streaming behavior unchanged while tolerating reroute events.
                break

            case "turn/completed":
                try handleTurnCompleted(
                    params: params,
                    continuation: continuation,
                    state: state
                )

            case "error":
                try handleErrorNotification(params: params)

            default:
                break
            }
        }
    }

}
