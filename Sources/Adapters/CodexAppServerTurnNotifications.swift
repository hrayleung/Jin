import Foundation

extension CodexAppServerAdapter {
    func handleTurnStarted(
        params: [String: JSONValue],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        state: CodexStreamState
    ) {
        let turnID = params.string(at: ["turn", "id"]) ?? UUID().uuidString
        state.activeTurnID = turnID
        if !state.didEmitMessageStart {
            continuation.yield(.messageStart(id: turnID))
            state.didEmitMessageStart = true
        }
    }

    func emitThinkingDelta(
        _ delta: String?,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) {
        guard let delta, !delta.isEmpty else { return }
        continuation.yield(.thinkingDelta(.thinking(textDelta: delta, signature: nil)))
    }

    func updateTokenUsage(params: [String: JSONValue], state: CodexStreamState) {
        if let usage = parseUsage(from: params.object(at: ["tokenUsage", "last"])) {
            state.latestUsage = usage
        }
    }

    func handleTurnCompletedWithoutParams(
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        state: CodexStreamState
    ) {
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

    func handleTurnCompleted(
        params: [String: JSONValue],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        state: CodexStreamState
    ) throws {
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
    }

    func handleErrorNotification(params: [String: JSONValue]) throws {
        let message = params.string(at: ["error", "message"])
            ?? params.string(at: ["message"])
            ?? "Codex app-server returned an error notification."
        let willRetry = params.bool(at: ["willRetry"]) ?? false

        // `error` notifications may represent transient stream hiccups while Codex is
        // retrying in the background (for example "Reconnecting... 1/5").
        // Surface only terminal errors to the chat UI.
        if willRetry || message.lowercased().contains("reconnecting") {
            return
        }
        throw LLMError.providerError(code: "codex_event_error", message: message)
    }
}
