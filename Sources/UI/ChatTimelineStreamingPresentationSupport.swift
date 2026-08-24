import Foundation

/// Owns the handoff between a just-persisted assistant tool turn and the
/// still-open streaming row.
///
/// After `persistAssistantOutput` the assistant bubble already shows the
/// in-flight MCP cards. Cloning those calls onto the reset live bubble — or
/// leaving an empty "Generating" plate under them — is what produced the
/// duplicate Running row. This type is the single decision point for that
/// gap: suppress the idle live row while the last assistant still owns
/// unresolved visible tools; keep the persisted card as the only live status.
enum ChatTimelineStreamingPresentationSupport {
    struct LastVisibleTurn: Equatable {
        let role: MessageRole
        let unresolvedVisibleToolCallIDs: Set<String>

        var hasUnresolvedVisibleToolCalls: Bool {
            !unresolvedVisibleToolCallIDs.isEmpty
        }
    }

    static func lastVisibleTurn(
        from messages: [MessageRenderItem],
        toolResultsByCallID: [String: ToolResult]
    ) -> LastVisibleTurn? {
        lastVisibleTurn(
            lastMessage: messages.last,
            toolResultsByCallID: toolResultsByCallID
        )
    }

    static func lastVisibleTurn(
        lastMessage: MessageRenderItem?,
        toolResultsByCallID: [String: ToolResult]
    ) -> LastVisibleTurn? {
        guard let lastMessage,
              let role = MessageRole(rawValue: lastMessage.role) else {
            return nil
        }

        let unresolvedIDs = Set(
            lastMessage.visibleToolCalls.compactMap { call in
                toolResultsByCallID[call.id] == nil ? call.id : nil
            }
        )
        return LastVisibleTurn(
            role: role,
            unresolvedVisibleToolCallIDs: unresolvedIDs
        )
    }

    /// Hide the empty live bubble (no Generating plate, no cloned tool card)
    /// while the last visible assistant already owns in-flight MCP tools.
    static func suppressesIdlePlaceholder(
        lastVisibleTurn: LastVisibleTurn?
    ) -> Bool {
        lastVisibleTurn?.role == .assistant
            && lastVisibleTurn?.hasUnresolvedVisibleToolCalls == true
    }

    static func shouldCollapseIdleStreamingRow(
        hasVisiblePresentation: Bool,
        lastVisibleTurn: LastVisibleTurn?
    ) -> Bool {
        !hasVisiblePresentation && suppressesIdlePlaceholder(lastVisibleTurn: lastVisibleTurn)
    }

    /// During a tool handoff the empty live row is hidden, so the last
    /// persisted assistant header temporarily owns the turn's one live orb.
    static func persistedActivityOwnerMessageID(
        isConversationStreaming: Bool,
        lastMessage: MessageRenderItem?,
        toolResultsByCallID: [String: ToolResult]
    ) -> UUID? {
        guard isConversationStreaming, let lastMessage else { return nil }
        let turn = lastVisibleTurn(
            lastMessage: lastMessage,
            toolResultsByCallID: toolResultsByCallID
        )
        guard suppressesIdlePlaceholder(lastVisibleTurn: turn) else { return nil }
        return lastMessage.id
    }

    /// Persisted MCP cards are live only while this conversation is still
    /// streaming and the call has no result yet. Historical unresolved calls
    /// stay as a static Running label.
    static func isLiveToolTimeline(
        isConversationStreaming: Bool,
        visibleToolCalls: [ToolCall],
        toolResultsByCallID: [String: ToolResult]
    ) -> Bool {
        guard isConversationStreaming else { return false }
        return visibleToolCalls.contains { call in
            toolResultsByCallID[call.id] == nil
        }
    }

    /// Persisted snapshot wins on conflict so a just-saved tool body replaces
    /// the in-flight copy. Live results fill gaps for cards that still hold a
    /// pre-persist `shared` snapshot across an identity mutation.
    static func resolvedToolResults(
        persisted: [String: ToolResult],
        live: [String: ToolResult]
    ) -> [String: ToolResult] {
        persisted.merging(live) { persistedResult, _ in persistedResult }
    }
}
