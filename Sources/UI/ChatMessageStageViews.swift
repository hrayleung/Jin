import SwiftUI

struct ChatThreadRenderContext {
    let visibleMessages: [MessageRenderItem]
    let messageEntitiesByID: [UUID: MessageEntity]
    let toolResultsByCallID: [String: ToolResult]
    let artifactCatalog: ArtifactCatalog
}

struct ChatDecodedRenderContext: Sendable {
    let visibleMessages: [MessageRenderItem]
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
    let actionsEnabled: Bool
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
    let editSlashCommand: EditSlashCommandContext
}

struct ChatMessageTimelineView: View {
    let visibleMessages: [MessageRenderItem]
    let hiddenCount: Int
    let messageRenderPageSize: Int?
    let onLoadEarlier: (() -> Void)?
    let bubbleMaxWidth: CGFloat
    let assistantDisplayName: String
    let providerIconID: String?
    let eagerCodeHighlightStartIndex: Int
    let toolResultsByCallID: [String: ToolResult]
    let messageEntitiesByID: [UUID: MessageEntity]
    let interaction: ChatMessageInteractionContext
    let streamingMessage: StreamingMessageState?
    let streamingModelLabel: String?
    let bottomSpacerHeight: CGFloat
    let bottomID: String
    let onActivateThreadForMessage: (UUID?) -> Void
    let onActivateTimeline: () -> Void
    let onOpenArtifact: (RenderedArtifactVersion, UUID?) -> Void

    @ViewBuilder
    var body: some View {
        if hiddenCount > 0,
           let messageRenderPageSize,
           let onLoadEarlier {
            LoadEarlierMessagesRow(
                hiddenCount: hiddenCount,
                pageSize: messageRenderPageSize,
                onLoad: onLoadEarlier
            )
            .id("loadEarlier")
        }

        ForEach(Array(visibleMessages.enumerated()), id: \.element.id) { index, message in
            MessageRow(
                item: message,
                maxBubbleWidth: bubbleMaxWidth,
                assistantDisplayName: assistantDisplayName,
                providerIconID: providerIconID,
                deferCodeHighlightUpgrade: index < eagerCodeHighlightStartIndex,
                toolResultsByCallID: toolResultsByCallID,
                actionsEnabled: interaction.actionsEnabled,
                textToSpeechEnabled: interaction.textToSpeechEnabled,
                textToSpeechConfigured: interaction.textToSpeechConfigured,
                textToSpeechIsGenerating: interaction.textToSpeechIsGenerating(message.id),
                textToSpeechIsPlaying: interaction.textToSpeechIsPlaying(message.id),
                textToSpeechIsPaused: interaction.textToSpeechIsPaused(message.id),
                onToggleSpeakAssistantMessage: { messageID, text in
                    guard let entity = messageEntitiesByID[messageID] else { return }
                    interaction.onToggleSpeakAssistantMessage(entity, text)
                },
                onStopSpeakAssistantMessage: { messageID in
                    guard let entity = messageEntitiesByID[messageID] else { return }
                    interaction.onStopSpeakAssistantMessage(entity)
                },
                onRegenerate: { messageID in
                    guard let entity = messageEntitiesByID[messageID] else { return }
                    interaction.onRegenerate(entity)
                },
                onEditUserMessage: { messageID in
                    guard let entity = messageEntitiesByID[messageID] else { return }
                    interaction.onEditUserMessage(entity)
                },
                editingUserMessageID: interaction.editingUserMessageID,
                editingUserMessageText: interaction.editingUserMessageText,
                editingUserMessageFocused: interaction.editingUserMessageFocused,
                onSubmitUserEdit: { messageID in
                    guard let entity = messageEntitiesByID[messageID] else { return }
                    interaction.onSubmitUserEdit(entity)
                },
                onCancelUserEdit: interaction.onCancelUserEdit,
                editSlashCommand: interaction.editSlashCommand,
                onOpenArtifact: onOpenArtifact,
                onActivate: {
                    if let threadID = message.contextThreadID {
                        onActivateThreadForMessage(threadID)
                    } else {
                        onActivateTimeline()
                    }
                }
            )
            .id(message.id)
        }

        if let streamingMessage {
            StreamingMessageView(
                state: streamingMessage,
                maxBubbleWidth: bubbleMaxWidth,
                assistantDisplayName: assistantDisplayName,
                modelLabel: streamingModelLabel,
                providerIconID: providerIconID,
                onContentUpdate: { }
            )
            .id(bottomID == "bottom" ? "streaming" : "streaming-\(bottomID)")
        }

        Color.clear
            .frame(height: bottomSpacerHeight)
            .id(bottomID)
    }
}

struct ChatSingleThreadMessagesView: View {
    let conversationID: UUID
    let conversationMessageCount: Int
    let containerSize: CGSize
    let allMessages: [MessageRenderItem]
    let toolResultsByCallID: [String: ToolResult]
    let messageEntitiesByID: [UUID: MessageEntity]
    let assistantDisplayName: String
    let providerIconID: String?
    let composerHeight: CGFloat
    let isStreaming: Bool
    let streamingMessage: StreamingMessageState?
    let streamingModelLabel: String?
    let messageRenderPageSize: Int
    let eagerCodeHighlightTailCount: Int
    let nonLazyMessageStackThreshold: Int
    let pinnedBottomRefreshDelays: [TimeInterval]
    let interaction: ChatMessageInteractionContext
    let onStreamingFinished: () -> Void
    let onActivateMessageThread: (UUID) -> Void
    let onOpenArtifact: (RenderedArtifactVersion, UUID?) -> Void
    @Binding var messageRenderLimit: Int
    @Binding var pendingRestoreScrollMessageID: UUID?
    @Binding var isPinnedToBottom: Bool
    @Binding var pinnedBottomRefreshGeneration: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                let usableWidth = max(0, containerSize.width - 32)
                let bubbleMaxWidth = max(260, usableWidth * 0.78)
                let visibleMessages = Array(allMessages.suffix(messageRenderLimit))
                let hiddenCount = allMessages.count - visibleMessages.count
                let eagerCodeHighlightStartIndex = max(0, visibleMessages.count - eagerCodeHighlightTailCount)
                let useLazyMessageStack = visibleMessages.count > nonLazyMessageStackThreshold

                Group {
                    if useLazyMessageStack {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            timelineView(
                                visibleMessages: visibleMessages,
                                hiddenCount: hiddenCount,
                                bubbleMaxWidth: bubbleMaxWidth,
                                eagerCodeHighlightStartIndex: eagerCodeHighlightStartIndex
                            )
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            timelineView(
                                visibleMessages: visibleMessages,
                                hiddenCount: hiddenCount,
                                bubbleMaxWidth: bubbleMaxWidth,
                                eagerCodeHighlightStartIndex: eagerCodeHighlightStartIndex
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .frame(minHeight: containerSize.height, alignment: .bottom)
            }
            .defaultScrollAnchor(.bottom)
            .overlay(alignment: .bottomTrailing) {
                if !isPinnedToBottom {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(.regularMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 20)
                    .padding(.bottom, 34)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isPinnedToBottom)
            .onScrollPinChange(isPinned: $isPinnedToBottom)
            .onChange(of: messageRenderLimit) { _, _ in
                guard let restoreID = pendingRestoreScrollMessageID else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(restoreID, anchor: .top)
                    pendingRestoreScrollMessageID = nil
                }
            }
            .onChange(of: conversationMessageCount) { _, _ in
                refreshPinnedBottomIfNeeded(proxy: proxy)
            }
            .onChange(of: isStreaming) { wasStreaming, nowStreaming in
                guard wasStreaming, !nowStreaming else { return }
                onStreamingFinished()
                refreshPinnedBottomIfNeeded(proxy: proxy)
            }
            .onChange(of: conversationID) { _, _ in
                DispatchQueue.main.async {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func timelineView(
        visibleMessages: [MessageRenderItem],
        hiddenCount: Int,
        bubbleMaxWidth: CGFloat,
        eagerCodeHighlightStartIndex: Int
    ) -> some View {
        ChatMessageTimelineView(
            visibleMessages: visibleMessages,
            hiddenCount: hiddenCount,
            messageRenderPageSize: messageRenderPageSize,
            onLoadEarlier: {
                guard let firstVisible = visibleMessages.first else { return }
                pendingRestoreScrollMessageID = firstVisible.id
                messageRenderLimit = min(allMessages.count, messageRenderLimit + messageRenderPageSize)
            },
            bubbleMaxWidth: bubbleMaxWidth,
            assistantDisplayName: assistantDisplayName,
            providerIconID: providerIconID,
            eagerCodeHighlightStartIndex: eagerCodeHighlightStartIndex,
            toolResultsByCallID: toolResultsByCallID,
            messageEntitiesByID: messageEntitiesByID,
            interaction: interaction,
            streamingMessage: streamingMessage,
            streamingModelLabel: streamingModelLabel,
            bottomSpacerHeight: composerHeight + 24,
            bottomID: "bottom",
            onActivateThreadForMessage: { threadID in
                guard let threadID else { return }
                onActivateMessageThread(threadID)
            },
            onActivateTimeline: { },
            onOpenArtifact: onOpenArtifact
        )
    }

    private func refreshPinnedBottomIfNeeded(proxy: ScrollViewProxy) {
        guard isPinnedToBottom else { return }
        pinnedBottomRefreshGeneration &+= 1
        let refreshGeneration = pinnedBottomRefreshGeneration

        for delay in pinnedBottomRefreshDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard refreshGeneration == pinnedBottomRefreshGeneration else { return }
                guard isPinnedToBottom else { return }
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}

struct ChatMultiModelStageView: View {
    let conversationMessageCount: Int
    let containerSize: CGSize
    let threads: [ConversationModelThreadEntity]
    let contextsByThreadID: [UUID: ChatThreadRenderContext]
    let assistantDisplayName: String
    let composerHeight: CGFloat
    let isStreaming: Bool
    let activeThreadID: UUID?
    let initialMessageRenderLimit: Int
    let messageRenderPageSize: Int
    let eagerCodeHighlightTailCount: Int
    let nonLazyMessageStackThreshold: Int
    let interaction: ChatMessageInteractionContext
    let modelNameForThread: (ConversationModelThreadEntity) -> String
    let providerIconIDForProviderID: (String) -> String?
    let streamingMessageForThread: (UUID) -> StreamingMessageState?
    let streamingModelLabelForThread: (UUID) -> String?
    let onActivateThread: (UUID) -> Void
    let onOpenArtifact: (RenderedArtifactVersion, UUID?) -> Void

    var body: some View {
        let horizontalPadding: CGFloat = 20
        let spacing: CGFloat = 12
        let availableWidth = max(0, containerSize.width - (horizontalPadding * 2) - (spacing * CGFloat(max(threads.count - 1, 0))))
        let columnWidth = max(320, availableWidth / CGFloat(max(threads.count, 1)))

        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: spacing) {
                ForEach(threads) { thread in
                    if let context = contextsByThreadID[thread.id] {
                        ChatMultiModelThreadColumnView(
                            conversationMessageCount: conversationMessageCount,
                            thread: thread,
                            context: context,
                            columnWidth: columnWidth,
                            containerHeight: containerSize.height,
                            assistantDisplayName: assistantDisplayName,
                            providerIconID: providerIconIDForProviderID(thread.providerID),
                            threadTitle: modelNameForThread(thread),
                            composerHeight: composerHeight,
                            isStreaming: isStreaming,
                            isActive: activeThreadID == thread.id,
                            initialMessageRenderLimit: initialMessageRenderLimit,
                            messageRenderPageSize: messageRenderPageSize,
                            eagerCodeHighlightTailCount: eagerCodeHighlightTailCount,
                            nonLazyMessageStackThreshold: nonLazyMessageStackThreshold,
                            interaction: interaction,
                            streamingMessage: streamingMessageForThread(thread.id),
                            streamingModelLabel: streamingModelLabelForThread(thread.id),
                            onActivateThread: { onActivateThread(thread.id) },
                            onOpenArtifact: onOpenArtifact
                        )
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 16)
            .frame(minHeight: containerSize.height, alignment: .bottomLeading)
        }
    }
}

private struct ChatMultiModelThreadColumnView: View {
    let conversationMessageCount: Int
    let thread: ConversationModelThreadEntity
    let context: ChatThreadRenderContext
    let columnWidth: CGFloat
    let containerHeight: CGFloat
    let assistantDisplayName: String
    let providerIconID: String?
    let threadTitle: String
    let composerHeight: CGFloat
    let isStreaming: Bool
    let isActive: Bool
    let initialMessageRenderLimit: Int
    let messageRenderPageSize: Int
    let eagerCodeHighlightTailCount: Int
    let nonLazyMessageStackThreshold: Int
    let interaction: ChatMessageInteractionContext
    let streamingMessage: StreamingMessageState?
    let streamingModelLabel: String?
    let onActivateThread: () -> Void
    let onOpenArtifact: (RenderedArtifactVersion, UUID?) -> Void

    @State private var messageRenderLimit: Int
    @State private var pendingRestoreScrollMessageID: UUID?

    init(
        conversationMessageCount: Int,
        thread: ConversationModelThreadEntity,
        context: ChatThreadRenderContext,
        columnWidth: CGFloat,
        containerHeight: CGFloat,
        assistantDisplayName: String,
        providerIconID: String?,
        threadTitle: String,
        composerHeight: CGFloat,
        isStreaming: Bool,
        isActive: Bool,
        initialMessageRenderLimit: Int,
        messageRenderPageSize: Int,
        eagerCodeHighlightTailCount: Int,
        nonLazyMessageStackThreshold: Int,
        interaction: ChatMessageInteractionContext,
        streamingMessage: StreamingMessageState?,
        streamingModelLabel: String?,
        onActivateThread: @escaping () -> Void,
        onOpenArtifact: @escaping (RenderedArtifactVersion, UUID?) -> Void
    ) {
        self.conversationMessageCount = conversationMessageCount
        self.thread = thread
        self.context = context
        self.columnWidth = columnWidth
        self.containerHeight = containerHeight
        self.assistantDisplayName = assistantDisplayName
        self.providerIconID = providerIconID
        self.threadTitle = threadTitle
        self.composerHeight = composerHeight
        self.isStreaming = isStreaming
        self.isActive = isActive
        self.initialMessageRenderLimit = initialMessageRenderLimit
        self.messageRenderPageSize = messageRenderPageSize
        self.eagerCodeHighlightTailCount = eagerCodeHighlightTailCount
        self.nonLazyMessageStackThreshold = nonLazyMessageStackThreshold
        self.interaction = interaction
        self.streamingMessage = streamingMessage
        self.streamingModelLabel = streamingModelLabel
        self.onActivateThread = onActivateThread
        self.onOpenArtifact = onOpenArtifact
        _messageRenderLimit = State(initialValue: initialMessageRenderLimit)
        _pendingRestoreScrollMessageID = State(initialValue: nil)
    }

    private var bubbleMaxWidth: CGFloat {
        max(220, columnWidth - 34)
    }

    private var bottomID: String {
        "bottom-\(thread.id.uuidString)"
    }

    private var eagerCodeHighlightStartIndex: Int {
        max(0, visibleMessages.count - eagerCodeHighlightTailCount)
    }

    private var visibleMessages: [MessageRenderItem] {
        Array(context.visibleMessages.suffix(messageRenderLimit))
    }

    private var hiddenCount: Int {
        context.visibleMessages.count - visibleMessages.count
    }

    private var useLazyMessageStack: Bool {
        visibleMessages.count > nonLazyMessageStackThreshold
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onActivateThread) {
                HStack(spacing: 8) {
                    ProviderIconView(iconID: providerIconID, size: 12)
                        .frame(width: 14, height: 14)
                    Text(threadTitle)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isActive {
                        Image(systemName: "pencil.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .overlay(JinSemanticColor.separator.opacity(0.35))

            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if useLazyMessageStack {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                timelineView
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 16) {
                                timelineView
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: messageRenderLimit) { _, _ in
                    guard let restoreID = pendingRestoreScrollMessageID else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(restoreID, anchor: .top)
                        pendingRestoreScrollMessageID = nil
                    }
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
                .onChange(of: conversationMessageCount) { _, _ in
                    DispatchQueue.main.async {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
                .onChange(of: isStreaming) { _, _ in
                    DispatchQueue.main.async {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
                .onChange(of: thread.id) { _, _ in
                    messageRenderLimit = initialMessageRenderLimit
                    pendingRestoreScrollMessageID = nil
                }
            }
        }
        .frame(width: columnWidth, alignment: .topLeading)
        .frame(minHeight: containerHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)
                .fill(JinSemanticColor.detailSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)
                .stroke(
                    isActive ? Color.accentColor.opacity(0.65) : JinSemanticColor.separator.opacity(0.45),
                    lineWidth: isActive ? JinStrokeWidth.emphasized : JinStrokeWidth.hairline
                )
        )
    }

    private var timelineView: some View {
        ChatMessageTimelineView(
            visibleMessages: visibleMessages,
            hiddenCount: hiddenCount,
            messageRenderPageSize: hiddenCount > 0 ? messageRenderPageSize : nil,
            onLoadEarlier: hiddenCount > 0 ? {
                guard let firstVisible = visibleMessages.first else { return }
                pendingRestoreScrollMessageID = firstVisible.id
                messageRenderLimit = min(context.visibleMessages.count, messageRenderLimit + messageRenderPageSize)
            } : nil,
            bubbleMaxWidth: bubbleMaxWidth,
            assistantDisplayName: assistantDisplayName,
            providerIconID: providerIconID,
            eagerCodeHighlightStartIndex: eagerCodeHighlightStartIndex,
            toolResultsByCallID: context.toolResultsByCallID,
            messageEntitiesByID: context.messageEntitiesByID,
            interaction: interaction,
            streamingMessage: streamingMessage,
            streamingModelLabel: streamingModelLabel,
            bottomSpacerHeight: composerHeight + 24,
            bottomID: bottomID,
            onActivateThreadForMessage: { _ in onActivateThread() },
            onActivateTimeline: onActivateThread,
            onOpenArtifact: onOpenArtifact
        )
    }
}
