import Foundation

enum ChatMessageEditingSupport {

    static func editableUserText(from message: Message) -> String? {
        message.content.compactMap { part in
            if case .text(let text) = part { return text }
            return nil
        }.first
    }

    static func updateUserMessageContent(_ entity: MessageEntity, newText: String) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        let originalContent = try decoder.decode([ContentPart].self, from: entity.contentData)
        var newContent: [ContentPart] = []
        newContent.reserveCapacity(max(1, originalContent.count))

        var didInsertText = false
        for part in originalContent {
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

        entity.contentData = try encoder.encode(newContent)
    }

    static func keepCountForRegeneratingUserMessage(
        _ messageEntity: MessageEntity,
        orderedMessages: [MessageEntity]
    ) -> Int? {
        guard let index = orderedMessages.firstIndex(where: { $0.id == messageEntity.id }) else { return nil }
        let keepCount = index + 1
        guard keepCount > 0 else { return nil }
        return keepCount
    }

    static func keepCountForRegeneratingAssistantMessage(
        _ messageEntity: MessageEntity,
        orderedMessages: [MessageEntity]
    ) -> Int? {
        guard let index = orderedMessages.firstIndex(where: { $0.id == messageEntity.id }) else { return nil }
        let keepCount = index
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
        guard let index = orderedMessages.firstIndex(where: { $0.id == messageEntity.id }) else { return nil }
        let startIndex = index + 1
        guard startIndex < orderedMessages.count else { return nil }

        var result: [MessageEntity] = []
        for i in startIndex..<orderedMessages.count {
            let msg = orderedMessages[i]
            if msg.role == MessageRole.user.rawValue { break }
            result.append(msg)
        }
        return result.isEmpty ? nil : result
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
        let latestUserTimestamp = conversation.messages
            .filter { $0.role == MessageRole.user.rawValue }
            .map(\.timestamp)
            .max()

        conversation.updatedAt = latestUserTimestamp ?? conversation.createdAt
    }
}
