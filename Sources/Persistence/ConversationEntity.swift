import Foundation
import SwiftData

/// Conversation entity (SwiftData)
@Model
final class ConversationEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var isStarred: Bool?
    var artifactsEnabled: Bool?
    var createdAt: Date
    var updatedAt: Date
    var systemPrompt: String?
    /// Legacy compatibility snapshot of the currently active thread's provider.
    var providerID: String
    /// Legacy compatibility snapshot of the currently active thread's model.
    var modelID: String
    /// Legacy compatibility snapshot of the currently active thread's controls.
    var modelConfigData: Data // Codable GenerationControls
    /// Currently active model thread for composer/send.
    var activeThreadID: UUID?

    @Relationship var assistant: AssistantEntity?

    @Relationship(deleteRule: .cascade, inverse: \MessageEntity.conversation)
    var messages: [MessageEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \ConversationModelThreadEntity.conversation)
    var modelThreads: [ConversationModelThreadEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \MessageHighlightEntity.conversation)
    var messageHighlights: [MessageHighlightEntity] = []

    init(
        id: UUID = UUID(),
        title: String,
        isStarred: Bool = false,
        artifactsEnabled: Bool? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        systemPrompt: String? = nil,
        providerID: String,
        modelID: String,
        modelConfigData: Data,
        activeThreadID: UUID? = nil,
        assistant: AssistantEntity? = nil
    ) {
        self.id = id
        self.title = title
        self.isStarred = isStarred
        self.artifactsEnabled = artifactsEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.systemPrompt = systemPrompt
        self.providerID = providerID
        self.modelID = modelID
        self.modelConfigData = modelConfigData
        self.activeThreadID = activeThreadID
        self.assistant = assistant
    }

    /// Convert to domain model
    func toDomain() throws -> Conversation {
        let decoder = JSONDecoder()
        let threadByID = Dictionary(uniqueKeysWithValues: modelThreads.map { ($0.id, $0) })
        let activeThread = activeThreadID.flatMap { threadByID[$0] } ?? modelThreads.first

        let effectiveProviderID = activeThread?.providerID ?? providerID
        let effectiveModelID = activeThread?.modelID ?? modelID
        let effectiveModelConfigData = activeThread?.modelConfigData ?? modelConfigData

        let controls = try decoder.decode(GenerationControls.self, from: effectiveModelConfigData)

        let modelConfig = ModelConfig(
            providerID: effectiveProviderID,
            modelID: effectiveModelID,
            controls: controls
        )

        return Conversation(
            id: id,
            title: title,
            systemPrompt: systemPrompt,
            artifactsEnabled: artifactsEnabled == true,
            messages: try messages.sorted(by: { $0.timestamp < $1.timestamp }).map { try $0.toDomain() },
            modelConfig: modelConfig,
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
