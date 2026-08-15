import Foundation

enum ChatMessageEditingSupport {

    static func normalizedEditedUserText(_ text: String) -> String? {
        text.trimmedNonEmpty
    }

    static func replacingTextParts(in content: [ContentPart], with newText: String) -> [ContentPart] {
        var newContent: [ContentPart] = []
        newContent.reserveCapacity(max(1, content.count))

        var didInsertText = false
        for part in content {
            switch part {
            case .text:
                if !didInsertText {
                    newContent.append(.text(newText))
                    didInsertText = true
                }
            default:
                newContent.append(part)
            }
        }

        if !didInsertText {
            newContent.append(.text(newText))
        }

        return newContent
    }

    /// Persists the edited text. Prefer passing `existingContent` from the
    /// in-memory history cache so image/file parts are not JSON-decoded just
    /// to rewrite one string.
    @discardableResult
    static func updateUserMessageContent(
        _ entity: MessageEntity,
        newText: String,
        existingContent: [ContentPart]? = nil
    ) throws -> [ContentPart] {
        let originalContent = try existingContent ?? JSONDecoder().decode([ContentPart].self, from: entity.contentData)
        let newContent = replacingTextParts(in: originalContent, with: newText)
        entity.contentData = try JSONEncoder().encode(newContent)
        return newContent
    }

    static func makeUpdatedUserMessage(
        from existing: Message?,
        id: UUID,
        newContent: [ContentPart],
        timestamp: Date,
        perMessageMCPServerNames: [String]?
    ) -> Message {
        Message(
            id: id,
            role: .user,
            content: newContent,
            toolCalls: existing?.toolCalls,
            toolResults: existing?.toolResults,
            searchActivities: existing?.searchActivities,
            codeExecutionActivities: existing?.codeExecutionActivities,
            timestamp: timestamp,
            perMessageMCPServerNames: perMessageMCPServerNames
        )
    }

    static func editableUserText(fromRenderedBlocks blocks: [RenderedMessageBlock]) -> String? {
        let parts = blocks.compactMap { block -> String? in
            guard case .content(_, .text(let text)) = block else { return nil }
            return text.trimmedNonEmpty
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n\n")
    }

    static func keepCountForRegeneratingUserMessage(
        _ messageEntity: MessageEntity,
        orderedMessages: [MessageEntity]
    ) -> Int? {
        keepCount(for: messageEntity, orderedMessages: orderedMessages, offset: 1)
    }

    static func keepCountForRegeneratingAssistantMessage(
        _ messageEntity: MessageEntity,
        orderedMessages: [MessageEntity]
    ) -> Int? {
        keepCount(for: messageEntity, orderedMessages: orderedMessages, offset: 0)
    }

    /// Returns `index + offset` for the given message within `orderedMessages`,
    /// or `nil` if the message is not found or the result is zero (nothing to keep).
    private static func keepCount(
        for messageEntity: MessageEntity,
        orderedMessages: [MessageEntity],
        offset: Int
    ) -> Int? {
        guard let index = orderedMessages.firstIndex(where: { $0.id == messageEntity.id }) else { return nil }
        let keepCount = index + offset
        guard keepCount > 0 else { return nil }
        return keepCount
    }

    static func messagesToDeleteForUserMessage(
        _ messageEntity: MessageEntity,
        orderedMessages: [MessageEntity]
    ) -> [MessageEntity]? {
        guard orderedMessages.contains(where: { $0.id == messageEntity.id }) else { return nil }
        return [messageEntity]
    }

    static func messagesToDeleteForResponse(
        afterUserMessage messageEntity: MessageEntity,
        orderedMessages: [MessageEntity]
    ) -> [MessageEntity]? {
        MessageRoleIdentifiableSupport.messagesToDeleteForResponse(
            afterUserMessage: messageEntity,
            orderedMessages: orderedMessages
        )
    }

    static func messagesToDeleteForAssistantMessage(
        _ messageEntity: MessageEntity,
        orderedMessages: [MessageEntity]
    ) -> [MessageEntity]? {
        guard let index = orderedMessages.firstIndex(where: { $0.id == messageEntity.id }) else { return nil }

        var result: [MessageEntity] = [messageEntity]
        for i in (index + 1)..<orderedMessages.count {
            let msg = orderedMessages[i]
            if msg.role == MessageRole.tool.rawValue {
                result.append(msg)
            } else {
                break
            }
        }
        return result
    }

    static func refreshConversationActivityTimestamp(conversation: ConversationEntity) {
        conversation.updatedAt = ConversationActivitySupport.activityDate(for: conversation)
    }
}
