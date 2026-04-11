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

        guard let message = try? messageEntity.toDomain() else { return }
        guard let editableText = editableUserText(from: message), !editableText.isEmpty else { return }

        editingUserMessageID = messageEntity.id
        editingUserMessageText = editableText
        if let idsData = messageEntity.perMessageMCPServerIDsData,
           let savedIDs = try? JSONDecoder().decode([String].self, from: idsData) {
            perMessageMCPServerIDs = Set(savedIDs)
        } else {
            perMessageMCPServerIDs = []
        }

        DispatchQueue.main.async {
            isEditingUserMessageFocused = true
        }
    }

    func submitEditingUserMessage(_ messageEntity: MessageEntity) {
        guard !isStreaming else { return }
        guard messageEntity.role == "user" else { return }
        guard editingUserMessageID == messageEntity.id else { return }

        let trimmed = editingUserMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil else {
            cancelEditingUserMessage()
            return
        }

        do {
            try updateUserMessageContent(messageEntity, newText: trimmed)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            return
        }

        if let threadID = messageEntity.contextThreadID ?? activeModelThread?.id {
            invalidateCodexThreadPersistence(forThreadID: threadID)
            invalidateClaudeManagedAgentSessionPersistence(forThreadID: threadID)
        }

        let selectedServers = eligibleMCPServers.filter { perMessageMCPServerIDs.contains($0.id) }
        if !selectedServers.isEmpty {
            messageEntity.perMessageMCPServerNamesData = try? JSONEncoder().encode(selectedServers.map(\.name).sorted())
            messageEntity.perMessageMCPServerIDsData = try? JSONEncoder().encode(selectedServers.map(\.id).sorted())
        } else {
            messageEntity.perMessageMCPServerNamesData = nil
            messageEntity.perMessageMCPServerIDsData = nil
        }

        endEditingUI()
        regenerateFromUserMessage(messageEntity)
    }

    /// Clears editing UI state without resetting the composer-level per-message MCP selection.
    func endEditingUI() {
        editingUserMessageID = nil
        editingUserMessageText = ""
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
        guard let threadID = messageEntity.contextThreadID ?? activeModelThread?.id else { return }
        guard let keepCount = keepCountForRegeneratingUserMessage(messageEntity, threadID: threadID) else { return }
        var perMessageMCPSnapshot = perMessageMCPServerIDs
        if perMessageMCPSnapshot.isEmpty,
           let idsData = messageEntity.perMessageMCPServerIDsData,
           let savedIDs = try? JSONDecoder().decode([String].self, from: idsData) {
            perMessageMCPSnapshot = Set(savedIDs)
        }
        perMessageMCPServerIDs = []
        let askedAt = Date()
        truncateConversation(keepingMessages: keepCount, in: threadID)
        messageEntity.timestamp = askedAt
        conversationEntity.updatedAt = askedAt
        activateThread(by: threadID)
        startStreamingResponse(
            for: threadID,
            triggeredByUserSend: false,
            perMessageMCPServerIDs: perMessageMCPSnapshot
        )
    }

    func regenerateFromAssistantMessage(_ messageEntity: MessageEntity) {
        guard let threadID = messageEntity.contextThreadID ?? activeModelThread?.id else { return }
        guard let keepCount = keepCountForRegeneratingAssistantMessage(messageEntity, threadID: threadID) else { return }
        truncateConversation(keepingMessages: keepCount, in: threadID)
        activateThread(by: threadID)
        startStreamingResponse(for: threadID, triggeredByUserSend: false)
    }

    func deleteMessage(_ messageEntity: MessageEntity) {
        guard !isStreaming else { return }
        cancelEditingUserMessage()

        let threadID = messageEntity.contextThreadID ?? activeModelThread?.id
        guard let threadID else { return }
        let ordered = orderedConversationMessages(threadID: threadID)

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
        deleteMessages(messagesToDelete, in: threadID)
    }

    func deleteResponse(_ messageEntity: MessageEntity) {
        guard !isStreaming else { return }
        guard messageEntity.role == "user" else { return }
        cancelEditingUserMessage()

        let threadID = messageEntity.contextThreadID ?? activeModelThread?.id
        guard let threadID else { return }
        let ordered = orderedConversationMessages(threadID: threadID)

        guard let messagesToDelete = ChatMessageEditingSupport.messagesToDeleteForResponse(
            afterUserMessage: messageEntity,
            orderedMessages: ordered
        ) else { return }

        deleteMessages(messagesToDelete, in: threadID)
    }

    func deleteMessages(_ messages: [MessageEntity], in threadID: UUID) {
        let idsToDelete = Set(messages.map(\.id))
        recordCodexThreadHistoryMutation(forThreadID: threadID, removedMessages: messages)
        recordClaudeManagedAgentHistoryMutation(forThreadID: threadID, removedMessages: messages)
        for message in messages {
            modelContext.delete(message)
        }
        conversationEntity.messages.removeAll { idsToDelete.contains($0.id) }
        refreshConversationActivityTimestampFromLatestUserMessage()
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        rebuildMessageCaches()
    }

    func truncateConversation(keepingMessages keepCount: Int, in threadID: UUID) {
        let ordered = orderedConversationMessages(threadID: threadID)
        let normalizedKeepCount = max(0, min(keepCount, ordered.count))
        let keepIDs = Set(ordered.prefix(normalizedKeepCount).map(\.id))
        let messagesToDelete = Array(ordered.suffix(from: normalizedKeepCount))
        recordCodexThreadHistoryMutation(forThreadID: threadID, removedMessages: messagesToDelete)
        recordClaudeManagedAgentHistoryMutation(forThreadID: threadID, removedMessages: messagesToDelete)

        for message in messagesToDelete {
            modelContext.delete(message)
        }

        conversationEntity.messages.removeAll {
            $0.contextThreadID == threadID && !keepIDs.contains($0.id)
        }
        refreshConversationActivityTimestampFromLatestUserMessage()
        pendingRestoreScrollMessageID = nil
        isPinnedToBottom = true
        rebuildMessageCaches()
    }

    // MARK: - Helpers

    func keepCountForRegeneratingUserMessage(_ messageEntity: MessageEntity, threadID: UUID) -> Int? {
        ChatMessageEditingSupport.keepCountForRegeneratingUserMessage(messageEntity, orderedMessages: orderedConversationMessages(threadID: threadID))
    }

    func keepCountForRegeneratingAssistantMessage(_ messageEntity: MessageEntity, threadID: UUID) -> Int? {
        ChatMessageEditingSupport.keepCountForRegeneratingAssistantMessage(messageEntity, orderedMessages: orderedConversationMessages(threadID: threadID))
    }

    func editableUserText(from message: Message) -> String? {
        ChatMessageRenderPipeline.editableUserText(from: message)
    }

    func updateUserMessageContent(_ entity: MessageEntity, newText: String) throws {
        try ChatMessageEditingSupport.updateUserMessageContent(entity, newText: newText)
    }

    func refreshConversationActivityTimestampFromLatestUserMessage() {
        ChatMessageEditingSupport.refreshConversationActivityTimestamp(conversation: conversationEntity)
    }
}
