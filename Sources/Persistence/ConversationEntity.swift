import Foundation
import SwiftData

/// Conversation entity (SwiftData)
@Model
final class ConversationEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var isStarred: Bool?
    var artifactsEnabled: Bool?
    var titleEditedByUser: Bool?
    var createdAt: Date
    var updatedAt: Date
    var systemPrompt: String?
    var providerID: String
    var modelID: String
    var modelConfigData: Data // Codable GenerationControls
    /// Denormalized `messages.count`. The sidebar needs "has messages" for
    /// every conversation on every body evaluation; testing the to-many
    /// relationship faults every conversation's message rows each time.
    /// `nil` (rows from before this attribute existed) falls back to the
    /// relationship until post-launch maintenance backfills it.
    var messageCount: Int?
    /// Denormalized `computedActivityDate()`. The sidebar sorts and groups every
    /// conversation by activity on every body evaluation; deriving it from the
    /// to-many relationship issued one SQL fetch *per conversation* and blocked
    /// the main thread for hundreds of milliseconds on every SwiftData save.
    /// `nil` (rows from before this attribute existed) falls back to the
    /// relationship until post-launch maintenance backfills it.
    var lastActivityAt: Date?

    @Relationship var assistant: AssistantEntity?

    @Relationship(deleteRule: .cascade, inverse: \MessageEntity.conversation)
    var messages: [MessageEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \MessageHighlightEntity.conversation)
    var messageHighlights: [MessageHighlightEntity] = []

    init(
        id: UUID = UUID(),
        title: String,
        isStarred: Bool = false,
        artifactsEnabled: Bool? = nil,
        titleEditedByUser: Bool? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        systemPrompt: String? = nil,
        providerID: String,
        modelID: String,
        modelConfigData: Data,
        assistant: AssistantEntity? = nil
    ) {
        self.id = id
        self.title = title
        self.isStarred = isStarred
        self.artifactsEnabled = artifactsEnabled
        self.titleEditedByUser = titleEditedByUser
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.systemPrompt = systemPrompt
        self.providerID = providerID
        self.modelID = modelID
        self.modelConfigData = modelConfigData
        self.assistant = assistant
        self.messageCount = 0
        // Deliberately left nil: seeding it here would make a stale stored
        // value authoritative for any conversation whose `messages` were
        // assigned without going through `refreshMessageCount()`. Nil reads
        // fall back to the relationship (empty and cheap for a new row) until
        // the first message append refreshes it.
    }

    var resolvedMessageCount: Int {
        messageCount ?? messages.count
    }

    /// Call after any mutation of `messages`. Recomputing from the
    /// relationship at mutation time is cheap (the messages are already
    /// resident there) and cannot drift.
    ///
    /// Both derived fields refresh together on purpose: they are backed by the
    /// same relationship, and a site that updates only one is exactly how a
    /// stale sidebar ordering would creep back in.
    func refreshMessageCount() {
        messageCount = messages.count
        lastActivityAt = computedActivityDate()
    }

    /// Sort/group key for the sidebar: when the user last *said* something,
    /// falling back to the last message of any role, then to creation.
    ///
    /// Faults `messages`. Only call it where they are already resident (a
    /// mutation site) or as the un-backfilled fallback — never in a loop over
    /// every conversation.
    func computedActivityDate() -> Date {
        latestMessageTimestamp(userOnly: true)
            ?? latestMessageTimestamp(userOnly: false)
            ?? createdAt
    }

    private func latestMessageTimestamp(userOnly: Bool) -> Date? {
        var latest: Date?
        for message in messages {
            if userOnly, message.role != MessageRole.user.rawValue { continue }
            if let current = latest {
                if message.timestamp > current { latest = message.timestamp }
            } else {
                latest = message.timestamp
            }
        }
        return latest
    }

    /// Convert to domain model
    func toDomain() throws -> Conversation {
        let decoder = JSONDecoder()
        let controls = try decoder.decode(GenerationControls.self, from: modelConfigData)

        return Conversation(
            id: id,
            title: title,
            systemPrompt: systemPrompt,
            artifactsEnabled: artifactsEnabled == true,
            messages: try messages.sorted(by: { $0.timestamp < $1.timestamp }).map { try $0.toDomain() },
            modelConfig: ModelConfig(providerID: providerID, modelID: modelID, controls: controls),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Create from domain model
    static func fromDomain(_ conversation: Conversation) throws -> ConversationEntity {
        let encoder = JSONEncoder()
        let modelConfigData = try encoder.encode(conversation.modelConfig.controls)

        return ConversationEntity(
            id: conversation.id,
            title: conversation.title,
            artifactsEnabled: conversation.artifactsEnabled,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            systemPrompt: conversation.systemPrompt,
            providerID: conversation.modelConfig.providerID,
            modelID: conversation.modelConfig.modelID,
            modelConfigData: modelConfigData
        )
    }
}
