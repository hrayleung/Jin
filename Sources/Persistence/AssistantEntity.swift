import Foundation
import SwiftData

/// Assistant entity (SwiftData)
@Model
final class AssistantEntity {
    @Attribute(.unique) var id: String
    var name: String
    var icon: String?
    var assistantDescription: String?
    var systemInstruction: String
    var temperature: Double
    var maxOutputTokens: Int?
    /// `nil` means "default".
    var truncateMessages: Bool?
    /// Maximum number of messages to keep in history (nil = unlimited)
    var maxHistoryMessages: Int?
    /// `nil` means "default".
    var replyLanguage: String?
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int

    @Relationship(deleteRule: .cascade, inverse: \ConversationEntity.assistant)
    var conversations: [ConversationEntity] = []

    init(
        id: String,
        name: String,
        icon: String? = nil,
        assistantDescription: String? = nil,
        systemInstruction: String = "",
        temperature: Double = 0.1,
        maxOutputTokens: Int? = nil,
        truncateMessages: Bool? = nil,
        maxHistoryMessages: Int? = nil,
        replyLanguage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.assistantDescription = assistantDescription
        self.systemInstruction = systemInstruction
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.truncateMessages = truncateMessages
        self.maxHistoryMessages = maxHistoryMessages
        self.replyLanguage = replyLanguage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
    }
}
