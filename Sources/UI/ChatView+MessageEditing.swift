import SwiftUI
import SwiftData

// MARK: - Message Editing, Regeneration & Deletion

extension ChatView {

    func regenerateMessage(_ messageEntity: MessageEntity) {
        guard !isStreaming else { return }

        cancelEditingUserMessage()

        switch messageEntity.role {
        case "user":
            regenerateFromUserMessage(messageEntity)
        case "assistant":
            regenerateFromAssistantMessage(messageEntity)
        default:
            break
        }
    }

    func beginEditingUserMessage(_ messageEntity: MessageEntity) {
        guard !isStreaming else { return }
        guard messageEntity.role == "user" else { return }

        if editingUserMessageID != messageEntity.id {
            cancelEditingUserMessage()
        }

        guard let editableText = editableUserTextForEditing(messageEntity) else { return }

        editingUserMessageID = messageEntity.id
        editingUserMessageText = editableText
        perMessageMCPServerIDs = ChatPerMessageMCPSelectionSupport.restoredVisibleServerIDs(
            idsData: messageEntity.perMessageMCPServerIDsData,
            namesData: messageEntity.perMessageMCPServerNamesData
        )

        DispatchQueue.main.async {
            isEditingUserMessageFocused = true
        }
    }

    func submitEditingUserMessage(_ messageEntity: MessageEntity) {
        guard !isStreaming else { return }
        guard messageEntity.role == "user" else { return }
        guard editingUserMessageID == messageEntity.id else { return }

        guard let editedText = ChatMessageEditingSupport.normalizedEditedUserText(editingUserMessageText) else {
            cancelEditingUserMessage()
            return
        }

        // One ordered walk for the whole commit. This used to be sorted three
        // separate times on the Enter turn (keep-count, truncate, keep-ID set),
        // each re-faulting the relationship — the edit path's share of the
        // "resend feels laggy" report.
        let orderedMessages = orderedConversationMessages()
        guard let keepCount = ChatMessageEditingSupport.keepCountForRegeneratingUserMessage(
            messageEntity,
            orderedMessages: orderedMessages
        ) else {
            cancelEditingUserMessage()
            return
        }

        let existingHistory = renderCache.activeThreadHistory.first { $0.id == messageEntity.id }
        let newContent: [ContentPart]
        do {
            newContent = try ChatMessageEditingSupport.updateUserMessageContent(
                messageEntity,
                newText: editedText,
                existingContent: existingHistory?.content
            )
        } catch {
            presentError(error.localizedDescription)
            return
        }

        if providerType == .claudeManagedAgents {
            clearClaudeManagedAgentSessionPersistence(for: conversationEntity)
        }

        let selectedServers = eligibleMCPServers.filter { perMessageMCPServerIDs.contains($0.id) }
        let selectedNames = selectedServers.map(\.name).sorted()
        if !selectedServers.isEmpty {
            messageEntity.perMessageMCPServerNamesData = try? JSONEncoder().encode(selectedNames)
            messageEntity.perMessageMCPServerIDsData = try? JSONEncoder().encode(selectedServers.map(\.id).sorted())
        } else {
            messageEntity.perMessageMCPServerNamesData = nil
            messageEntity.perMessageMCPServerIDsData = nil
        }

        let perMessageMCPSnapshot = Set(selectedServers.map(\.id))
        let askedAt = Date()
        let previousUpdatedAt = conversationEntity.updatedAt
        let previousTotalMessageCount = conversationEntity.resolvedMessageCount

        // Truncate BEFORE bumping the edited timestamp. `orderedConversationMessages`
        // sorts by timestamp — flipping it first would keep the wrong prefix.
        defersObservedMessageCacheRebuild = true
        truncateConversationEntities(keepingMessages: keepCount, orderedMessages: orderedMessages)
        messageEntity.timestamp = askedAt
        // The truncate derived the activity date from the pre-edit timestamp;
        // re-derive now that the edited turn carries its resend time.
        conversationEntity.refreshMessageCount()
        conversationEntity.updatedAt = askedAt

        let historyMessage = ChatMessageEditingSupport.makeUpdatedUserMessage(
            from: existingHistory,
            id: messageEntity.id,
            newContent: newContent,
            timestamp: askedAt,
            perMessageMCPServerNames: selectedNames.isEmpty ? nil : selectedNames
        )
        // Same prefix `truncateConversationEntities` just kept — reuse the one
        // ordered walk instead of re-sorting the (now truncated) relationship.
        let keepMessageIDs = Set(
            orderedMessages.prefix(max(0, min(keepCount, orderedMessages.count))).map(\.id)
        ).union([messageEntity.id])
        applyEditedUserTurnToRenderCaches(
            entity: messageEntity,
            message: historyMessage,
            keepMessageIDs: keepMessageIDs,
            previousUpdatedAt: previousUpdatedAt,
            previousTotalMessageCount: previousTotalMessageCount
        )

        perMessageMCPServerIDs = []
        pendingRestoreScrollMessageID = nil
        isPinnedToBottom = true
        // Leave the submitted text in the isolated store. Clearing it here
        // would blank a still-mounted editor if the table's identity mutation
        // has not yet reconfigured this cell.
        endEditingUI()

        let diagnosticRunID = UUID().uuidString
        let conversationID = conversationEntity.id
        armStreamingPlaceholderSession(diagnosticRunID: diagnosticRunID)
        DispatchQueue.main.async {
            self.defersObservedMessageCacheRebuild = false
        }

        Task { @MainActor in
            // First yield: let SwiftUI commit the rewritten bubble +
            // Generating row before any disk / provider work.
            await Task.yield()
            // Always persist the edited turn before honoring Stop. The
            // placeholder was armed with persist deferred; if cancel
            // clears the session during this yield, skipping save would
            // revert the rewrite and truncated reply on relaunch.
            do {
                try modelContext.save()
            } catch {
                streamingStore.cancel(conversationID: conversationID)
                presentError("Failed to save chat: \(error.localizedDescription)")
                return
            }
            guard conversationEntity.id == conversationID else { return }
            guard isStreaming else { return }
            // Second yield: save can be expensive; give layout another
            // chance before startStreamingResponse resolves providers.
            await Task.yield()
            guard conversationEntity.id == conversationID else { return }
            guard isStreaming else { return }
            startStreamingResponse(
                triggeredByUserSend: false,
                diagnosticRunID: diagnosticRunID,
                perMessageMCPServerIDs: perMessageMCPSnapshot
            )
        }
    }

    /// Clears editing UI state without resetting the composer-level per-message MCP selection.
    func endEditingUI() {
        editingUserMessageID = nil
        isEditingUserMessageFocused = false
        if slashCommandTarget == .editMessage {
            isSlashMCPPopoverVisible = false
            slashMCPFilterText = ""
            slashMCPHighlightedIndex = 0
        }
    }

    func cancelEditingUserMessage() {
        endEditingUI()
        perMessageMCPServerIDs = []
    }

    func regenerateFromUserMessage(_ messageEntity: MessageEntity) {
        guard let keepCount = keepCountForRegeneratingUserMessage(messageEntity) else { return }
        var perMessageMCPSnapshot = perMessageMCPServerIDs
        if perMessageMCPSnapshot.isEmpty {
            perMessageMCPSnapshot = ChatPerMessageMCPSelectionSupport.restoredVisibleServerIDs(
                idsData: messageEntity.perMessageMCPServerIDsData,
                namesData: messageEntity.perMessageMCPServerNamesData
            )
        }
        perMessageMCPServerIDs = []
        let askedAt = Date()
        truncateConversation(keepingMessages: keepCount)
        messageEntity.timestamp = askedAt
        // The truncate derived the activity date from the pre-regenerate
        // timestamp. Without this the stale value is non-nil, so the backfill
        // will never repair it and the conversation stays sorted under its old
        // date until some later message mutation. Mirrors the edit path.
        conversationEntity.refreshMessageCount()
        conversationEntity.updatedAt = askedAt
        startStreamingResponse(
            triggeredByUserSend: false,
            perMessageMCPServerIDs: perMessageMCPSnapshot
        )
    }

    func regenerateFromAssistantMessage(_ messageEntity: MessageEntity) {
        guard let keepCount = keepCountForRegeneratingAssistantMessage(messageEntity) else { return }
        truncateConversation(keepingMessages: keepCount)
        startStreamingResponse(triggeredByUserSend: false)
    }

    func deleteMessage(_ messageEntity: MessageEntity) {
        guard !isStreaming else { return }
        cancelEditingUserMessage()

        let ordered = orderedConversationMessages()

        let messagesToDelete: [MessageEntity]?
        switch messageEntity.role {
        case "user":
            messagesToDelete = ChatMessageEditingSupport.messagesToDeleteForUserMessage(messageEntity, orderedMessages: ordered)
        case "assistant":
            messagesToDelete = ChatMessageEditingSupport.messagesToDeleteForAssistantMessage(messageEntity, orderedMessages: ordered)
        default:
            messagesToDelete = nil
        }

        guard let messagesToDelete, !messagesToDelete.isEmpty else { return }
        deleteMessages(messagesToDelete)
    }

    func deleteResponse(_ messageEntity: MessageEntity) {
        guard !isStreaming else { return }
        guard messageEntity.role == "user" else { return }
        cancelEditingUserMessage()

        let ordered = orderedConversationMessages()

        guard let messagesToDelete = ChatMessageEditingSupport.messagesToDeleteForResponse(
            afterUserMessage: messageEntity,
            orderedMessages: ordered
        ) else { return }

        deleteMessages(messagesToDelete)
    }

    func deleteMessages(_ messages: [MessageEntity]) {
        let idsToDelete = Set(messages.map(\.id))
        recordClaudeManagedAgentHistoryMutation(removedMessages: messages)
        for message in messages {
            modelContext.delete(message)
        }
        conversationEntity.messages.removeAll { idsToDelete.contains($0.id) }
        conversationEntity.refreshMessageCount()
        refreshConversationActivityTimestampFromLatestUserMessage()
        do {
            try modelContext.save()
        } catch {
            presentError(error.localizedDescription)
        }
        rebuildMessageCaches()
    }

    func truncateConversation(keepingMessages keepCount: Int) {
        truncateConversationEntities(keepingMessages: keepCount)
        pendingRestoreScrollMessageID = nil
        isPinnedToBottom = true
        rebuildMessageCaches()
    }

    /// Deletes trailing messages without rebuilding the render cache. The
    /// edit path paints the rewritten user turn first; regenerate still
    /// follows this with `rebuildMessageCaches()`.
    /// - Parameter orderedMessages: pass the caller's already-sorted list to
    ///   skip a redundant relationship fault + sort. The edit-commit path runs
    ///   on the Enter keypress turn, where that walk is not free.
    @discardableResult
    func truncateConversationEntities(
        keepingMessages keepCount: Int,
        orderedMessages: [MessageEntity]? = nil
    ) -> [MessageEntity] {
        let ordered = orderedMessages ?? orderedConversationMessages()
        let normalizedKeepCount = max(0, min(keepCount, ordered.count))
        let keepIDs = Set(ordered.prefix(normalizedKeepCount).map(\.id))
        let messagesToDelete = Array(ordered.suffix(from: normalizedKeepCount))
        recordClaudeManagedAgentHistoryMutation(removedMessages: messagesToDelete)

        for message in messagesToDelete {
            modelContext.delete(message)
        }

        conversationEntity.messages.removeAll { !keepIDs.contains($0.id) }
        conversationEntity.refreshMessageCount()
        refreshConversationActivityTimestampFromLatestUserMessage()
        return messagesToDelete
    }

    // MARK: - Helpers

    func keepCountForRegeneratingUserMessage(_ messageEntity: MessageEntity) -> Int? {
        ChatMessageEditingSupport.keepCountForRegeneratingUserMessage(messageEntity, orderedMessages: orderedConversationMessages())
    }

    func keepCountForRegeneratingAssistantMessage(_ messageEntity: MessageEntity) -> Int? {
        ChatMessageEditingSupport.keepCountForRegeneratingAssistantMessage(messageEntity, orderedMessages: orderedConversationMessages())
    }

    func editableUserText(from message: Message) -> String? {
        ChatMessageRenderPipeline.editableUserText(from: message)
    }

    /// Prefer already-decoded render/history text so opening the editor
    /// never JSON-decodes inline image payloads just to seed a string.
    func editableUserTextForEditing(_ messageEntity: MessageEntity) -> String? {
        if let item = renderCache.visibleMessages.first(where: { $0.id == messageEntity.id }),
           let text = ChatMessageEditingSupport.editableUserText(fromRenderedBlocks: item.renderedBlocks) {
            return text
        }
        if let message = renderCache.activeThreadHistory.first(where: { $0.id == messageEntity.id }),
           let text = editableUserText(from: message) {
            return text
        }
        guard let message = try? messageEntity.toDomain() else { return nil }
        return editableUserText(from: message)
    }

    func updateUserMessageContent(_ entity: MessageEntity, newText: String) throws {
        _ = try ChatMessageEditingSupport.updateUserMessageContent(entity, newText: newText)
    }

    func refreshConversationActivityTimestampFromLatestUserMessage() {
        ChatMessageEditingSupport.refreshConversationActivityTimestamp(conversation: conversationEntity)
    }
}
