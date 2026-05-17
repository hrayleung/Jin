import Foundation

struct QuoteContent: Codable, Sendable, Hashable {
    let sourceMessageID: UUID?
    let sourceRole: MessageRole?
    let sourceModelName: String?
    let sourceProviderIconID: String?
    let quotedText: String
    let prefixContext: String?
    let suffixContext: String?
    let createdAt: Date

    init(
        sourceMessageID: UUID? = nil,
        sourceRole: MessageRole? = nil,
        sourceModelName: String? = nil,
        sourceProviderIconID: String? = nil,
        quotedText: String,
        prefixContext: String? = nil,
        suffixContext: String? = nil,
        createdAt: Date = Date()
    ) {
        self.sourceMessageID = sourceMessageID
        self.sourceRole = sourceRole
        self.sourceModelName = sourceModelName
        self.sourceProviderIconID = sourceProviderIconID
        self.quotedText = quotedText
        self.prefixContext = prefixContext
        self.suffixContext = suffixContext
        self.createdAt = createdAt
    }
}
