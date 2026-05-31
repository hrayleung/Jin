import SwiftUI

struct ChatSingleThreadMessagesContentView: View, Equatable {
    let key: ChatStageEquatableKey
    let conversationID: UUID
    let visibleMessagesForWindow: [MessageRenderItem]
    let allMessageCount: Int
    let messageRenderPageSize: Int
    let eagerCodeHighlightTailCount: Int
    let nonLazyMessageStackThreshold: Int
    let containerSize: CGSize
    let visibleContainerWidth: CGFloat
    let layoutCenterOffset: CGFloat
    let composerHeight: CGFloat
    let isStreaming: Bool
    let streamingMessage: StreamingMessageState?
    let streamingModelLabel: String?
    let streamingModelID: String?
    let assistantDisplayName: String
    let providerType: ProviderType?
    let providerIconID: String?
    let toolResultsByCallID: [String: ToolResult]
    let messageEntitiesByID: [UUID: MessageEntity]
    let pinnedBottomRefreshDelays: [TimeInterval]
    let interaction: ChatMessageInteractionContext
    let onStreamingFinished: () -> Void
    let onOpenArtifact: (RenderedArtifactVersion) -> Void
    let timelineWindow: ChatMessageStagePresentationSupport.TimelineWindow
    let expandedCollapsedMessageIDs: Binding<Set<UUID>>
    @Binding var messageRenderLimit: Int
    @Binding var pendingRestoreScrollMessageID: UUID?
    @Binding var isPinnedToBottom: Bool
    @Binding var pinnedBottomRefreshGeneration: Int
    @Binding var lastMeasuredContentHeight: CGFloat
    @Binding var pendingPinnedBottomRefreshTask: Task<Void, Never>?
    @Binding var shouldMaintainPinnedBottomAnchor: Bool
    @Binding var isUserScrollInProgress: Bool

    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.codeFontFamily) private var codeFontFamily = JinTypography.systemFontPreferenceValue
    private static let maxPrewarmItems = 8

    /// Background markdown-parse pre-warm. We hold the `Task` returned by
    /// `NativeMarkdownCache.prewarm(...)` so a new wave can cancel the
    /// previous one — without this an in-progress prewarm for the prior
    /// conversation keeps thrashing the CPU after the user switches.
    @State private var prewarmTask: Task<Void, Never>?

    /// Bridge so the SwiftUI "scroll to bottom" chevron can drive the AppKit
    /// table controller without the controller leaking into the view tree.
    @StateObject private var scrollHandle = ChatTimelineScrollHandle()

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key
    }

    private var rows: [ChatTimelineRow] {
        var result: [ChatTimelineRow] = []
        if timelineWindow.canLoadEarlier {
            result.append(.loadEarlier(
                hiddenCount: timelineWindow.hiddenCount,
                pageSize: messageRenderPageSize
            ))
        }
        for (index, message) in timelineWindow.visibleMessages.enumerated() {
            result.append(.message(message, index: index))
        }
        if let streamingMessage {
            result.append(.streaming(streamingMessage))
        }
        return result
    }

    private func makeShared(
        layout: ChatMessageStagePresentationSupport.SingleThreadLayout
    ) -> ChatTimelineSharedInputs {
        ChatTimelineSharedInputs(
            maxBubbleWidth: layout.bubbleMaxWidth,
            columnWidth: layout.columnWidth,
            layoutCenterOffset: layoutCenterOffset,
            assistantDisplayName: assistantDisplayName,
            providerType: providerType,
            providerIconID: providerIconID,
            eagerCodeHighlightStartIndex: timelineWindow.eagerCodeHighlightStartIndex,
            payloadResolver: ChatTimelinePayloadResolverFactory.make(messageEntitiesByID: messageEntitiesByID),
            toolResultsByCallID: toolResultsByCallID,
            messageEntitiesByID: messageEntitiesByID,
            interaction: interaction,
            onOpenArtifact: onOpenArtifact,
            effectiveRenderMode: effectiveRenderMode,
            onExpandCollapsedContent: expandCollapsedContent,
            colorScheme: colorScheme
        )
    }

    var body: some View {
        let layout = ChatMessageStagePresentationSupport.SingleThreadLayout(
            visibleContainerWidth: visibleContainerWidth
        )

        ChatTimelineTableRepresentable(
            conversationID: conversationID,
            rows: rows,
            shared: makeShared(layout: layout),
            streamingMessage: streamingMessage,
            streamingModelLabel: streamingModelLabel,
            streamingModelID: streamingModelID,
            topInset: 24,
            bottomInset: composerHeight + 24,
            bottomTolerance: ChatTimelineScrollCoordinator.pinnedBottomTolerance(
                composerHeight: composerHeight
            ),
            nextRenderLimit: timelineWindow.nextRenderLimit,
            canLoadEarlier: timelineWindow.canLoadEarlier,
            scrollHandle: scrollHandle,
            isPinnedToBottom: $isPinnedToBottom,
            messageRenderLimit: $messageRenderLimit,
            onLoadEarlier: {
                pendingRestoreScrollMessageID = timelineWindow.loadEarlierPlan?.restoreMessageID
            }
        )
        .overlay(alignment: .bottomTrailing) {
            if !isPinnedToBottom {
                scrollToBottomButton
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isPinnedToBottom)
        .onChange(of: isStreaming) { wasStreaming, nowStreaming in
            guard wasStreaming, !nowStreaming else { return }
            onStreamingFinished()
        }
        .task(id: PrewarmKey(
            conversationID: conversationID,
            // Re-run the prewarm when the visible window grows (load earlier
            // expands the window, streaming adds the just-finished message).
            messageCount: visibleMessagesForWindow.count,
            // Identity of the *last* visible message — catches the
            // streaming-finished case where messageCount is stable.
            lastMessageID: visibleMessagesForWindow.last?.id,
            appFontFamily: appFontFamily,
            codeFontFamily: codeFontFamily
        )) {
            schedulePrewarm()
        }
        .onDisappear {
            prewarmTask?.cancel()
        }
    }

    private var scrollToBottomButton: some View {
        Button {
            scrollHandle.scrollToBottom(animated: true)
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .jinAdaptiveBackground(Circle())
                .shadow(color: JinSemanticColor.shadowElevated, radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 34)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }

    private struct PrewarmKey: Hashable {
        let conversationID: UUID
        let messageCount: Int
        let lastMessageID: UUID?
        let appFontFamily: String
        let codeFontFamily: String
    }

    private func schedulePrewarm() {
        // Cancel any in-flight prewarm before starting a fresh wave — the
        // previous wave's queued texts may no longer match what the user is
        // about to see (e.g., after a conversation switch).
        prewarmTask?.cancel()
        // Reverse order so the message closest to the viewport bottom — where
        // pin-to-bottom puts the user on conversation open — gets parsed first.
        let items = extractPrewarmItems(from: visibleMessagesForWindow)
            .reversed()
            .prefix(Self.maxPrewarmItems)
        prewarmTask = NativeMarkdownCache.prewarm(
            items: Array(items),
            appFontFamily: appFontFamily,
            codeFontFamily: codeFontFamily
        )
    }

    private func extractPrewarmItems(from messages: [MessageRenderItem]) -> [NativeMarkdownCache.PrewarmItem] {
        var items: [NativeMarkdownCache.PrewarmItem] = []
        items.reserveCapacity(messages.count)
        for (index, message) in messages.enumerated() {
            guard message.isAssistant else { continue }
            let renderMode = effectiveRenderMode(index: index, message: message)
            guard renderMode != .collapsedPreview else { continue }
            let renderPlainText = renderMode == .nativeText

            for block in message.renderedBlocks {
                guard case .content(_, let part) = block else { continue }
                guard case .text(let text) = part else { continue }
                guard !text.isEmpty else { continue }
                items.append(NativeMarkdownCache.PrewarmItem(
                    markdownText: text,
                    renderPlainText: renderPlainText
                ))
            }
        }
        return items
    }

    private func effectiveRenderMode(index: Int, message: MessageRenderItem) -> MessageRenderMode {
        ChatLongConversationRenderPolicy.effectiveRenderMode(
            index: index,
            message: message,
            totalMessageCount: allMessageCount,
            visibleMessageCount: visibleMessagesForWindow.count,
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
