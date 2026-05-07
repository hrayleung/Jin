import Foundation
import SwiftData

@Model
final class MessageHighlightEntity {
    @Attribute(.unique) var id: UUID
    var messageID: UUID
    var conversationID: UUID
    var contextThreadID: UUID?
    var anchorID: String
    var selectedText: String
    var prefixContext: String?
    var suffixContext: String?
    var startOffset: Int
    var endOffset: Int
    var colorStyleRaw: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship var conversation: ConversationEntity?
    @Relationship var message: MessageEntity?

    init(
        id: UUID = UUID(),
        messageID: UUID,
        conversationID: UUID,
        contextThreadID: UUID? = nil,
        anchorID: String,
        selectedText: String,
        prefixContext: String? = nil,
        suffixContext: String? = nil,
        startOffset: Int,
        endOffset: Int,
        colorStyle: MessageHighlightColorStyle = .readerYellow,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.messageID = messageID
        self.conversationID = conversationID
        self.contextThreadID = contextThreadID
        self.anchorID = anchorID
        self.selectedText = selectedText
        self.prefixContext = prefixContext
        self.suffixContext = suffixContext
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.colorStyleRaw = colorStyle.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var colorStyle: MessageHighlightColorStyle {
        get { MessageHighlightColorStyle(rawValue: colorStyleRaw) ?? .readerYellow }
        set { colorStyleRaw = newValue.rawValue }
    }

    func syncIDsWithRelationships() {
        if let message {
            messageID = message.id
        }
        if let conversation {
            conversationID = conversation.id
        }
    }

    func makeSnapshot() -> MessageHighlightSnapshot {
        return MessageHighlightSnapshot(
            id: id,
            messageID: messageID,
            contextThreadID: contextThreadID,
            anchorID: anchorID,
            selectedText: selectedText,
            prefixContext: prefixContext,
            suffixContext: suffixContext,
            startOffset: startOffset,
            endOffset: endOffset,
            colorStyle: colorStyle,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
