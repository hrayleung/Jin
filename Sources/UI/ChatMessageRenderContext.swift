import SwiftUI

struct ChatThreadRenderContext {
    let visibleMessages: [MessageRenderItem]
    let historyMessages: [Message]
    let messageEntitiesByID: [UUID: MessageEntity]
    let toolResultsByCallID: [String: ToolResult]
    let artifactCatalog: ArtifactCatalog
}

struct ChatDecodedRenderContext: Sendable {
    let visibleMessages: [MessageRenderItem]
    let historyMessages: [Message]
    let toolResultsByCallID: [String: ToolResult]
    let artifactCatalog: ArtifactCatalog
}

struct EditSlashCommandContext {
    let servers: [SlashCommandMCPServerItem]
    let isActive: Bool
    let filterText: String
    let highlightedIndex: Int
    let perMessageChips: [SlashCommandMCPServerItem]
    let onSelectServer: (String) -> Void
    let onDismiss: () -> Void
    let onRemovePerMessageServer: (String) -> Void
    let onInterceptKeyDown: ((UInt16) -> Bool)?

    static let inactive = EditSlashCommandContext(
        servers: [],
        isActive: false,
        filterText: "",
        highlightedIndex: 0,
        perMessageChips: [],
        onSelectServer: { _ in },
        onDismiss: {},
        onRemovePerMessageServer: { _ in },
        onInterceptKeyDown: nil
    )
}

struct ChatMessageInteractionContext {
    let textToSpeechEnabled: Bool
    let textToSpeechConfigured: Bool
    let editingUserMessageID: UUID?
    let editingUserMessageText: Binding<String>
    let editingUserMessageFocused: Binding<Bool>
    let textToSpeechIsGenerating: (UUID) -> Bool
    let textToSpeechIsPlaying: (UUID) -> Bool
    let textToSpeechIsPaused: (UUID) -> Bool
    let onToggleSpeakAssistantMessage: (MessageEntity, String) -> Void
    let onStopSpeakAssistantMessage: (MessageEntity) -> Void
    let onRegenerate: (MessageEntity) -> Void
    let onEditUserMessage: (MessageEntity) -> Void
    let onSubmitUserEdit: (MessageEntity) -> Void
    let onCancelUserEdit: () -> Void
    let onDeleteMessage: (MessageEntity) -> Void
    let onDeleteResponse: (MessageEntity) -> Void
    let onQuoteSelection: (MessageSelectionSnapshot, String?) -> Void
    let onCreateHighlight: (MessageSelectionSnapshot) -> Void
    let onRemoveHighlights: ([UUID]) -> Void
    let editSlashCommand: EditSlashCommandContext
}
