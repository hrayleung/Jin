import Foundation

// MARK: - Server Event & Request Handling

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
                    if !state.didEmitMessageEnd {
                        if !state.didEmitMessageStart {
                            let startID = state.activeTurnID ?? UUID().uuidString
                            continuation.yield(.messageStart(id: startID))
                            state.didEmitMessageStart = true
                        }
                        continuation.yield(.messageEnd(usage: state.latestUsage))
                        state.didEmitMessageEnd = true
                    }
                    state.didCompleteTurn = true
                }
                return
            }

            switch method {
            case "turn/started":
                let turnID = params.string(at: ["turn", "id"]) ?? UUID().uuidString
                state.activeTurnID = turnID
                if !state.didEmitMessageStart {
                    continuation.yield(.messageStart(id: turnID))
                    state.didEmitMessageStart = true
                }

            case "item/started":
                guard let item = params.object(at: ["item"]) else { break }
                if let activity = Self.searchActivityFromCodexItem(
                    item: item,
                    method: method,
                    params: params,
                    fallbackTurnID: state.activeTurnID
                ) {
                    continuation.yield(.searchActivity(activity))
                }
                if let toolActivity = Self.codexToolActivityFromCodexItem(
                    item: item,
                    method: method,
                    params: params,
                    fallbackTurnID: state.activeTurnID
                ) {
                    continuation.yield(.codexToolActivity(toolActivity))
                }

            case "item/agentMessage/delta":
                if let delta = params.string(at: ["delta"]), !delta.isEmpty {
                    emitAssistantText(
                        delta,
                        params: params,
                        continuation: continuation,
                        state: state
                    )
                }

            case "item/reasoning/textDelta", "item/reasoning/summaryTextDelta":
                if let delta = params.string(at: ["delta"]), !delta.isEmpty {
                    continuation.yield(.thinkingDelta(.thinking(textDelta: delta, signature: nil)))
                }

            case "item/reasoning/summaryPartAdded":
                if let delta = params.string(at: ["part", "text"]) ?? params.string(at: ["text"]),
                   !delta.isEmpty {
                    continuation.yield(.thinkingDelta(.thinking(textDelta: delta, signature: nil)))
                }

            case "item/completed":
                guard let item = params.object(at: ["item"]) else { break }

                let itemType = item.string(at: ["type"]) ?? ""
                if itemType == "agentMessage",
                   let completedText = Self.parseAgentMessageText(from: item) {
                    emitAssistantTextSnapshot(
                        completedText,
                        params: params,
                        continuation: continuation,
                        state: state
                    )
                }

                // Compatibility: newer app-server versions can return multimodal dynamic tool outputs.
                // Surface them in the stream so users can still see text/image tool results.
                if itemType == "dynamicToolCall" {
                    for part in Self.parseDynamicToolCallOutputParts(from: item) {
                        if case .text(let text) = part {
                            state.assistantTextBuffer.append(text)
                            state.didEmitAssistantText = true
                        }
                        continuation.yield(.contentDelta(part))
                    }
                    if let activity = Self.searchActivityFromDynamicToolCall(
                        item: item,
                        method: method,
                        params: params,
                            fallbackTurnID: state.activeTurnID
                    ) {
                        continuation.yield(.searchActivity(activity))
                    }
                    if let toolActivity = Self.codexToolActivityFromDynamicToolCall(
                        item: item,
                        method: method,
                        params: params,
                        fallbackTurnID: state.activeTurnID
                    ) {
                        continuation.yield(.codexToolActivity(toolActivity))
                    }

                    break
                }

                if let activity = Self.searchActivityFromCodexItem(
                    item: item,
                    method: method,
                    params: params,
                    fallbackTurnID: state.activeTurnID
                ) {
                    continuation.yield(.searchActivity(activity))
                }
                if let toolActivity = Self.codexToolActivityFromCodexItem(
                    item: item,
                    method: method,
                    params: params,
                    fallbackTurnID: state.activeTurnID
                ) {
                    continuation.yield(.codexToolActivity(toolActivity))
                }

            case "item/updated":
                guard let item = params.object(at: ["item"]) else { break }
                let itemType = item.string(at: ["type"]) ?? ""
                if itemType == "agentMessage",
                   let snapshotText = Self.parseAgentMessageText(from: item) {
                    emitAssistantTextSnapshot(
                        snapshotText,
                        params: params,
                        continuation: continuation,
                        state: state
                    )
                } else if let activity = Self.searchActivityFromCodexItem(
                    item: item,
                    method: method,
                    params: params,
                    fallbackTurnID: state.activeTurnID
                ) {
                    continuation.yield(.searchActivity(activity))
                }
                if let toolActivity = Self.codexToolActivityFromCodexItem(
                    item: item,
                    method: method,
                    params: params,
                    fallbackTurnID: state.activeTurnID
                ) {
                    continuation.yield(.codexToolActivity(toolActivity))
                }

            case let dynamicToolMethod where dynamicToolMethod.hasPrefix("item/dynamicToolCall/"):
                var item = params.object(at: ["item"]) ?? params
                if item.string(at: ["type"]) == nil {
                    item["type"] = .string("dynamicToolCall")
                }
                if let activity = Self.searchActivityFromCodexItem(
                    item: item,
                    method: dynamicToolMethod,
                    params: params,
                    fallbackTurnID: state.activeTurnID
                ) {
                    continuation.yield(.searchActivity(activity))
                }
                if let toolActivity = Self.codexToolActivityFromCodexItem(
                    item: item,
                    method: dynamicToolMethod,
                    params: params,
                    fallbackTurnID: state.activeTurnID
                ) {
                    continuation.yield(.codexToolActivity(toolActivity))
                }

            case let itemSubMethod where itemSubMethod.hasPrefix("item/commandExecution/")
                || itemSubMethod.hasPrefix("item/fileChange/")
                || itemSubMethod.hasPrefix("item/mcpToolCall/")
                || itemSubMethod.hasPrefix("item/collabToolCall/"):
                let item = params.object(at: ["item"]) ?? params
                if let toolActivity = Self.codexToolActivityFromCodexItem(
                    item: item,
                    method: itemSubMethod,
                    params: params,
                    fallbackTurnID: state.activeTurnID
                ) {
                    continuation.yield(.codexToolActivity(toolActivity))
                }

            case "thread/tokenUsage/updated":
                if let usage = parseUsage(from: params.object(at: ["tokenUsage", "last"])) {
                    state.latestUsage = usage
                }

            case "model/rerouted":
                // Compatibility no-op for newer app-server notifications.
                // We keep streaming behavior unchanged while tolerating reroute events.
                break

            case "turn/completed":
                let status = params.string(at: ["turn", "status"])?.lowercased()
                if status == "failed" {
                    let message = params.string(at: ["turn", "error", "message"])
                        ?? "Codex turn failed."
                    throw LLMError.providerError(code: "turn_failed", message: message)
                }

                if !state.didEmitMessageStart {
                    let turnID = params.string(at: ["turn", "id"]) ?? state.activeTurnID ?? UUID().uuidString
                    state.activeTurnID = turnID
                    continuation.yield(.messageStart(id: turnID))
                    state.didEmitMessageStart = true
                }

                if !state.didEmitMessageEnd {
                    continuation.yield(.messageEnd(usage: state.latestUsage))
                    state.didEmitMessageEnd = true
                }
                state.didCompleteTurn = true

            case "error":
                let message = params.string(at: ["error", "message"])
                    ?? params.string(at: ["message"])
                    ?? "Codex app-server returned an error notification."
                let willRetry = params.bool(at: ["willRetry"]) ?? false

                // `error` notifications may represent transient stream hiccups while Codex is
                // retrying in the background (for example "Reconnecting... 1/5").
                // Surface only terminal errors to the chat UI.
                if willRetry || message.lowercased().contains("reconnecting") {
                    break
                }
                throw LLMError.providerError(code: "codex_event_error", message: message)

            default:
                break
            }
        }
    }

    func handleServerRequest(
        id: JSONRPCID,
        method: String,
        params: [String: JSONValue]?,
        with client: CodexWebSocketRPCClient,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation?
    ) async throws {
        let params = params ?? [:]

        if let continuation,
           let interaction = Self.interactionRequest(id: id, method: method, params: params) {
            continuation.yield(.codexInteractionRequest(interaction))
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
            try await Self.sendInteractionResponse(
                response,
                for: interaction,
                requestID: id,
                client: client
            )
            return
        }

        if let autoReply = CodexAppServerAutoReply.result(forServerRequestMethod: method) {
            try await client.respond(id: id, result: autoReply)
            return
        }

        let message: String
        switch method {
        case "item/tool/call", "item/tool/requestUserInput":
            message = "Client callbacks are disabled for this Codex App Server provider."
        default:
            message = "Unsupported server request method: \(method)"
        }

        try await client.respondWithError(
            id: id,
            code: -32601,
            message: message
        )
    }
}
