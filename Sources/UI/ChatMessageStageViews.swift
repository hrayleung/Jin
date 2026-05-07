import SwiftUI

struct ChatSingleThreadMessagesView: View {
    let conversationID: UUID
    let conversationMessageCount: Int
    let renderRevision: Int
    let containerSize: CGSize
    let visibleContainerWidth: CGFloat
    let layoutCenterOffset: CGFloat
    let allMessages: [MessageRenderItem]
    let toolResultsByCallID: [String: ToolResult]
    let messageEntitiesByID: [UUID: MessageEntity]
    let assistantDisplayName: String
    let providerType: ProviderType?
    let providerIconID: String?
    let composerHeight: CGFloat
    let isStreaming: Bool
    let streamingMessage: StreamingMessageState?
    let streamingModelLabel: String?
    let streamingModelID: String?
    let messageRenderPageSize: Int
    let eagerCodeHighlightTailCount: Int
    let nonLazyMessageStackThreshold: Int
    let pinnedBottomRefreshDelays: [TimeInterval]
    let interaction: ChatMessageInteractionContext
    let onStreamingFinished: () -> Void
    let onActivateMessageThread: (UUID) -> Void
    let onOpenArtifact: (RenderedArtifactVersion, UUID?) -> Void
    let expandedCollapsedMessageIDs: Binding<Set<UUID>>
    @Binding var messageRenderLimit: Int
    @Binding var pendingRestoreScrollMessageID: UUID?
    @Binding var isPinnedToBottom: Bool
    @Binding var pinnedBottomRefreshGeneration: Int
    @State private var lastMeasuredContentHeight: CGFloat = 0
    @State private var pendingPinnedBottomRefreshTask: Task<Void, Never>?
    @State private var shouldMaintainPinnedBottomAnchor = true
    @State private var isUserScrollInProgress = false

    private var visibleMessagesForWindow: [MessageRenderItem] {
        timelineWindow.visibleMessages
    }

    private var timelineWindow: ChatMessageStagePresentationSupport.TimelineWindow {
        ChatMessageStagePresentationSupport.TimelineWindow(
            messages: allMessages,
            renderLimit: messageRenderLimit,
            pageSize: messageRenderPageSize,
            eagerCodeHighlightTailCount: eagerCodeHighlightTailCount,
            nonLazyMessageStackThreshold: nonLazyMessageStackThreshold
        )
    }

    private var equatableKey: ChatStageEquatableKey {
        ChatMessageStageEquatableKeyBuilder.singleThreadKey(
            conversationID: conversationID,
            conversationMessageCount: conversationMessageCount,
            renderRevision: renderRevision,
            viewportHeight: containerSize.height,
            layoutWidthBucket: ChatConversationLayoutMetrics.layoutWidthBucket(for: visibleContainerWidth),
            layoutCenterOffsetBucket: Int(layoutCenterOffset.rounded(.toNearestOrAwayFromZero)),
            allMessageCount: allMessages.count,
            lastMessageID: allMessages.last?.id,
            toolResultCount: toolResultsByCallID.count,
            entityCount: messageEntitiesByID.count,
            assistantDisplayName: assistantDisplayName,
            providerType: providerType,
            providerIconID: providerIconID,
            composerHeight: composerHeight,
            isStreaming: isStreaming,
            streamingObjectID: streamingMessage.map(ObjectIdentifier.init),
            streamingModelLabel: streamingModelLabel,
            streamingModelID: streamingModelID,
            editingUserMessageID: interaction.editingUserMessageID,
            editSlashCommandKey: ChatEditSlashCommandEquatableKey(context: interaction.editSlashCommand),
            expandedCollapsedMessageIDs: expandedCollapsedMessageIDs.wrappedValue
        )
    }

    var body: some View {
        EquatableView(content: ChatSingleThreadMessagesContentView(
            key: equatableKey,
            conversationID: conversationID,
            visibleMessagesForWindow: visibleMessagesForWindow,
            allMessageCount: allMessages.count,
            messageRenderPageSize: messageRenderPageSize,
            eagerCodeHighlightTailCount: eagerCodeHighlightTailCount,
            nonLazyMessageStackThreshold: nonLazyMessageStackThreshold,
            containerSize: containerSize,
            visibleContainerWidth: visibleContainerWidth,
            layoutCenterOffset: layoutCenterOffset,
            composerHeight: composerHeight,
            isStreaming: isStreaming,
            streamingMessage: streamingMessage,
            streamingModelLabel: streamingModelLabel,
            streamingModelID: streamingModelID,
            assistantDisplayName: assistantDisplayName,
            providerType: providerType,
            providerIconID: providerIconID,
            toolResultsByCallID: toolResultsByCallID,
            messageEntitiesByID: messageEntitiesByID,
            pinnedBottomRefreshDelays: pinnedBottomRefreshDelays,
            interaction: interaction,
            onStreamingFinished: onStreamingFinished,
            onActivateMessageThread: onActivateMessageThread,
            onOpenArtifact: onOpenArtifact,
            timelineWindow: timelineWindow,
            expandedCollapsedMessageIDs: expandedCollapsedMessageIDs,
            messageRenderLimit: $messageRenderLimit,
            pendingRestoreScrollMessageID: $pendingRestoreScrollMessageID,
            isPinnedToBottom: $isPinnedToBottom,
            pinnedBottomRefreshGeneration: $pinnedBottomRefreshGeneration,
            lastMeasuredContentHeight: $lastMeasuredContentHeight,
            pendingPinnedBottomRefreshTask: $pendingPinnedBottomRefreshTask,
            shouldMaintainPinnedBottomAnchor: $shouldMaintainPinnedBottomAnchor,
            isUserScrollInProgress: $isUserScrollInProgress
        ))
    }
}
