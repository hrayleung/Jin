import Foundation

enum MessageHighlightColorStyle: String, Codable, Sendable, Hashable {
    case readerYellow
}

struct QuoteContent: Codable, Sendable, Hashable {
    let sourceMessageID: UUID
    let sourceThreadID: UUID?
    let sourceRole: MessageRole
    let sourceModelName: String?
    let quotedText: String
    let prefixContext: String?
    let suffixContext: String?
    let createdAt: Date

    init(
        sourceMessageID: UUID,
        sourceThreadID: UUID? = nil,
        sourceRole: MessageRole,
        sourceModelName: String? = nil,
        quotedText: String,
        prefixContext: String? = nil,
        suffixContext: String? = nil,
        createdAt: Date = Date()
    ) {
        self.sourceMessageID = sourceMessageID
        self.sourceThreadID = sourceThreadID
        self.sourceRole = sourceRole
        self.sourceModelName = sourceModelName
        self.quotedText = quotedText
        self.prefixContext = prefixContext
        self.suffixContext = suffixContext
        self.createdAt = createdAt
    }
}

struct MessageHighlightSnapshot: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let messageID: UUID
    let contextThreadID: UUID?
    let anchorID: String
    let selectedText: String
    let prefixContext: String?
    let suffixContext: String?
    let startOffset: Int
    let endOffset: Int
    let colorStyle: MessageHighlightColorStyle
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        messageID: UUID,
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
        self.contextThreadID = contextThreadID
        self.anchorID = anchorID
        self.selectedText = selectedText
        self.prefixContext = prefixContext
        self.suffixContext = suffixContext
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.colorStyle = colorStyle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
