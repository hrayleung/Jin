import SwiftUI

// MARK: - Multi-Model Stage

struct ChatMultiModelStageView: View {
    let conversationMessageCount: Int
    let containerSize: CGSize
    let visibleContainerWidth: CGFloat
    let layoutCenterOffset: CGFloat
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
    let providerTypeForThread: (ConversationModelThreadEntity) -> ProviderType?
    let providerIconIDForProviderID: (String) -> String?
    let streamingMessageForThread: (UUID) -> StreamingMessageState?
    let streamingModelLabelForThread: (UUID) -> String?
    let streamingModelIDForThread: (UUID) -> String?
    let errorMessageForThread: (UUID) -> String?
    let onActivateThread: (UUID) -> Void
    let onRetryThread: (UUID) -> Void
    let onDismissThreadError: (UUID) -> Void
    let onOpenArtifact: (RenderedArtifactVersion, UUID?) -> Void
    let expandedCollapsedMessageIDs: Binding<Set<UUID>>

    var body: some View {
        let layout = ChatMessageStagePresentationSupport.MultiModelLayout(
            containerWidth: visibleContainerWidth,
            threadCount: threads.count
        )

        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: layout.columnSpacing) {
                ForEach(threads) { thread in
                    if let context = contextsByThreadID[thread.id] {
                        ChatMultiModelThreadColumnView(
                            conversationMessageCount: conversationMessageCount,
                            thread: thread,
                            context: context,
                            columnWidth: layout.columnWidth,
                            containerHeight: containerSize.height,
                            assistantDisplayName: assistantDisplayName,
                            providerType: providerTypeForThread(thread),
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
                            streamingModelID: streamingModelIDForThread(thread.id),
                            errorMessage: errorMessageForThread(thread.id),
                            onActivateThread: { onActivateThread(thread.id) },
                            onRetryThread: { onRetryThread(thread.id) },
                            onDismissError: { onDismissThreadError(thread.id) },
                            onOpenArtifact: onOpenArtifact,
                            expandedCollapsedMessageIDs: expandedCollapsedMessageIDs
                        )
                    } else {
                        // Render an explicit placeholder rather than silently
                        // skipping the column. Reaching this branch means the
                        // render cache hasn't produced a context yet for a
                        // thread that the layout did include — without a
                        // placeholder, the column simply disappears and the
                        // layout shifts beneath the user.
                        ChatMultiModelPlaceholderColumnView(
                            columnWidth: layout.columnWidth,
                            containerHeight: containerSize.height,
                            providerIconID: providerIconIDForProviderID(thread.providerID),
                            threadTitle: modelNameForThread(thread),
                            isActive: activeThreadID == thread.id,
                            errorMessage: errorMessageForThread(thread.id),
                            onActivateThread: { onActivateThread(thread.id) },
                            onRetryThread: { onRetryThread(thread.id) },
                            onDismissError: { onDismissThreadError(thread.id) }
                        )
                    }
                }
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, 16)
            .frame(minHeight: containerSize.height, alignment: .bottom)
        }
        .frame(width: visibleContainerWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .offset(x: layoutCenterOffset)
    }
}

private struct ChatMultiModelPlaceholderColumnView: View {
    let columnWidth: CGFloat
    let containerHeight: CGFloat
    let providerIconID: String?
    let threadTitle: String
    let isActive: Bool
    let errorMessage: String?
    let onActivateThread: () -> Void
    let onRetryThread: () -> Void
    let onDismissError: () -> Void

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

            Spacer(minLength: 0)
            if let errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    HStack(spacing: 8) {
                        Button("Retry", action: onRetryThread)
                            .buttonStyle(.borderedProminent)
                        Button("Dismiss", action: onDismissError)
                            .buttonStyle(.bordered)
                    }
                }
            } else {
                Text("No messages yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
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
}

private struct ChatMultiModelThreadColumnView: View {
    let conversationMessageCount: Int
    let thread: ConversationModelThreadEntity
    let context: ChatThreadRenderContext
    let columnWidth: CGFloat
    let containerHeight: CGFloat
    let assistantDisplayName: String
    let providerType: ProviderType?
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
    let streamingModelID: String?
    let errorMessage: String?
    let onActivateThread: () -> Void
    let onRetryThread: () -> Void
    let onDismissError: () -> Void
    let onOpenArtifact: (RenderedArtifactVersion, UUID?) -> Void
    let expandedCollapsedMessageIDs: Binding<Set<UUID>>

    @State private var messageRenderLimit: Int
    @State private var pendingRestoreScrollMessageID: UUID?

    init(
        conversationMessageCount: Int,
        thread: ConversationModelThreadEntity,
        context: ChatThreadRenderContext,
        columnWidth: CGFloat,
        containerHeight: CGFloat,
        assistantDisplayName: String,
        providerType: ProviderType?,
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
        streamingModelID: String?,
        errorMessage: String?,
        onActivateThread: @escaping () -> Void,
        onRetryThread: @escaping () -> Void,
        onDismissError: @escaping () -> Void,
        onOpenArtifact: @escaping (RenderedArtifactVersion, UUID?) -> Void,
        expandedCollapsedMessageIDs: Binding<Set<UUID>>
    ) {
        self.conversationMessageCount = conversationMessageCount
        self.thread = thread
        self.context = context
        self.columnWidth = columnWidth
        self.containerHeight = containerHeight
        self.assistantDisplayName = assistantDisplayName
        self.providerType = providerType
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
        self.streamingModelID = streamingModelID
        self.errorMessage = errorMessage
        self.onActivateThread = onActivateThread
        self.onRetryThread = onRetryThread
        self.onDismissError = onDismissError
        self.onOpenArtifact = onOpenArtifact
        self.expandedCollapsedMessageIDs = expandedCollapsedMessageIDs
        _messageRenderLimit = State(initialValue: initialMessageRenderLimit)
        _pendingRestoreScrollMessageID = State(initialValue: nil)
    }

    private var bubbleMaxWidth: CGFloat {
        ChatMessageStagePresentationSupport.MultiModelLayout(
            columnWidth: columnWidth
        ).bubbleMaxWidth
    }

    private var bottomID: String {
        ChatMessageStagePresentationSupport.bottomAnchorID(threadID: thread.id)
    }

    private var eagerCodeHighlightStartIndex: Int {
        timelineWindow.eagerCodeHighlightStartIndex
    }

    private var visibleMessages: [MessageRenderItem] {
        timelineWindow.visibleMessages
    }

    private var hiddenCount: Int {
        timelineWindow.hiddenCount
    }

    private var useLazyMessageStack: Bool {
        timelineWindow.usesLazyStack
    }

    private var timelineWindow: ChatMessageStagePresentationSupport.TimelineWindow {
        ChatMessageStagePresentationSupport.TimelineWindow(
            messages: context.visibleMessages,
            renderLimit: messageRenderLimit,
            pageSize: messageRenderPageSize,
            eagerCodeHighlightTailCount: eagerCodeHighlightTailCount,
            nonLazyMessageStackThreshold: nonLazyMessageStackThreshold
        )
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

            if let errorMessage {
                ChatMultiModelErrorBannerView(
                    message: errorMessage,
                    onRetry: onRetryThread,
                    onDismiss: onDismissError
                )
            }

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
                .overlayScrollerStyle()
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
            messageRenderPageSize: timelineWindow.canLoadEarlier ? messageRenderPageSize : nil,
            onLoadEarlier: timelineWindow.canLoadEarlier ? {
                guard let plan = timelineWindow.loadEarlierPlan else { return }
                pendingRestoreScrollMessageID = plan.restoreMessageID
                messageRenderLimit = plan.nextRenderLimit
            } : nil,
            bubbleMaxWidth: bubbleMaxWidth,
            assistantDisplayName: assistantDisplayName,
            providerType: providerType,
            providerIconID: providerIconID,
            eagerCodeHighlightStartIndex: eagerCodeHighlightStartIndex,
            toolResultsByCallID: context.toolResultsByCallID,
            messageEntitiesByID: context.messageEntitiesByID,
            interaction: interaction,
            streamingMessage: streamingMessage,
            streamingModelLabel: streamingModelLabel,
            streamingModelID: streamingModelID,
            bottomSpacerHeight: composerHeight + 24,
            bottomID: bottomID,
            onActivateThreadForMessage: { _ in onActivateThread() },
            onActivateTimeline: onActivateThread,
            onOpenArtifact: onOpenArtifact,
            effectiveRenderMode: effectiveRenderMode,
            onExpandCollapsedContent: expandCollapsedContent
        )
    }

    private func effectiveRenderMode(index: Int, message: MessageRenderItem) -> MessageRenderMode {
        ChatLongConversationRenderPolicy.effectiveRenderMode(
            index: index,
            message: message,
            totalMessageCount: context.visibleMessages.count,
            visibleMessageCount: visibleMessages.count,
            expandedIDs: expandedCollapsedMessageIDs.wrappedValue
        )
    }

    private func expandCollapsedContent(_ messageID: UUID) {
        expandedCollapsedMessageIDs.wrappedValue = ChatLongConversationRenderPolicy.expandedMessageIDs(
            byExpanding: messageID,
            from: expandedCollapsedMessageIDs.wrappedValue
        )
    }
}

/// Inline error banner used by both the populated and placeholder columns
/// when a stream attempt for that thread failed. Lets the user retry without
/// leaving the column or losing the rest of the multi-model layout.
private struct ChatMultiModelErrorBannerView: View {
    let message: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Retry", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Dismiss", action: onDismiss)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
    }
}
