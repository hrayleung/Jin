import Foundation

extension CodexAppServerAdapter {
    func handleItemStarted(
        method: String,
        params: [String: JSONValue],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        state: CodexStreamState
    ) {
        guard let item = params.object(at: ["item"]) else { return }
        emitSearchAndToolActivity(
            item: item,
            method: method,
            params: params,
            continuation: continuation,
            state: state
        )
    }

    func handleAgentMessageDelta(
        params: [String: JSONValue],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        state: CodexStreamState
    ) {
        guard let delta = params.string(at: ["delta"]), !delta.isEmpty else {
            return
        }

        emitAssistantText(
            delta,
            params: params,
            continuation: continuation,
            state: state
        )
    }

    func handleItemCompleted(
        method: String,
        params: [String: JSONValue],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        state: CodexStreamState
    ) {
        guard let item = params.object(at: ["item"]) else { return }

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

        if itemType == "dynamicToolCall" {
            handleCompletedDynamicToolCall(
                item: item,
                method: method,
                params: params,
                continuation: continuation,
                state: state
            )
            return
        }

        emitSearchAndToolActivity(
            item: item,
            method: method,
            params: params,
            continuation: continuation,
            state: state
        )
    }

    func handleCompletedDynamicToolCall(
        item: [String: JSONValue],
        method: String,
        params: [String: JSONValue],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        state: CodexStreamState
    ) {
        // Compatibility: newer app-server versions can return multimodal dynamic tool outputs.
        // Surface them in the stream so users can still see text/image tool results.
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
    }

    func handleItemUpdated(
        method: String,
        params: [String: JSONValue],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        state: CodexStreamState
    ) {
        guard let item = params.object(at: ["item"]) else { return }

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
    }

    func handleDynamicToolNotification(
        method: String,
        params: [String: JSONValue],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        state: CodexStreamState
    ) {
        var item = params.object(at: ["item"]) ?? params
        if item.string(at: ["type"]) == nil {
            item["type"] = .string("dynamicToolCall")
        }

        emitSearchAndToolActivity(
            item: item,
            method: method,
            params: params,
            continuation: continuation,
            state: state
        )
    }

    func handleToolSubNotification(
        method: String,
        params: [String: JSONValue],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        state: CodexStreamState
    ) {
        let item = params.object(at: ["item"]) ?? params
        if let toolActivity = Self.codexToolActivityFromCodexItem(
            item: item,
            method: method,
            params: params,
            fallbackTurnID: state.activeTurnID
        ) {
            continuation.yield(.codexToolActivity(toolActivity))
        }
    }

    func emitSearchAndToolActivity(
        item: [String: JSONValue],
        method: String,
        params: [String: JSONValue],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        state: CodexStreamState
    ) {
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
    }

    nonisolated static func isToolSubNotification(_ method: String) -> Bool {
        method.hasPrefix("item/commandExecution/")
            || method.hasPrefix("item/fileChange/")
            || method.hasPrefix("item/mcpToolCall/")
            || method.hasPrefix("item/collabToolCall/")
    }
}
