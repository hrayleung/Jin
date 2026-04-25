import SwiftUI

struct ChatEditSlashCommandEquatableKey: Equatable {
    let isActive: Bool
    let filterText: String
    let highlightedIndex: Int
    let servers: [SlashCommandMCPServerItem]
    let perMessageChips: [SlashCommandMCPServerItem]

    static let inactive = ChatEditSlashCommandEquatableKey(
        isActive: false,
        filterText: "",
        highlightedIndex: 0,
        servers: [],
        perMessageChips: []
    )

    init(context: EditSlashCommandContext) {
        isActive = context.isActive
        filterText = context.isActive ? context.filterText : ""
        highlightedIndex = context.isActive ? context.highlightedIndex : 0
        servers = context.isActive ? context.servers : []
        perMessageChips = context.perMessageChips
    }

    private init(
        isActive: Bool,
        filterText: String,
        highlightedIndex: Int,
        servers: [SlashCommandMCPServerItem],
        perMessageChips: [SlashCommandMCPServerItem]
    ) {
        self.isActive = isActive
        self.filterText = filterText
        self.highlightedIndex = highlightedIndex
        self.servers = servers
        self.perMessageChips = perMessageChips
    }
}

enum ChatMessageStageEquatableKeyBuilder {
    static func singleThreadKey(
        conversationID: UUID,
        conversationMessageCount: Int,
        renderRevision: Int,
        viewportHeight: CGFloat,
        allMessageCount: Int,
        lastMessageID: UUID?,
        toolResultCount: Int,
        entityCount: Int,
        assistantDisplayName: String,
        providerType: ProviderType?,
        providerIconID: String?,
        composerHeight: CGFloat,
        isStreaming: Bool,
        streamingObjectID: ObjectIdentifier?,
        streamingModelLabel: String?,
        streamingModelID: String?,
        editingUserMessageID: UUID? = nil,
        editSlashCommandKey: ChatEditSlashCommandEquatableKey = .inactive,
        expandedCollapsedMessageIDs: Set<UUID>
    ) -> ChatStageEquatableKey {
        ChatStageEquatableKey(
            conversationID: conversationID,
            conversationMessageCount: conversationMessageCount,
            renderRevision: renderRevision,
            viewportHeight: viewportHeight,
            allMessageCount: allMessageCount,
            lastMessageID: lastMessageID,
            toolResultCount: toolResultCount,
            entityCount: entityCount,
            assistantDisplayName: assistantDisplayName,
            providerType: providerType,
            providerIconID: providerIconID,
            composerHeight: composerHeight,
            isStreaming: isStreaming,
            streamingObjectID: streamingObjectID,
            streamingModelLabel: streamingModelLabel,
            streamingModelID: streamingModelID,
            editingUserMessageID: editingUserMessageID,
            editSlashCommandKey: editSlashCommandKey,
            activeThreadID: nil,
            threadIDs: [],
            contextKeysByThreadID: [:],
            expandedCollapsedMessageIDs: expandedCollapsedMessageIDs
        )
    }
}
struct ChatStageEquatableKey: Equatable {
    let conversationID: UUID?
    let conversationMessageCount: Int
    let renderRevision: Int
    let viewportHeight: CGFloat
    let allMessageCount: Int
    let lastMessageID: UUID?
    let toolResultCount: Int
    let entityCount: Int
    let assistantDisplayName: String
    let providerType: ProviderType?
    let providerIconID: String?
    let composerHeight: CGFloat
    let isStreaming: Bool
    let streamingObjectID: ObjectIdentifier?
    let streamingModelLabel: String?
    let streamingModelID: String?
    let editingUserMessageID: UUID?
    let editSlashCommandKey: ChatEditSlashCommandEquatableKey
    let activeThreadID: UUID?
    let threadIDs: [UUID]
    let contextKeysByThreadID: [UUID: ChatThreadContextEquatableKey]
    let expandedCollapsedMessageIDs: Set<UUID>
}

struct ChatThreadContextEquatableKey: Equatable {
    let messageIDs: [UUID]
    let toolResultIDs: [String]
    let entityIDs: [UUID]
    let artifactLatestID: String?
    let artifactLatestVersion: Int?
}

extension ChatThreadRenderContext {
    var equatableKey: ChatThreadContextEquatableKey {
        ChatThreadContextEquatableKey(
            messageIDs: visibleMessages.map(\.id),
            toolResultIDs: toolResultsByCallID.keys.sorted(),
            entityIDs: messageEntitiesByID.keys.sorted { $0.uuidString < $1.uuidString },
            artifactLatestID: artifactCatalog.latestVersion?.artifactID,
            artifactLatestVersion: artifactCatalog.latestVersion?.version
        )
    }
}
