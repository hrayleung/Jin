import Foundation

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
        updatedAt: Date? = nil
    ) {
        let initialUpdatedAt = updatedAt ?? createdAt
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
        self.updatedAt = initialUpdatedAt
    }
}
