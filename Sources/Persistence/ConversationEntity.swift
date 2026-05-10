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
    /// Dead snapshot of the active thread's provider. Production code reads
    /// the active `ConversationModelThreadEntity` directly via
    /// `ChatView.activeProviderID` / `ContentView.activeProviderID(for:)`.
    /// Retained only so the SwiftData column is not dropped without a
    /// versioned schema migration; remove once `JinSchemaV2` lands.
    var providerID: String
    /// Dead snapshot — see `providerID` above.
    var modelID: String
    /// Dead snapshot — see `providerID` above.
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
        let sortedThreads = modelThreads.sorted { lhs, rhs in
            if lhs.displayOrder != rhs.displayOrder {
                return lhs.displayOrder < rhs.displayOrder
            }
            return lhs.createdAt < rhs.createdAt
        }

        var domainThreads: [ModelThread] = []
        domainThreads.reserveCapacity(sortedThreads.count)
        for thread in sortedThreads {
            let controls = try decoder.decode(GenerationControls.self, from: thread.modelConfigData)
            domainThreads.append(
                ModelThread(
                    id: thread.id,
                    providerID: thread.providerID,
                    modelID: thread.modelID,
                    controls: controls,
                    displayOrder: thread.displayOrder,
                    isSelected: thread.isSelected,
                    isPrimary: thread.isPrimary
                )
            )
        }

        // Migration safety net: a `ConversationEntity` predating multi-model
        // support has no rows in `modelThreads`. Materialize a primary thread
        // from the legacy fields so the domain model is always populated.
        if domainThreads.isEmpty {
            let controls = try decoder.decode(GenerationControls.self, from: modelConfigData)
            domainThreads.append(
                ModelThread(
                    providerID: providerID,
                    modelID: modelID,
                    controls: controls,
                    isPrimary: true
                )
            )
        }

        let resolvedActiveThreadID = activeThreadID.flatMap { id in
            domainThreads.contains(where: { $0.id == id }) ? id : nil
        } ?? domainThreads.first?.id

        return Conversation(
            id: id,
            title: title,
            systemPrompt: systemPrompt,
            artifactsEnabled: artifactsEnabled == true,
            messages: try messages.sorted(by: { $0.timestamp < $1.timestamp }).map { try $0.toDomain() },
            threads: domainThreads,
            activeThreadID: resolvedActiveThreadID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Create from domain model
    static func fromDomain(_ conversation: Conversation) throws -> ConversationEntity {
        let encoder = JSONEncoder()
        let activeThread = conversation.activeThread
        let modelConfigData = try encoder.encode(activeThread?.controls ?? GenerationControls())

        return ConversationEntity(
            id: conversation.id,
            title: conversation.title,
            artifactsEnabled: conversation.artifactsEnabled,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            systemPrompt: conversation.systemPrompt,
            providerID: activeThread?.providerID ?? "",
            modelID: activeThread?.modelID ?? "",
            modelConfigData: modelConfigData,
            activeThreadID: conversation.activeThreadID
        )
    }
}
