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
        layoutWidthBucket: Int,
        layoutCenterOffsetBucket: Int,
        allMessageCount: Int,
        lastMessageID: UUID?,
        messageRenderLimit: Int,
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
        textToSpeechEnabled: Bool = false,
        textToSpeechConfigured: Bool = false,
        textToSpeechPlaybackState: TextToSpeechPlaybackManager.State = .idle,
        expandedCollapsedMessageIDs: Set<UUID>
    ) -> ChatStageEquatableKey {
        ChatStageEquatableKey(
            conversationID: conversationID,
            conversationMessageCount: conversationMessageCount,
            renderRevision: renderRevision,
            viewportHeight: viewportHeight,
            layoutWidthBucket: layoutWidthBucket,
            layoutCenterOffsetBucket: layoutCenterOffsetBucket,
            allMessageCount: allMessageCount,
            lastMessageID: lastMessageID,
            messageRenderLimit: messageRenderLimit,
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
            textToSpeechEnabled: textToSpeechEnabled,
            textToSpeechConfigured: textToSpeechConfigured,
            textToSpeechPlaybackState: textToSpeechPlaybackState,
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
    let layoutWidthBucket: Int
    let layoutCenterOffsetBucket: Int
    let allMessageCount: Int
    let lastMessageID: UUID?
    // Visible-window size for the single-thread stage. Without this, clicking
    // "Load N earlier messages" updates the upstream binding but the EquatableView
    // wrapper short-circuits the re-render because every other field is unchanged.
    let messageRenderLimit: Int
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
    // EquatableView in the stage skips re-renders when the key is unchanged.
    // Without these, toggling/configuring the TTS plugin updates ChatView's
    // @State but the footer stays disabled because the cached subtree never
    // re-evaluates with the new interaction values. The playback state is
    // also required so the speaker icon flips back to idle when the mini
    // player's close button stops playback — `interaction`'s closures read
    // the new value, but EquatableView won't call them without a key change.
    let textToSpeechEnabled: Bool
    let textToSpeechConfigured: Bool
    let textToSpeechPlaybackState: TextToSpeechPlaybackManager.State
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
