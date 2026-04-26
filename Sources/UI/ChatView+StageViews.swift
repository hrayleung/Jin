import SwiftUI
import SwiftData

// MARK: - Stage Views, Render Contexts & Header Bar

enum ChatStageBottomFadeMetrics {
    static let hiddenComposerHeight: CGFloat = 64
    static let minimumVisibleComposerHeight: CGFloat = 88
    static let visibleComposerExtraHeight: CGFloat = 20
    static let maximumFadeHeight: CGFloat = 180

    static func normalizedComposerHeight(_ height: CGFloat) -> CGFloat {
        guard height.isFinite else { return 0 }
        return max(0, height.rounded(.toNearestOrAwayFromZero))
    }

    static func fadeHeight(composerHeight: CGFloat, isComposerHidden: Bool) -> CGFloat {
        let baseHeight = isComposerHidden
            ? hiddenComposerHeight
            : max(minimumVisibleComposerHeight, composerHeight + visibleComposerExtraHeight)

        return min(maximumFadeHeight, baseHeight)
    }
}

private struct ChatStageBottomFadeView: View {
    let surfaceColor: Color
    let composerHeight: CGFloat
    let isComposerHidden: Bool
    let isExpandedComposerPresented: Bool

    private var fadeHeight: CGFloat {
        ChatStageBottomFadeMetrics.fadeHeight(
            composerHeight: composerHeight,
            isComposerHidden: isComposerHidden
        )
    }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            guard size.width > 0, size.height > 0 else { return }

            let rect = CGRect(origin: .zero, size: size)
            let gradient = Gradient(stops: [
                .init(color: surfaceColor.opacity(0), location: 0),
                .init(color: surfaceColor.opacity(0.10), location: 0.24),
                .init(color: surfaceColor.opacity(0.34), location: 0.58),
                .init(color: surfaceColor.opacity(0.72), location: 0.84),
                .init(color: surfaceColor, location: 1)
            ])

            context.fill(
                Path(rect),
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                )
            )
        }
        .frame(height: fadeHeight)
        .frame(maxWidth: .infinity)
        .opacity(isExpandedComposerPresented ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension ChatView {
    var conversationStage: some View {
        Group {
            if isArtifactPaneVisible {
                HSplitView {
                    messageStageContainer
                    artifactPane
                }
            } else {
                messageStageContainer
            }
        }
        .onChange(of: activeThreadID) { _, _ in
            syncArtifactSelectionForActiveThread()
        }
        .onPreferenceChange(ComposerHeightPreferenceKey.self) { newValue in
            let normalizedHeight = ChatStageBottomFadeMetrics.normalizedComposerHeight(newValue)
            if composerHeight != normalizedHeight {
                composerHeight = normalizedHeight
            }
        }
        .background(JinSemanticColor.detailSurface)
        .animation(.easeInOut(duration: 0.18), value: isArtifactPaneVisible)
    }

    var messageStageContainer: some View {
        ZStack(alignment: .bottom) {
            messageStage
            messageStageBottomFade
            floatingComposer
        }
    }

    @ViewBuilder
    var messageStageBottomFade: some View {
        ChatStageBottomFadeView(
            surfaceColor: JinSemanticColor.detailSurface,
            composerHeight: composerHeight,
            isComposerHidden: isComposerHidden,
            isExpandedComposerPresented: isExpandedComposerPresented
        )
    }

    var artifactPane: some View {
        ArtifactWorkspaceView(
            catalog: activeArtifactCatalog,
            selectedArtifactID: selectedArtifactIDBinding,
            selectedArtifactVersion: selectedArtifactVersionBinding,
            onClose: {
                isArtifactPaneVisible = false
            }
        )
    }

    var messageStage: some View {
        GeometryReader { geometry in
            if selectedModelThreads.count > 1 {
                multiThreadMessageStage(geometry: geometry)
            } else {
                singleThreadMessageStage(geometry: geometry)
            }
        }
        .environment(\.googleMapsLocationBias, googleMapsLocationBiasValue)
    }

    func singleThreadMessageStage(geometry: GeometryProxy) -> some View {
        let visibleContainerWidth = ChatConversationLayoutMetrics.visibleContainerWidth(
            containerWidth: geometry.size.width,
            sidebarWidth: mainSidebarWidth,
            isSidebarHidden: isSidebarHidden
        )
        let columnWidth = ChatConversationLayoutMetrics.messageColumnWidth(for: visibleContainerWidth)
        let compensationRatio = sidebarCompensationRatio
        let layoutCenterOffset = ChatConversationLayoutMetrics.sidebarCompensationOffset(
            containerWidth: geometry.size.width,
            contentWidth: columnWidth,
            sidebarWidth: mainSidebarWidth,
            isSidebarHidden: isSidebarHidden,
            compensationRatio: compensationRatio
        )

        return ChatSingleThreadMessagesView(
            conversationID: conversationEntity.id,
            conversationMessageCount: conversationEntity.messages.count,
            renderRevision: renderCache.version,
            containerSize: geometry.size,
            visibleContainerWidth: visibleContainerWidth,
            layoutCenterOffset: layoutCenterOffset,
            allMessages: singleThreadRenderContext.visibleMessages,
            toolResultsByCallID: singleThreadRenderContext.toolResultsByCallID,
            messageEntitiesByID: singleThreadRenderContext.messageEntitiesByID,
            assistantDisplayName: assistantDisplayName,
            providerType: providerType,
            providerIconID: currentProviderIconID,
            composerHeight: composerHeight,
            isStreaming: isStreaming,
            streamingMessage: streamingMessage,
            streamingModelLabel: streamingModelLabel,
            streamingModelID: activeThreadID.flatMap { streamingModelID(for: $0) },
            messageRenderPageSize: Self.messageRenderPageSize,
            eagerCodeHighlightTailCount: Self.eagerCodeHighlightTailCount,
            nonLazyMessageStackThreshold: Self.nonLazyMessageStackThreshold,
            pinnedBottomRefreshDelays: Self.pinnedBottomRefreshDelays,
            interaction: messageInteractionContext,
            onStreamingFinished: {
                rebuildMessageCachesIfNeeded()
            },
            onActivateMessageThread: { threadID in
                activateThread(by: threadID)
            },
            onOpenArtifact: openArtifact,
            expandedCollapsedMessageIDs: $expandedCollapsedMessageIDs,
            messageRenderLimit: $messageRenderLimit,
            pendingRestoreScrollMessageID: $pendingRestoreScrollMessageID,
            isPinnedToBottom: $isPinnedToBottom,
            pinnedBottomRefreshGeneration: $pinnedBottomRefreshGeneration
        )
        .animation(.easeInOut(duration: 0.24), value: mainSidebarWidth)
    }

    var sidebarCompensationRatio: CGFloat {
        mainWindowIsFullScreen
            ? ChatConversationLayoutMetrics.fullScreenSidebarCompensationRatio
            : ChatConversationLayoutMetrics.standardSidebarCompensationRatio
    }

    func multiThreadMessageStage(geometry: GeometryProxy) -> some View {
        ChatMultiModelStageView(
            conversationMessageCount: conversationEntity.messages.count,
            containerSize: geometry.size,
            threads: selectedModelThreads,
            contextsByThreadID: selectedThreadRenderContexts,
            assistantDisplayName: assistantDisplayName,
            composerHeight: composerHeight,
            isStreaming: isStreaming,
            activeThreadID: activeModelThread?.id,
            initialMessageRenderLimit: Self.initialMessageRenderLimit,
            messageRenderPageSize: Self.messageRenderPageSize,
            eagerCodeHighlightTailCount: Self.eagerCodeHighlightTailCount,
            nonLazyMessageStackThreshold: Self.nonLazyMessageStackThreshold,
            interaction: messageInteractionContext,
            modelNameForThread: { thread in
                modelName(id: thread.modelID, providerID: thread.providerID)
            },
            providerTypeForThread: { thread in
                providerType(forProviderID: thread.providerID)
            },
            providerIconIDForProviderID: { providerID in
                providerIconID(for: providerID)
            },
            streamingMessageForThread: { threadID in
                streamingMessage(for: threadID)
            },
            streamingModelLabelForThread: { threadID in
                streamingModelLabel(for: threadID)
            },
            streamingModelIDForThread: { threadID in
                streamingModelID(for: threadID)
            },
            onActivateThread: { threadID in
                activateThread(by: threadID)
            },
            onOpenArtifact: openArtifact,
            expandedCollapsedMessageIDs: $expandedCollapsedMessageIDs
        )
    }

    // MARK: - Render Contexts

    var singleThreadRenderContext: ChatThreadRenderContext {
        renderCache.singleThreadContext(activeThreadID: activeModelThread?.id)
    }

    var selectedThreadRenderContexts: [UUID: ChatThreadRenderContext] {
        Dictionary(uniqueKeysWithValues: selectedModelThreads.map { thread in
            (thread.id, threadRenderContext(threadID: thread.id))
        })
    }

    var activeArtifactCatalog: ArtifactCatalog {
        if let activeThreadID, activeModelThread != nil {
            return threadRenderContext(threadID: activeThreadID).artifactCatalog
        }
        return renderCache.artifactCatalog
    }

    var selectedArtifactIDBinding: Binding<String?> {
        Binding(
            get: {
                guard let threadID = activeModelThread?.id else { return nil }
                return selectedArtifactIDByThreadID[threadID]
            },
            set: { newValue in
                guard let threadID = activeModelThread?.id else { return }
                selectedArtifactIDByThreadID[threadID] = newValue
            }
        )
    }

    var selectedArtifactVersionBinding: Binding<Int?> {
        Binding(
            get: {
                guard let threadID = activeModelThread?.id else { return nil }
                return selectedArtifactVersionByThreadID[threadID]
            },
            set: { newValue in
                guard let threadID = activeModelThread?.id else { return }
                selectedArtifactVersionByThreadID[threadID] = newValue
            }
        )
    }

    func threadRenderContext(threadID: UUID) -> ChatThreadRenderContext {
        renderCache.threadContext(
            threadID: threadID,
            allMessages: conversationEntity.messages,
            sortedThreads: sortedModelThreads,
            currentModelName: currentModelName,
            modelNameForThread: { thread in
                modelName(id: thread.modelID, providerID: thread.providerID)
            },
            assistantProviderIconID: { providerID in
                providerIconID(for: providerID)
            }
        )
    }

    // MARK: - Message Interaction

    var messageInteractionContext: ChatMessageInteractionContext {
        ChatMessageInteractionContext(
            textToSpeechEnabled: textToSpeechPluginEnabled,
            textToSpeechConfigured: textToSpeechConfigured,
            editingUserMessageID: editingUserMessageID,
            editingUserMessageText: $editingUserMessageText,
            editingUserMessageFocused: $isEditingUserMessageFocused,
            textToSpeechIsGenerating: { messageID in
                ttsPlaybackManager.isGenerating(messageID: messageID)
            },
            textToSpeechIsPlaying: { messageID in
                ttsPlaybackManager.isPlaying(messageID: messageID)
            },
            textToSpeechIsPaused: { messageID in
                ttsPlaybackManager.isPaused(messageID: messageID)
            },
            onToggleSpeakAssistantMessage: { entity, text in
                toggleSpeakAssistantMessage(entity, text: text)
            },
            onStopSpeakAssistantMessage: { entity in
                stopSpeakAssistantMessage(entity)
            },
            onRegenerate: { entity in
                regenerateMessage(entity)
            },
            onEditUserMessage: { entity in
                beginEditingUserMessage(entity)
            },
            onSubmitUserEdit: { entity in
                submitEditingUserMessage(entity)
            },
            onCancelUserEdit: {
                cancelEditingUserMessage()
            },
            onDeleteMessage: { entity in
                deleteMessage(entity)
            },
            onDeleteResponse: { entity in
                deleteResponse(entity)
            },
            onQuoteSelection: { snapshot, modelName in
                addDraftQuote(from: snapshot, sourceModelName: modelName)
            },
            onCreateHighlight: { snapshot in
                persistHighlight(from: snapshot)
            },
            onRemoveHighlights: { highlightIDs in
                removeHighlights(ids: highlightIDs)
            },
            editSlashCommand: editSlashCommandContext
        )
    }

    var editSlashCommandContext: EditSlashCommandContext {
        let isEditTarget = slashCommandTarget == .editMessage
        return EditSlashCommandContext(
            servers: slashCommandMCPItems,
            isActive: isSlashMCPPopoverVisible && isEditTarget,
            filterText: isEditTarget ? slashMCPFilterText : "",
            highlightedIndex: isEditTarget ? slashMCPHighlightedIndex : 0,
            perMessageChips: perMessageMCPChips,
            onSelectServer: handleSlashCommandSelectServer,
            onDismiss: dismissSlashCommandPopover,
            onRemovePerMessageServer: removePerMessageMCPServer,
            onInterceptKeyDown: (isSlashMCPPopoverVisible && isEditTarget) ? handleSlashCommandKeyDown : nil
        )
    }

    // MARK: - Header Bar

    var detailHeaderBar: some View {
        ChatHeaderBarView(
            isSidebarHidden: isSidebarHidden,
            onToggleSidebar: onToggleSidebar,
            onNewChat: onNewChat,
            titlebarLeadingInset: titlebarLeadingInset,
            mainSidebarWidth: mainSidebarWidth,
            currentProviderIconID: currentProviderIconID,
            currentModelName: currentModelName,
            modelPickerHelpText: providerType == .claudeManagedAgents ? "Select managed agent or model" : "Select model",
            toolbarThreads: headerToolbarThreads,
            isModelPickerPresented: $isModelPickerPresented,
            isAddModelPickerPresented: $isAddModelPickerPresented,
            isStarred: conversationEntity.isStarred == true,
            starShortcutLabel: shortcutsStore.binding(for: .toggleStarChat)?.displayLabel,
            addModelShortcutLabel: shortcutsStore.binding(for: .addModelToChat)?.displayLabel,
            onToggleStar: {
                conversationEntity.isStarred = !(conversationEntity.isStarred == true)
                try? modelContext.save()
            },
            onOpenAssistantInspector: { isAssistantInspectorPresented = true },
            onRequestDeleteConversation: onRequestDeleteConversation,
            onToggleToolbarThread: { threadID in
                guard let thread = sortedModelThreads.first(where: { $0.id == threadID }) else { return }
                toggleThreadSelection(thread)
            },
            onActivateToolbarThread: activateThread(by:),
            onRemoveToolbarThread: { threadID in
                guard let thread = sortedModelThreads.first(where: { $0.id == threadID }) else { return }
                removeModelThread(thread)
            }
        ) {
            modelPickerPopoverContent(includeManagedAgentSelection: true) { providerID, modelID in
                setProviderAndModel(providerID: providerID, modelID: modelID)
                isModelPickerPresented = false
            }
        } addModelPopover: {
            modelPickerPopoverContent(includeManagedAgentSelection: false) { providerID, modelID in
                addOrActivateThread(providerID: providerID, modelID: modelID)
                isAddModelPickerPresented = false
            }
        }
    }

    var headerToolbarThreads: [ChatHeaderToolbarThread] {
        ChatThreadSupport.headerToolbarThreads(
            secondaryThreads: secondaryToolbarThreads,
            sortedThreadCount: sortedModelThreads.count,
            providerIconID: { providerID in
                providerIconID(for: providerID)
            },
            modelName: { modelID, providerID in
                modelName(id: modelID, providerID: providerID)
            },
            isActiveThread: { thread in
                isActiveThread(thread)
            }
        )
    }

    func modelPickerPopoverContent(
        includeManagedAgentSelection: Bool,
        onSelect: @escaping (String, String) -> Void
    ) -> some View {
        ModelPickerPopover(
            favoritesStore: favoriteModelsStore,
            providers: providers,
            selectedProviderID: conversationEntity.providerID,
            selectedModelID: conversationEntity.modelID,
            managedAgentContext: includeManagedAgentSelection ? currentManagedAgentPickerContext : nil,
            onSelect: onSelect
        )
    }

    var currentManagedAgentPickerContext: ModelPickerPopover.ManagedAgentContext? {
        guard providerType == .claudeManagedAgents,
              let currentProvider else { return nil }

        let resolvedControls = resolvedClaudeManagedControls(
            for: conversationEntity.providerID,
            threadControls: controls
        )

        return ModelPickerPopover.ManagedAgentContext(
            provider: currentProvider,
            selectedAgentID: resolvedControls.claudeManagedAgentID,
            availableAgents: resolvedClaudeManagedAgentOptions(
                for: conversationEntity.providerID,
                threadControls: controls
            ),
            isRefreshing: isRefreshingClaudeManagedSessionResources,
            onRefresh: {
                Task { await refreshClaudeManagedAgentSessionResources() }
            },
            onOpenSettings: {
                openClaudeManagedAgentSessionSettingsEditor()
            },
            onSelectAgent: { descriptor in
                applyClaudeManagedAgentSelection(descriptor)
                isModelPickerPresented = false
            }
        )
    }
}
