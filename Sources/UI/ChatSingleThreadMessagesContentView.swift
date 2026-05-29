import SwiftUI

private struct MessageTimelineContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

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

    /// Set while we are driving `proxy.scrollTo(...)` ourselves. During a
    /// programmatic scroll the scroll-geometry stream emits transient
    /// off-pin offsets that must not be treated as a user-initiated unpin.
    @State private var isExecutingProgrammaticScroll = false
    @State private var programmaticScrollGeneration = 0
    @State private var pendingInitialBottomScrollConversationID: UUID?
    @State private var pendingInitialBottomScrollTask: Task<Void, Never>?

    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.codeFontFamily) private var codeFontFamily = JinTypography.systemFontPreferenceValue
    private static let maxPrewarmItems = 8

    /// Background markdown-parse pre-warm. We hold the `Task` returned by
    /// `NativeMarkdownCache.prewarm(...)` so a new wave can cancel the
    /// previous one — without this an in-progress prewarm for the prior
    /// conversation keeps thrashing the CPU after the user switches.
    @State private var prewarmTask: Task<Void, Never>?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key
    }

    private var visibleMessages: [MessageRenderItem] {
        visibleMessagesForWindow
    }

    private var initialBottomScrollContentKey: InitialBottomScrollContentKey {
        InitialBottomScrollContentKey(
            conversationID: conversationID,
            visibleMessageCount: visibleMessagesForWindow.count,
            lastVisibleMessageID: visibleMessagesForWindow.last?.id,
            hasStreamingMessage: streamingMessage != nil
        )
    }

    private var hasPendingInitialBottomScroll: Bool {
        pendingInitialBottomScrollConversationID == conversationID
    }

    private var hasInitialBottomScrollContent: Bool {
        !visibleMessagesForWindow.isEmpty || streamingMessage != nil
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                let layout = ChatMessageStagePresentationSupport.SingleThreadLayout(
                    visibleContainerWidth: visibleContainerWidth
                )
                let window = timelineWindow

                Group {
                    if window.usesLazyStack {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            timelineView(
                                window: window,
                                bubbleMaxWidth: layout.bubbleMaxWidth
                            )
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            timelineView(
                                window: window,
                                bubbleMaxWidth: layout.bubbleMaxWidth
                            )
                        }
                    }
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: MessageTimelineContentHeightPreferenceKey.self,
                            value: geometry.size.height
                        )
                    }
                }
                .frame(width: layout.columnWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .offset(x: layoutCenterOffset)
                .padding(.top, 24)
            }
            .overlayScrollerStyle()
            .defaultScrollAnchor(.bottom)
            .overlay(alignment: .bottomTrailing) {
                if !isPinnedToBottom {
                    Button {
                        shouldMaintainPinnedBottomAnchor = true
                        withAnimation(.easeOut(duration: 0.2)) {
                            scrollToBottomIfNeeded(proxy: proxy, allowWhenContentFits: true)
                        }
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
            }
            .animation(.easeInOut(duration: 0.2), value: isPinnedToBottom)
            .onScrollPinChange(
                isPinned: $isPinnedToBottom,
                bottomTolerance: ChatTimelineScrollCoordinator.pinnedBottomTolerance(
                    composerHeight: composerHeight
                ),
                onChange: handlePinStateChange
            )
            .onUserScrollIntentChange { isUserDrivenScroll in
                isUserScrollInProgress = isUserDrivenScroll
                if isUserDrivenScroll {
                    cancelPendingInitialBottomScroll()
                    cancelPendingPinnedBottomRefresh()
                    shouldMaintainPinnedBottomAnchor = false
                    pinnedBottomRefreshGeneration = ChatTimelineScrollCoordinator.invalidatedRefreshGeneration(
                        current: pinnedBottomRefreshGeneration
                    )
                }
            }
            .onChange(of: messageRenderLimit) { _, _ in
                guard let restoreID = pendingRestoreScrollMessageID else { return }
                DispatchQueue.main.async {
                    beginProgrammaticScroll()
                    proxy.scrollTo(restoreID, anchor: .top)
                    pendingRestoreScrollMessageID = nil
                }
            }
            .onChange(of: allMessageCount) { _, _ in
                refreshPinnedBottomIfNeeded(proxy: proxy)
            }
            .onChange(of: isStreaming) { wasStreaming, nowStreaming in
                guard wasStreaming, !nowStreaming else { return }
                onStreamingFinished()
                refreshPinnedBottomIfNeeded(proxy: proxy)
            }
            .onChange(of: conversationID, initial: true) { _, _ in
                prepareInitialScrollToBottomAfterConversationSwitch(proxy: proxy)
            }
            .onChange(of: initialBottomScrollContentKey) { _, _ in
                requestInitialScrollToBottomIfReady(proxy: proxy)
            }
            .onPreferenceChange(MessageTimelineContentHeightPreferenceKey.self) { newHeight in
                handleContentHeightChange(newHeight, proxy: proxy)
            }
            .onDisappear {
                cancelPendingPinnedBottomRefresh()
                cancelPendingInitialBottomScroll()
            }
            .task(id: PrewarmKey(
                conversationID: conversationID,
                // Re-run the prewarm when the visible window grows (load
                // earlier expands the window, streaming adds the
                // just-finished message). Without this, newly visible
                // messages would only parse on first scroll-into-view.
                messageCount: visibleMessagesForWindow.count,
                // Identity of the *last* visible message — catches the
                // streaming-finished case where messageCount is stable
                // (the previously-streaming placeholder gets replaced by
                // a non-streaming MessageRenderItem with a fresh UUID).
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
    }

    private struct PrewarmKey: Hashable {
        let conversationID: UUID
        let messageCount: Int
        let lastMessageID: UUID?
        let appFontFamily: String
        let codeFontFamily: String
    }

    private struct InitialBottomScrollContentKey: Equatable {
        let conversationID: UUID
        let visibleMessageCount: Int
        let lastVisibleMessageID: UUID?
        let hasStreamingMessage: Bool
    }

    private func schedulePrewarm() {
        // Cancel any in-flight prewarm before starting a fresh wave —
        // the previous wave's queued texts may no longer match what the
        // user is about to see (e.g., after a conversation switch).
        prewarmTask?.cancel()
        // Reverse order so the message closest to the viewport bottom —
        // where pin-to-bottom puts the user on conversation open — gets
        // parsed first. The user sees its content come up without the
        // synchronous parse hitch on first paint.
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

    private func timelineView(
        window: ChatMessageStagePresentationSupport.TimelineWindow,
        bubbleMaxWidth: CGFloat
    ) -> some View {
        ChatMessageTimelineView(
            visibleMessages: window.visibleMessages,
            hiddenCount: window.hiddenCount,
            messageRenderPageSize: messageRenderPageSize,
            onLoadEarlier: {
                guard let plan = window.loadEarlierPlan else { return }
                pendingRestoreScrollMessageID = plan.restoreMessageID
                messageRenderLimit = plan.nextRenderLimit
            },
            bubbleMaxWidth: bubbleMaxWidth,
            assistantDisplayName: assistantDisplayName,
            providerType: providerType,
            providerIconID: providerIconID,
            eagerCodeHighlightStartIndex: window.eagerCodeHighlightStartIndex,
            toolResultsByCallID: toolResultsByCallID,
            messageEntitiesByID: messageEntitiesByID,
            interaction: interaction,
            streamingMessage: streamingMessage,
            streamingModelLabel: streamingModelLabel,
            streamingModelID: streamingModelID,
            bottomSpacerHeight: composerHeight + 24,
            bottomID: ChatMessageStagePresentationSupport.bottomAnchorID(),
            onOpenArtifact: onOpenArtifact,
            effectiveRenderMode: effectiveRenderMode,
            onExpandCollapsedContent: expandCollapsedContent
        )
    }

    private func refreshPinnedBottomIfNeeded(proxy: ScrollViewProxy) {
        guard let plan = ChatTimelineScrollCoordinator.refreshPlan(
            currentGeneration: pinnedBottomRefreshGeneration,
            shouldMaintainPinnedBottomAnchor: shouldMaintainPinnedBottomAnchor,
            delays: pinnedBottomRefreshDelays
        ) else {
            return
        }
        pinnedBottomRefreshGeneration = plan.generation

        for delay in plan.delays {
            schedulePinnedBottomRefreshAttempt(
                after: delay,
                expectedGeneration: plan.generation,
                proxy: proxy
            )
        }
    }

    private func schedulePinnedBottomRefresh(
        proxy: ScrollViewProxy,
        debounceNanoseconds: UInt64? = nil
    ) {
        cancelPendingPinnedBottomRefresh()
        guard shouldMaintainPinnedBottomAnchor else { return }

        pendingPinnedBottomRefreshTask = Task { @MainActor in
            if let debounceNanoseconds {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
                guard !Task.isCancelled else { return }
            }

            refreshPinnedBottomIfNeeded(proxy: proxy)
            pendingPinnedBottomRefreshTask = nil
        }
    }

    private func schedulePinnedBottomRefreshAttempt(
        after delay: TimeInterval,
        expectedGeneration: Int,
        proxy: ScrollViewProxy
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard ChatTimelineScrollCoordinator.shouldPerformRefresh(
                expectedGeneration: expectedGeneration,
                currentGeneration: pinnedBottomRefreshGeneration,
                shouldMaintainPinnedBottomAnchor: shouldMaintainPinnedBottomAnchor
            ) else {
                return
            }
            scrollToBottomIfNeeded(proxy: proxy)
        }
    }

    private func cancelPendingPinnedBottomRefresh() {
        pendingPinnedBottomRefreshTask?.cancel()
        pendingPinnedBottomRefreshTask = nil
    }

    private func scrollToBottomIfNeeded(
        proxy: ScrollViewProxy,
        allowWhenContentFits: Bool = false
    ) {
        guard ChatTimelineScrollCoordinator.shouldScrollToBottom(
            lastMeasuredContentHeight: lastMeasuredContentHeight,
            viewportHeight: containerSize.height,
            allowWhenContentFits: allowWhenContentFits
        ) else {
            return
        }
        beginProgrammaticScroll()
        proxy.scrollTo(ChatMessageStagePresentationSupport.bottomAnchorID(), anchor: .bottom)
    }

    private func prepareInitialScrollToBottomAfterConversationSwitch(proxy: ScrollViewProxy) {
        cancelPendingPinnedBottomRefresh()
        cancelPendingInitialBottomScroll()
        lastMeasuredContentHeight = 0
        shouldMaintainPinnedBottomAnchor = true
        isUserScrollInProgress = false
        pendingInitialBottomScrollConversationID = conversationID
        requestInitialScrollToBottomIfReady(proxy: proxy)
    }

    private func requestInitialScrollToBottomIfReady(proxy: ScrollViewProxy) {
        guard hasPendingInitialBottomScroll else { return }
        guard !isUserScrollInProgress else {
            cancelPendingInitialBottomScroll()
            return
        }
        guard hasInitialBottomScrollContent else {
            pendingInitialBottomScrollTask?.cancel()
            pendingInitialBottomScrollTask = nil
            return
        }

        let contentKey = initialBottomScrollContentKey
        shouldMaintainPinnedBottomAnchor = true
        performInitialBottomScroll(proxy: proxy)
        scheduleInitialBottomScrollSettle(
            proxy: proxy,
            targetConversationID: conversationID,
            contentKey: contentKey
        )
    }

    private func performInitialBottomScroll(proxy: ScrollViewProxy) {
        beginProgrammaticScroll()
        proxy.scrollTo(ChatMessageStagePresentationSupport.bottomAnchorID(), anchor: .bottom)
    }

    private func scheduleInitialBottomScrollSettle(
        proxy: ScrollViewProxy,
        targetConversationID: UUID,
        contentKey: InitialBottomScrollContentKey
    ) {
        pendingInitialBottomScrollTask?.cancel()
        pendingInitialBottomScrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            guard pendingInitialBottomScrollConversationID == targetConversationID else { return }
            guard initialBottomScrollContentKey == contentKey,
                  hasInitialBottomScrollContent else {
                pendingInitialBottomScrollTask = nil
                return
            }
            guard !isUserScrollInProgress else {
                cancelPendingInitialBottomScroll()
                return
            }

            shouldMaintainPinnedBottomAnchor = true
            performInitialBottomScroll(proxy: proxy)

            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            guard pendingInitialBottomScrollConversationID == targetConversationID else { return }
            guard initialBottomScrollContentKey == contentKey,
                  hasInitialBottomScrollContent else {
                pendingInitialBottomScrollTask = nil
                return
            }
            guard !isUserScrollInProgress else {
                cancelPendingInitialBottomScroll()
                return
            }

            pendingInitialBottomScrollConversationID = nil
            pendingInitialBottomScrollTask = nil
            shouldMaintainPinnedBottomAnchor = true
        }
    }

    private func cancelPendingInitialBottomScroll() {
        pendingInitialBottomScrollTask?.cancel()
        pendingInitialBottomScrollTask = nil
        pendingInitialBottomScrollConversationID = nil
    }

    private func beginProgrammaticScroll() {
        programmaticScrollGeneration &+= 1
        let generation = programmaticScrollGeneration
        isExecutingProgrammaticScroll = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard programmaticScrollGeneration == generation else { return }
            isExecutingProgrammaticScroll = false
        }
    }

    private func handleContentHeightChange(_ newHeight: CGFloat, proxy: ScrollViewProxy) {
        guard !isUserScrollInProgress else { return }
        guard let action = ChatTimelineScrollCoordinator.contentHeightChangeAction(
            newHeight: newHeight,
            previousHeight: lastMeasuredContentHeight,
            shouldMaintainPinnedBottomAnchor: shouldMaintainPinnedBottomAnchor
        ) else {
            return
        }
        lastMeasuredContentHeight = action.measuredHeight
        if hasPendingInitialBottomScroll {
            requestInitialScrollToBottomIfReady(proxy: proxy)
        }
        guard action.shouldScheduleRefresh else { return }
        guard !isExecutingProgrammaticScroll else { return }
        schedulePinnedBottomRefresh(
            proxy: proxy,
            debounceNanoseconds: 120_000_000
        )
    }

    private func handlePinStateChange(wasPinned: Bool, isPinned: Bool) {
        guard wasPinned != isPinned else { return }

        if isPinned {
            shouldMaintainPinnedBottomAnchor = true
            return
        }

        guard !hasPendingInitialBottomScroll else {
            shouldMaintainPinnedBottomAnchor = true
            return
        }
        guard !isExecutingProgrammaticScroll else { return }
        cancelPendingPinnedBottomRefresh()
        shouldMaintainPinnedBottomAnchor = false
        pinnedBottomRefreshGeneration = ChatTimelineScrollCoordinator.invalidatedRefreshGeneration(
            current: pinnedBottomRefreshGeneration
        )
    }

    private func effectiveRenderMode(index: Int, message: MessageRenderItem) -> MessageRenderMode {
        ChatLongConversationRenderPolicy.effectiveRenderMode(
            index: index,
            message: message,
            totalMessageCount: allMessageCount,
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
