import SwiftUI
import SwiftData

// MARK: - Stage Views, Render Contexts & Header Bar

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
            if abs(composerHeight - newValue) > 0.5 {
                composerHeight = newValue
            }
        }
        .background(JinSemanticColor.detailSurface)
        .animation(.easeInOut(duration: 0.18), value: isArtifactPaneVisible)
    }

    var messageStageContainer: some View {
        ZStack(alignment: .bottom) {
            messageStage
                .overlay(alignment: .bottom) {
                    messageStageBottomFade
                }
            floatingComposer
        }
    }

    @ViewBuilder
    var messageStageBottomFade: some View {
        let baseHeight = isComposerHidden ? 64.0 : max(88.0, composerHeight + 20)
        let fadeHeight = min(180.0, baseHeight)

        LinearGradient(
            stops: [
                .init(color: JinSemanticColor.detailSurface.opacity(0), location: 0),
                .init(color: JinSemanticColor.detailSurface.opacity(0.10), location: 0.24),
                .init(color: JinSemanticColor.detailSurface.opacity(0.34), location: 0.58),
                .init(color: JinSemanticColor.detailSurface.opacity(0.72), location: 0.84),
                .init(color: JinSemanticColor.detailSurface, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: fadeHeight)
        .opacity(isExpandedComposerPresented ? 0 : 1)
        .allowsHitTesting(false)
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
        ChatSingleThreadMessagesView(
            conversationID: conversationEntity.id,
            conversationMessageCount: conversationEntity.messages.count,
            containerSize: geometry.size,
            allMessages: singleThreadRenderContext.visibleMessages,
            toolResultsByCallID: singleThreadRenderContext.toolResultsByCallID,
            messageEntitiesByID: singleThreadRenderContext.messageEntitiesByID,
            assistantDisplayName: assistantDisplayName,
            providerIconID: currentProviderIconID,
            composerHeight: composerHeight,
            isStreaming: isStreaming,
            streamingMessage: streamingMessage,
            streamingModelLabel: streamingModelLabel,
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
            providerIconIDForProviderID: { providerID in
                providerIconID(for: providerID)
            },
            streamingMessageForThread: { threadID in
                streamingMessage(for: threadID)
            },
            streamingModelLabelForThread: { threadID in
                streamingModelLabel(for: threadID)
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
        if let threadID = activeModelThread?.id,
           let cached = cachedThreadRenderContextsByThreadID[threadID] {
            return cached
        }

        return ChatThreadRenderContext(
            visibleMessages: cachedVisibleMessages,
            historyMessages: cachedActiveThreadHistory,
            messageEntitiesByID: cachedMessageEntitiesByID,
            toolResultsByCallID: cachedToolResultsByCallID,
            artifactCatalog: cachedArtifactCatalog
        )
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
        return cachedArtifactCatalog
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
        if let cached = cachedThreadRenderContextsByThreadID[threadID] {
            return cached
        }

        let ordered = ChatMessageRenderPipeline.orderedMessages(
            from: conversationEntity.messages,
            threadID: threadID
        )
        let fallbackModelLabel = sortedModelThreads
            .first(where: { $0.id == threadID })
            .map { modelName(id: $0.modelID, providerID: $0.providerID) }
            ?? currentModelName

        let context = ChatMessageRenderPipeline.makeRenderContext(
            from: ordered,
            fallbackModelLabel: fallbackModelLabel,
            assistantProviderIconID: { providerID in
                providerIconID(for: providerID)
            }
        )

        DispatchQueue.main.async { [threadID, context] in
            guard cachedThreadRenderContextsByThreadID[threadID] == nil else { return }
            cachedThreadRenderContextsByThreadID[threadID] = context
        }

        return context
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
            currentProviderIconID: currentProviderIconID,
            currentModelName: currentModelName,
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
            modelPickerPopoverContent { providerID, modelID in
                setProviderAndModel(providerID: providerID, modelID: modelID)
                isModelPickerPresented = false
            }
        } addModelPopover: {
            modelPickerPopoverContent { providerID, modelID in
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

    func modelPickerPopoverContent(onSelect: @escaping (String, String) -> Void) -> some View {
        ModelPickerPopover(
            favoritesStore: favoriteModelsStore,
            providers: providers,
            selectedProviderID: conversationEntity.providerID,
            selectedModelID: conversationEntity.modelID,
            onSelect: onSelect
        )
    }
}
