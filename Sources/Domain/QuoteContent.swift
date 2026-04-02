import Foundation

struct QuoteContent: Codable, Sendable, Hashable {
    let sourceMessageID: UUID?
    let sourceThreadID: UUID?
    let sourceRole: MessageRole?
    let sourceModelName: String?
    let quotedText: String
    let prefixContext: String?
    let suffixContext: String?
    let createdAt: Date

    init(
        sourceMessageID: UUID? = nil,
        sourceThreadID: UUID? = nil,
        sourceRole: MessageRole? = nil,
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
