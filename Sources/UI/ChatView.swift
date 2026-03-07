import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import Combine

struct ChatView: View {
    static let initialMessageRenderLimit = 24
    static let messageRenderPageSize = 40
    static let eagerCodeHighlightTailCount = 6
    static let nonLazyMessageStackThreshold = 16
    static let pinnedBottomRefreshDelays: [TimeInterval] = [0, 0.04, 0.14]

    private struct PendingCodexInteraction: Identifiable {
        let localThreadID: UUID
        let request: CodexInteractionRequest

        var id: UUID { request.id }
    }

    private var activeCodexInteractionBinding: Binding<PendingCodexInteraction?> {
        Binding(
            get: { pendingCodexInteractions.first },
            set: { newValue in
                guard newValue == nil, !pendingCodexInteractions.isEmpty else { return }
                pendingCodexInteractions.removeFirst()
            }
        )
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var streamingStore: ConversationStreamingStore
    @EnvironmentObject private var responseCompletionNotifier: ResponseCompletionNotifier
    @Bindable var conversationEntity: ConversationEntity
    let onRequestDeleteConversation: () -> Void
    @Binding var isAssistantInspectorPresented: Bool
    var onPersistConversationIfNeeded: () -> Void = {}
    var isSidebarHidden: Bool = false
    var onToggleSidebar: (() -> Void)? = nil
    @Query private var providers: [ProviderConfigEntity]
    @Query private var mcpServers: [MCPServerConfigEntity]

    @AppStorage(AppPreferenceKeys.sendWithCommandEnter) private var sendWithCommandEnter = false
    @AppStorage(AppPreferenceKeys.sttAddRecordingAsFile) private var sttAddRecordingAsFile = false

    @State private var controls: GenerationControls = GenerationControls()
    @State private var messageText = ""
    @State private var remoteVideoInputURLText = ""
    @State private var draftAttachments: [DraftAttachment] = []
    @State private var isFileImporterPresented = false
    @State private var isComposerDropTargeted = false
    @State private var isFullPageDropTargeted = false
    @State private var dropForwarderRef = DropForwarderRef()
    @State private var isComposerFocused = false
    @State private var editingUserMessageID: UUID?
    @State private var editingUserMessageText = ""
    @State private var isEditingUserMessageFocused = false
    @State private var composerHeight: CGFloat = 0
    @State private var composerTextContentHeight: CGFloat = 36
    @State private var isModelPickerPresented = false
    @State private var isAddModelPickerPresented = false
    @State private var messageRenderLimit: Int = Self.initialMessageRenderLimit
    @State private var pendingRestoreScrollMessageID: UUID?
    @State private var isPinnedToBottom = true
    @State private var pinnedBottomRefreshGeneration = 0
    @State private var isExpandedComposerPresented = false
    @State private var activeThreadID: UUID?

    // Cache expensive derived data so typing/streaming doesn't repeatedly sort/decode the entire history.
    @State private var cachedVisibleMessages: [MessageRenderItem] = []
    @State private var cachedMessagesVersion: Int = 0
    @State private var cachedMessageEntitiesByID: [UUID: MessageEntity] = [:]
    @State private var cachedToolResultsByCallID: [String: ToolResult] = [:]
    @State private var lastCacheRebuildMessageCount: Int = 0
    @State private var lastCacheRebuildUpdatedAt: Date = .distantPast
    @ObservedObject private var favoriteModelsStore = FavoriteModelsStore.shared

    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingThinkingBudgetSheet = false
    @State private var thinkingBudgetDraft = ""
    @State private var maxTokensDraft = ""
    @State private var showingCodexSessionSettingsSheet = false
    @State private var codexWorkingDirectoryDraft = ""
    @State private var codexWorkingDirectoryDraftError: String?
    @State private var codexSandboxModeDraft: CodexSandboxMode = .default
    @State private var codexPersonalityDraft: CodexPersonality?
    @State private var pendingCodexInteractions: [PendingCodexInteraction] = []

    @State private var showingContextCacheSheet = false
    @State private var showingAnthropicWebSearchSheet = false
    @State private var anthropicWebSearchDomainMode: AnthropicDomainFilterMode = .none
    @State private var anthropicWebSearchAllowedDomainsDraft = ""
    @State private var anthropicWebSearchBlockedDomainsDraft = ""
    @State private var anthropicWebSearchLocationDraft = WebSearchUserLocation()
    @State private var anthropicWebSearchDraftError: String?
    @State private var contextCacheDraft = ContextCacheControls(mode: .implicit)
    @State private var contextCacheTTLPreset = ContextCacheTTLPreset.providerDefault
    @State private var contextCacheCustomTTLDraft = ""
    @State private var contextCacheMinTokensDraft = ""
    @State private var contextCacheDraftError: String?
    @State private var contextCacheAdvancedExpanded = false

    @State private var showingImageGenerationSheet = false
    @State private var imageGenerationDraft = ImageGenerationControls()
    @State private var imageGenerationSeedDraft = ""
    @State private var imageGenerationCompressionQualityDraft = ""
    @State private var imageGenerationDraftError: String?
    @State private var mistralOCRConfigured = false
    @State private var deepSeekOCRConfigured = false
    @State private var textToSpeechConfigured = false
    @State private var speechToTextConfigured = false
    @State private var mistralOCRPluginEnabled = true
    @State private var deepSeekOCRPluginEnabled = true
    @State private var textToSpeechPluginEnabled = true
    @State private var speechToTextPluginEnabled = true
    @State private var webSearchPluginEnabled = true
    @State private var webSearchPluginConfigured = false
    @State private var isPreparingToSend = false
    @State private var prepareToSendStatus: String?
    @State private var prepareToSendTask: Task<Void, Never>?
    @EnvironmentObject private var ttsPlaybackManager: TextToSpeechPlaybackManager
    @StateObject private var speechToTextManager = SpeechToTextManager()

    private let conversationTitleGenerator = ConversationTitleGenerator()

    private var isStreaming: Bool {
        streamingStore.isStreaming(conversationID: conversationEntity.id)
    }

    private var isBusy: Bool {
        isStreaming || isPreparingToSend
    }

    private var streamingMessage: StreamingMessageState? {
        guard let activeThreadID else { return nil }
        return streamingStore.streamingState(conversationID: conversationEntity.id, threadID: activeThreadID)
    }

    private var streamingModelLabel: String? {
        guard let activeThreadID else { return nil }
        return streamingStore.streamingModelLabel(conversationID: conversationEntity.id, threadID: activeThreadID)
    }

    private func streamingMessage(for threadID: UUID) -> StreamingMessageState? {
        streamingStore.streamingState(conversationID: conversationEntity.id, threadID: threadID)
    }

    private func streamingModelLabel(for threadID: UUID) -> String? {
        streamingStore.streamingModelLabel(conversationID: conversationEntity.id, threadID: threadID)
    }

    private var sortedModelThreads: [ConversationModelThreadEntity] {
        ChatThreadSupport.sortedThreads(in: conversationEntity.modelThreads)
    }

    private var selectedModelThreads: [ConversationModelThreadEntity] {
        ChatThreadSupport.selectedThreads(
            from: sortedModelThreads,
            activeThread: activeModelThread
        )
    }

    private var secondaryToolbarThreads: [ConversationModelThreadEntity] {
        ChatThreadSupport.secondaryToolbarThreads(
            from: sortedModelThreads,
            activeThread: activeModelThread
        )
    }

    private var activeModelThread: ConversationModelThreadEntity? {
        ChatThreadSupport.activeThread(
            in: sortedModelThreads,
            preferredID: activeThreadID ?? conversationEntity.activeThreadID
        )
    }

    private var composerOverlay: some View {
        CompactComposerOverlayView(
            messageText: $messageText,
            remoteVideoURLText: $remoteVideoInputURLText,
            draftAttachments: $draftAttachments,
            isComposerDropTargeted: $isComposerDropTargeted,
            isComposerFocused: $isComposerFocused,
            composerTextContentHeight: $composerTextContentHeight,
            sendWithCommandEnter: sendWithCommandEnter,
            isBusy: isBusy,
            canSendDraft: canSendDraft,
            showsRemoteVideoURLField: supportsExplicitRemoteVideoURLInput,
            isPreparingToSend: isPreparingToSend,
            prepareToSendStatus: prepareToSendStatus,
            isRecording: speechToTextManager.isRecording,
            isTranscribing: speechToTextManager.isTranscribing,
            recordingDurationText: formattedRecordingDuration,
            transcribingStatusText: speechToTextUsesAudioAttachment ? "Attaching audio…" : "Transcribing…",
            onDropFileURLs: handleDroppedFileURLs,
            onDropImages: handleDroppedImages,
            onSubmit: handleComposerSubmit,
            onCancel: handleComposerCancel,
            onRemoveAttachment: removeDraftAttachment,
            onExpand: { isExpandedComposerPresented = true },
            onSend: sendMessage
        ) {
            composerControlsRow
        }
    }

    @ViewBuilder
    private var composerControlsRow: some View {
        HStack(spacing: 6) {
            if speechToTextPluginEnabled || speechToTextManagerActive {
                composerButtonControl(
                    systemName: speechToTextSystemImageName,
                    isActive: speechToTextManagerActive,
                    badgeText: speechToTextBadgeText,
                    help: speechToTextHelpText,
                    activeColor: speechToTextActiveColor,
                    disabled: isBusy || speechToTextManager.isTranscribing || (!speechToTextReadyForCurrentMode && !speechToTextManager.isRecording),
                    action: toggleSpeechToText
                )
            }

            composerButtonControl(
                systemName: "paperclip",
                isActive: !draftAttachments.isEmpty,
                badgeText: draftAttachments.isEmpty ? nil : "\(draftAttachments.count)",
                help: fileAttachmentHelpText,
                disabled: isBusy
            ) {
                isFileImporterPresented = true
            }

            if supportsPDFProcessingControl {
                composerMenuControl(
                    systemName: "doc.text.magnifyingglass",
                    isActive: resolvedPDFProcessingMode != .native,
                    badgeText: pdfProcessingBadgeText,
                    help: pdfProcessingHelpText
                ) {
                    pdfProcessingMenuContent
                }
            }

            if supportsReasoningControl {
                composerMenuControl(
                    systemName: "brain",
                    isActive: isReasoningEnabled,
                    badgeText: reasoningBadgeText,
                    help: reasoningHelpText
                ) {
                    reasoningMenuContent
                }
            }

            if supportsOpenAIServiceTierControl {
                composerMenuControl(
                    systemName: "speedometer",
                    isActive: controls.openAIServiceTier != nil,
                    badgeText: openAIServiceTierBadgeText,
                    help: openAIServiceTierHelpText
                ) {
                    openAIServiceTierMenuContent
                }
            }

            if supportsWebSearchControl {
                composerMenuControl(
                    systemName: "globe",
                    isActive: isWebSearchEnabled,
                    badgeText: webSearchBadgeText,
                    help: webSearchHelpText
                ) {
                    webSearchMenuContent
                }
            }

            if supportsContextCacheControl {
                composerMenuControl(
                    systemName: "archivebox",
                    isActive: isContextCacheEnabled,
                    badgeText: contextCacheBadgeText,
                    help: contextCacheHelpText
                ) {
                    contextCacheMenuContent
                }
            }

            if supportsMCPToolsControl {
                composerMenuControl(
                    systemName: "hammer",
                    isActive: supportsMCPToolsControl && isMCPToolsEnabled,
                    badgeText: mcpToolsBadgeText,
                    help: mcpToolsHelpText
                ) {
                    mcpToolsMenuContent
                }
            }

            if supportsCodexSessionControl {
                composerButtonControl(
                    systemName: "terminal",
                    isActive: codexSessionOverrideCount > 0,
                    badgeText: codexSessionBadgeText,
                    help: codexSessionHelpText,
                    action: openCodexSessionSettingsEditor
                )
            }

            if supportsImageGenerationControl {
                composerMenuControl(
                    systemName: "photo",
                    isActive: isImageGenerationConfigured,
                    badgeText: imageGenerationBadgeText,
                    help: imageGenerationHelpText
                ) {
                    imageGenerationMenuContent
                }
            }

            if supportsVideoGenerationControl {
                composerMenuControl(
                    systemName: "film",
                    isActive: isVideoGenerationConfigured,
                    badgeText: videoGenerationBadgeText,
                    help: videoGenerationHelpText
                ) {
                    videoGenerationMenuContent
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 1)
    }

    private func composerButtonControl(
        systemName: String,
        isActive: Bool,
        badgeText: String?,
        help: String,
        activeColor: Color = .accentColor,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ComposerControlIconLabel(
                systemName: systemName,
                isActive: isActive,
                badgeText: badgeText,
                activeColor: activeColor
            )
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(disabled)
    }

    private func composerMenuControl<MenuContent: View>(
        systemName: String,
        isActive: Bool,
        badgeText: String?,
        help: String,
        activeColor: Color = .accentColor,
        @ViewBuilder content: @escaping () -> MenuContent
    ) -> some View {
        Menu(content: content) {
            ComposerControlIconLabel(
                systemName: systemName,
                isActive: isActive,
                badgeText: badgeText,
                activeColor: activeColor
            )
        }
        .menuStyle(.borderlessButton)
        .help(help)
    }

    private var messageInteractionContext: ChatMessageInteractionContext {
        ChatMessageInteractionContext(
            actionsEnabled: !isStreaming,
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
            }
        )
    }

    private var assistantDisplayName: String {
        conversationEntity.assistant?.displayName ?? "Assistant"
    }

    private var singleThreadRenderContext: ChatThreadRenderContext {
        ChatThreadRenderContext(
            visibleMessages: cachedVisibleMessages,
            messageEntitiesByID: cachedMessageEntitiesByID,
            toolResultsByCallID: cachedToolResultsByCallID
        )
    }

    private var selectedThreadRenderContexts: [UUID: ChatThreadRenderContext] {
        Dictionary(uniqueKeysWithValues: selectedModelThreads.map { thread in
            (thread.id, threadRenderContext(threadID: thread.id))
        })
    }

    private func threadRenderContext(threadID: UUID) -> ChatThreadRenderContext {
        let ordered = ChatMessageRenderPipeline.orderedMessages(
            from: conversationEntity.messages,
            threadID: threadID
        )
        let fallbackModelLabel = sortedModelThreads
            .first(where: { $0.id == threadID })
            .map { modelName(id: $0.modelID, providerID: $0.providerID) }
            ?? currentModelName

        return ChatMessageRenderPipeline.makeRenderContext(
            from: ordered,
            fallbackModelLabel: fallbackModelLabel,
            assistantProviderIconID: { providerID in
                providerIconID(for: providerID)
            }
        )
    }

    private func singleThreadMessageStage(geometry: GeometryProxy) -> some View {
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
            messageRenderLimit: $messageRenderLimit,
            pendingRestoreScrollMessageID: $pendingRestoreScrollMessageID,
            isPinnedToBottom: $isPinnedToBottom,
            pinnedBottomRefreshGeneration: $pinnedBottomRefreshGeneration
        )
    }

    private func multiThreadMessageStage(geometry: GeometryProxy) -> some View {
        ChatMultiModelStageView(
            conversationMessageCount: conversationEntity.messages.count,
            containerSize: geometry.size,
            threads: selectedModelThreads,
            contextsByThreadID: selectedThreadRenderContexts,
            assistantDisplayName: assistantDisplayName,
            composerHeight: composerHeight,
            isStreaming: isStreaming,
            activeThreadID: activeModelThread?.id,
            eagerCodeHighlightTailCount: Self.eagerCodeHighlightTailCount,
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
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            detailHeaderBar
            conversationStage
        }
        .environment(\.dropForwarderRef, dropForwarderRef)
        .onDrop(of: [.fileURL, .url, .text, .image, .data, .item], isTargeted: $isFullPageDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            fullPageDropOverlay
        }
        .onAppear(perform: handleChatAppear)
        .onChange(of: conversationEntity.id) { _, _ in
            handleConversationSwitch()
        }
        .onChange(of: conversationEntity.messages.count) { _, _ in
            rebuildMessageCachesIfNeeded()
        }
        .onChange(of: conversationEntity.updatedAt) { _, _ in
            rebuildMessageCachesIfNeeded()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image, .movie, .audio, .pdf],
            allowsMultipleSelection: true
        ) { result in
            handleAttachmentImport(result)
        }
        .sheet(isPresented: $showingThinkingBudgetSheet) {
            ThinkingBudgetSheetView(
                usesAdaptiveThinking: anthropicUsesAdaptiveThinking,
                usesEffortMode: anthropicUsesEffortMode,
                modelID: conversationEntity.modelID,
                modelMaxOutputTokens: AnthropicModelLimits.maxOutputTokens(for: conversationEntity.modelID),
                supportsMaxEffort: AnthropicModelLimits.supportsMaxEffort(for: conversationEntity.modelID),
                thinkingBudgetDraft: $thinkingBudgetDraft,
                maxTokensDraft: $maxTokensDraft,
                effortSelection: anthropicEffortBinding,
                isValid: isThinkingBudgetDraftValid,
                validationWarning: thinkingBudgetValidationWarning,
                onCancel: { showingThinkingBudgetSheet = false },
                onSave: {
                    applyThinkingBudgetDraft()
                    showingThinkingBudgetSheet = false
                }
            )
        }
        .sheet(isPresented: $showingContextCacheSheet) {
            ContextCacheSheetView(
                draft: $contextCacheDraft,
                ttlPreset: $contextCacheTTLPreset,
                customTTLDraft: $contextCacheCustomTTLDraft,
                minTokensDraft: $contextCacheMinTokensDraft,
                advancedExpanded: $contextCacheAdvancedExpanded,
                draftError: $contextCacheDraftError,
                providerType: providerType,
                supportsExplicitMode: supportsExplicitContextCacheMode,
                supportsStrategy: supportsContextCacheStrategy,
                supportsTTL: supportsContextCacheTTL,
                supportsAdvancedOptions: contextCacheSupportsAdvancedOptions,
                summaryText: contextCacheSummaryText,
                guidanceText: contextCacheGuidanceText,
                isValid: isContextCacheDraftValid,
                onCancel: { showingContextCacheSheet = false },
                onSave: { applyContextCacheDraft() }
            )
        }
        .sheet(isPresented: $showingAnthropicWebSearchSheet) {
            AnthropicWebSearchSheetView(
                domainMode: $anthropicWebSearchDomainMode,
                allowedDomainsDraft: $anthropicWebSearchAllowedDomainsDraft,
                blockedDomainsDraft: $anthropicWebSearchBlockedDomainsDraft,
                locationDraft: $anthropicWebSearchLocationDraft,
                draftError: $anthropicWebSearchDraftError,
                onCancel: { showingAnthropicWebSearchSheet = false },
                onApply: { applyAnthropicWebSearchDraft() }
            )
        }
        .sheet(isPresented: $showingImageGenerationSheet) {
            ImageGenerationSheetView(
                draft: $imageGenerationDraft,
                seedDraft: $imageGenerationSeedDraft,
                compressionQualityDraft: $imageGenerationCompressionQualityDraft,
                draftError: $imageGenerationDraftError,
                providerType: providerType,
                supportsImageSizeControl: supportsCurrentModelImageSizeControl,
                supportedAspectRatios: supportedCurrentModelImageAspectRatios,
                supportedImageSizes: supportedCurrentModelImageSizes,
                isValid: isImageGenerationDraftValid,
                onCancel: { showingImageGenerationSheet = false },
                onSave: { applyImageGenerationDraft() }
            )
        }
        .sheet(isPresented: $showingCodexSessionSettingsSheet) {
            CodexSessionSettingsSheetView(
                workingDirectoryDraft: $codexWorkingDirectoryDraft,
                workingDirectoryDraftError: $codexWorkingDirectoryDraftError,
                sandboxModeDraft: $codexSandboxModeDraft,
                personalityDraft: $codexPersonalityDraft,
                onChooseDirectory: { pickCodexWorkingDirectory() },
                onSelectPreset: { preset in
                    codexWorkingDirectoryDraft = preset.path
                    codexWorkingDirectoryDraftError = nil
                },
                onResetWorkingDirectory: {
                    codexWorkingDirectoryDraft = ""
                    codexWorkingDirectoryDraftError = nil
                },
                onCancel: { showingCodexSessionSettingsSheet = false },
                onSave: { applyCodexSessionSettingsDraft() }
            )
        }
        .sheet(item: activeCodexInteractionBinding) { item in
            CodexInteractionSheetView(request: item.request) { response in
                resolveCodexInteraction(item, response: response)
            }
        }
        .task {
            // Chat-local state is already prepared in onAppear / onChange.
            // Avoid repeating these mutations here to prevent extra render churn.
            await refreshExtensionCredentialsStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pluginCredentialsDidChange)) { _ in
            Task {
                await refreshExtensionCredentialsStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .codexWorkingDirectoryPresetsDidChange)) { _ in }
        .focusedSceneValue(\.chatActions, chatFocusedActions)
    }

    private var conversationStage: some View {
        ZStack(alignment: .bottom) {
            messageStage
            floatingComposer
        }
        .onPreferenceChange(ComposerHeightPreferenceKey.self) { newValue in
            if abs(composerHeight - newValue) > 0.5 {
                composerHeight = newValue
            }
        }
        .background(JinSemanticColor.detailSurface)
        .overlay {
            expandedComposerOverlay
        }
        .animation(.easeInOut(duration: 0.2), value: isExpandedComposerPresented)
    }

    private var messageStage: some View {
        GeometryReader { geometry in
            if selectedModelThreads.count > 1 {
                multiThreadMessageStage(geometry: geometry)
            } else {
                singleThreadMessageStage(geometry: geometry)
            }
        }
    }

    private var floatingComposer: some View {
        composerOverlay
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: ComposerHeightPreferenceKey.self, value: geo.size.height)
                }
            }
    }

    @ViewBuilder
    private var expandedComposerOverlay: some View {
        if isExpandedComposerPresented {
            ExpandedComposerOverlay(
                messageText: $messageText,
                remoteVideoURLText: $remoteVideoInputURLText,
                draftAttachments: $draftAttachments,
                isPresented: $isExpandedComposerPresented,
                isComposerDropTargeted: $isComposerDropTargeted,
                isBusy: isBusy,
                canSendDraft: canSendDraft,
                showsRemoteVideoURLField: supportsExplicitRemoteVideoURLInput,
                onSend: {
                    isExpandedComposerPresented = false
                    sendMessage()
                },
                onDropFileURLs: handleDroppedFileURLs,
                onDropImages: handleDroppedImages,
                onRemoveAttachment: removeDraftAttachment
            )
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
        }
    }

    private var fullPageDropOverlay: some View {
        ZStack {
            Color.accentColor.opacity(0.08)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Drop to attach")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous))
        }
        .allowsHitTesting(false)
        .opacity(isFullPageDropTargeted ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: isFullPageDropTargeted)
    }

    private var chatFocusedActions: ChatFocusedActions {
        ChatFocusedActions(
            canAttach: !isBusy,
            canStopStreaming: isBusy,
            focusComposer: { isComposerFocused = true },
            openModelPicker: { isModelPickerPresented.toggle() },
            attach: { isFileImporterPresented = true },
            stopStreaming: {
                guard isBusy else { return }
                sendMessage()
            },
            toggleExpandedComposer: {
                isExpandedComposerPresented.toggle()
            }
        )
    }

    private func handleChatAppear() {
        isComposerFocused = true
        installWKWebViewDropForwarder()
        // loadControlsFromConversation internally calls ensureModelThreadsInitializedIfNeeded
        // and syncActiveThreadSelection, so calling them separately is redundant and causes
        // extra render cycles that make the header flicker.
        loadControlsFromConversation()
        rebuildMessageCaches()
    }

    private func handleConversationSwitch() {
        // Switching chats: reset transient per-chat state and rebuild caches.
        cancelEditingUserMessage()
        messageRenderLimit = Self.initialMessageRenderLimit
        pendingRestoreScrollMessageID = nil
        isPinnedToBottom = true
        isExpandedComposerPresented = false
        remoteVideoInputURLText = ""
        // loadControlsFromConversation internally calls ensureModelThreadsInitializedIfNeeded
        // and syncActiveThreadSelection, so calling them separately is redundant.
        loadControlsFromConversation()
        rebuildMessageCaches()
    }

    private func handleAttachmentImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task { await importAttachments(from: urls) }
        case .failure(let error):
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    // MARK: - Helpers & Subviews

    private var trimmedMessageText: String {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedRemoteVideoInputURLText: String {
        remoteVideoInputURLText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var supportsExplicitRemoteVideoURLInput: Bool {
        supportsVideoGenerationControl && providerType == .xai
    }

    private var canSendDraft: Bool {
        !trimmedMessageText.isEmpty || !draftAttachments.isEmpty
    }

    private var speechToTextManagerActive: Bool {
        speechToTextManager.isRecording || speechToTextManager.isTranscribing
    }

    private var speechToTextSystemImageName: String {
        if speechToTextManager.isTranscribing { return "waveform" }
        if speechToTextManager.isRecording { return "mic.fill" }
        return "mic"
    }

    private var speechToTextActiveColor: Color {
        speechToTextManager.isRecording ? .red : .accentColor
    }

    private var speechToTextBadgeText: String? {
        speechToTextManager.isTranscribing ? "…" : nil
    }

    private var speechToTextUsesAudioAttachment: Bool {
        sttAddRecordingAsFile && supportsAudioInput
    }

    private var speechToTextReadyForCurrentMode: Bool {
        speechToTextUsesAudioAttachment || speechToTextConfigured
    }

    private var speechToTextHelpText: String {
        if speechToTextManager.isTranscribing {
            return speechToTextUsesAudioAttachment ? "Attaching audio…" : "Transcribing…"
        }
        if speechToTextManager.isRecording {
            return speechToTextUsesAudioAttachment ? "Stop recording and attach audio" : "Stop recording"
        }
        if !speechToTextPluginEnabled { return "Speech to Text is turned off in Settings → Plugins" }
        if speechToTextUsesAudioAttachment {
            return "Record audio and attach it to the draft message"
        }
        if sttAddRecordingAsFile && !supportsAudioInput {
            if speechToTextConfigured {
                return "Current model doesn't support audio input; using transcription fallback."
            }
            return "Current model doesn't support audio input. Configure Speech to Text for transcription fallback."
        }
        if !speechToTextConfigured { return "Configure Speech to Text in Settings → Plugins → Speech to Text" }
        return "Start recording"
    }

    private var fileAttachmentHelpText: String {
        let base = supportsAudioInput
            ? "Attach images / videos / audio / PDFs"
            : "Attach images / videos / PDFs"
        return supportsNativePDF ? "\(base) (Native PDF support ✓)" : base
    }

    private var formattedRecordingDuration: String {
        let total = max(0, Int(speechToTextManager.elapsedSeconds.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func toggleSpeechToText() {
        Task { @MainActor in
            do {
                if speechToTextManager.isRecording {
                    if speechToTextUsesAudioAttachment {
                        guard draftAttachments.count < AttachmentConstants.maxDraftAttachments else {
                            throw AttachmentImportError(message: "You can attach up to \(AttachmentConstants.maxDraftAttachments) files per message.")
                        }

                        let clip = try await speechToTextManager.stopAndCollectRecording()
                        let attachment = try await AttachmentImportPipeline.importRecordedAudioClip(clip)
                        draftAttachments.append(attachment)
                        isComposerFocused = true
                        return
                    }

                    let config = try await currentSpeechToTextTranscriptionConfig()
                    let text = try await speechToTextManager.stopAndTranscribe(config: config)
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        if messageText.isEmpty {
                            messageText = trimmed
                        } else {
                            let separator = messageText.hasSuffix("\n") ? "\n" : "\n\n"
                            messageText += separator + trimmed
                        }
                        isComposerFocused = true
                    }
                    return
                }

                guard speechToTextPluginEnabled else { return }
                if speechToTextUsesAudioAttachment {
                    guard draftAttachments.count < AttachmentConstants.maxDraftAttachments else {
                        throw AttachmentImportError(message: "You can attach up to \(AttachmentConstants.maxDraftAttachments) files per message.")
                    }
                    try await speechToTextManager.startRecording()
                    return
                }

                _ = try await currentSpeechToTextTranscriptionConfig() // Validate configured
                try await speechToTextManager.startRecording()
            } catch {
                speechToTextManager.cancelAndCleanup()
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func removeDraftAttachment(_ attachment: DraftAttachment) {
        draftAttachments.removeAll { $0.id == attachment.id }
        try? FileManager.default.removeItem(at: attachment.fileURL)
    }

    /// Install a static drop forwarder on MarkdownWKWebView so files
    /// dropped directly onto rendered markdown messages are routed to the
    /// same attachment pipeline used by the SwiftUI `.onDrop` handler.
    /// WKWebView internally re-registers drag types via private APIs,
    /// making it impossible to prevent it from claiming drags. Instead of
    /// fighting it, we accept the drags at the WKWebView level and
    /// forward them here.
    private func installWKWebViewDropForwarder() {
        let coordinator = FileDropCaptureView.Coordinator(
            isDropTargeted: $isFullPageDropTargeted,
            onDropFileURLs: handleDroppedFileURLs,
            onDropImages: handleDroppedImages,
            onDropTextChunks: handleDroppedTextChunks
        )
        dropForwarderRef.onDragTargetChanged = { isTargeted in coordinator.setDropTargeted(isTargeted) }
        dropForwarderRef.onPerformDrop = { draggingInfo in coordinator.performDrop(draggingInfo) }
    }

    private func handleDroppedFileURLs(_ urls: [URL]) -> Bool {
        var seen = Set<URL>()
        let uniqueURLs = urls.filter { seen.insert($0).inserted }
        guard !uniqueURLs.isEmpty else { return false }

        if isBusy {
            errorMessage = "Stop generating (or wait for PDF processing) to attach files."
            showingError = true
            return true
        }

        Task { await importAttachments(from: uniqueURLs) }
        return true
    }

    private func handleDroppedImages(_ images: [NSImage]) -> Bool {
        guard !images.isEmpty else { return false }

        if isBusy {
            errorMessage = "Stop generating (or wait for PDF processing) to attach files."
            showingError = true
            return true
        }

        var urls: [URL] = []
        var errors: [String] = []

        for image in images {
            guard let url = AttachmentImportPipeline.writeTemporaryPNG(from: image) else {
                errors.append("Failed to read dropped image.")
                continue
            }
            urls.append(url)
        }

        if !urls.isEmpty {
            Task { await importAttachments(from: urls) }
        }

        if !errors.isEmpty {
            errorMessage = errors.joined(separator: "\n")
            showingError = true
        }

        return true
    }

    private func handleComposerSubmit() {
        guard !isBusy else { return }
        sendMessage()
    }

    private func handleComposerCancel() -> Bool {
        guard isBusy else { return false }
        sendMessage()
        return true
    }

    private func handleDroppedTextChunks(_ textChunks: [String]) -> Bool {
        if isBusy {
            errorMessage = "Stop generating (or wait for PDF processing) to drop text."
            showingError = true
            return true
        }
        return appendTextChunksToComposer(textChunks)
    }

    @discardableResult
    private func appendTextChunksToComposer(_ textChunks: [String]) -> Bool {
        let insertion = textChunks
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !insertion.isEmpty else { return false }

        if messageText.isEmpty {
            messageText = insertion
        } else {
            let separator = messageText.hasSuffix("\n") ? "" : "\n"
            messageText += separator + insertion
        }
        return true
    }

    private static func persistDroppedFileRepresentation(_ temporaryURL: URL) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JinDroppedFiles", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let filename = temporaryURL.lastPathComponent.isEmpty ? "Attachment" : temporaryURL.lastPathComponent
        let stableURL = dir.appendingPathComponent("\(UUID().uuidString)-\(filename)")
        try FileManager.default.copyItem(at: temporaryURL, to: stableURL)
        return stableURL
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        isFullPageDropTargeted = false

        if isBusy {
            errorMessage = "Stop generating (or wait for PDF processing) to attach files."
            showingError = true
            return true
        }

        var didScheduleWork = false
        let group = DispatchGroup()
        let lock = NSLock()

        var droppedFileURLs: [URL] = []
        var droppedTextChunks: [String] = []
        var errors: [String] = []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                didScheduleWork = true
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    if let url = AttachmentImportPipeline.urlFromItemProviderItem(item) {
                        lock.lock()
                        if url.isFileURL {
                            droppedFileURLs.append(url)
                        } else {
                            droppedTextChunks.append(url.absoluteString)
                        }
                        lock.unlock()
                        group.leave()
                        return
                    }

                    if let representationTypeID = AttachmentImportPipeline.preferredFileRepresentationTypeIdentifier(from: provider.registeredTypeIdentifiers) {
                        provider.loadFileRepresentation(forTypeIdentifier: representationTypeID) { url, fallbackError in
                            defer { group.leave() }

                            guard let url else {
                                if let fallbackError {
                                    lock.lock()
                                    errors.append(fallbackError.localizedDescription)
                                    lock.unlock()
                                } else if let error {
                                    lock.lock()
                                    errors.append(error.localizedDescription)
                                    lock.unlock()
                                }
                                return
                            }

                            do {
                                let stableURL = try Self.persistDroppedFileRepresentation(url)
                                lock.lock()
                                droppedFileURLs.append(stableURL)
                                lock.unlock()
                            } catch {
                                lock.lock()
                                errors.append(error.localizedDescription)
                                lock.unlock()
                            }
                        }
                        return
                    }

                    if let error {
                        lock.lock()
                        errors.append(error.localizedDescription)
                        lock.unlock()
                    }

                    group.leave()
                }
                continue
            }

            if provider.canLoadObject(ofClass: NSImage.self) {
                didScheduleWork = true
                group.enter()
                _ = provider.loadObject(ofClass: NSImage.self) { object, error in
                    defer { group.leave() }

                    guard let image = object as? NSImage else {
                        if let error {
                            lock.lock()
                            errors.append(error.localizedDescription)
                            lock.unlock()
                        }
                        return
                    }

                    guard let tempURL = AttachmentImportPipeline.writeTemporaryPNG(from: image) else {
                        lock.lock()
                        errors.append("Failed to read dropped image.")
                        lock.unlock()
                        return
                    }

                    lock.lock()
                    droppedFileURLs.append(tempURL)
                    lock.unlock()
                }
                continue
            }

            if provider.canLoadObject(ofClass: URL.self) {
                didScheduleWork = true
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { object, error in
                    defer { group.leave() }

                    if let url = object {
                        lock.lock()
                        if url.isFileURL {
                            droppedFileURLs.append(url)
                        } else {
                            droppedTextChunks.append(url.absoluteString)
                        }
                        lock.unlock()
                        return
                    }

                    if let error {
                        lock.lock()
                        errors.append(error.localizedDescription)
                        lock.unlock()
                    }
                }
                continue
            }

            if provider.canLoadObject(ofClass: NSString.self) {
                didScheduleWork = true
                group.enter()
                _ = provider.loadObject(ofClass: NSString.self) { object, error in
                    defer { group.leave() }

                    if let text = object as? String {
                        let parsed = AttachmentImportPipeline.parseDroppedString(text)
                        lock.lock()
                        droppedFileURLs.append(contentsOf: parsed.fileURLs)
                        droppedTextChunks.append(contentsOf: parsed.textChunks)
                        lock.unlock()
                        return
                    }

                    if let error {
                        lock.lock()
                        errors.append(error.localizedDescription)
                        lock.unlock()
                    }
                }
                continue
            }

            // Fallback: handle file promises or generic file-backed providers
            // that don't expose URL/image/text objects directly.
            let representationTypeID = AttachmentImportPipeline.preferredFileRepresentationTypeIdentifier(from: provider.registeredTypeIdentifiers)
            if let representationTypeID {
                didScheduleWork = true
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: representationTypeID) { url, error in
                    defer { group.leave() }

                    guard let url else {
                        if let error {
                            lock.lock()
                            errors.append(error.localizedDescription)
                            lock.unlock()
                        }
                        return
                    }

                    do {
                        let stableURL = try Self.persistDroppedFileRepresentation(url)
                        lock.lock()
                        droppedFileURLs.append(stableURL)
                        lock.unlock()
                    } catch {
                        lock.lock()
                        errors.append(error.localizedDescription)
                        lock.unlock()
                    }
                }
                continue
            }
        }

        guard didScheduleWork else { return false }

        let finalizeLock = NSLock()
        var didFinalize = false

        let finalize: () -> Void = {
            finalizeLock.lock()
            guard !didFinalize else {
                finalizeLock.unlock()
                return
            }
            didFinalize = true
            finalizeLock.unlock()

            lock.lock()
            let uniqueFileURLs = Array(Set(droppedFileURLs))
            let textChunks = droppedTextChunks
            let dropErrors = errors
            lock.unlock()

            isFullPageDropTargeted = false

            if !uniqueFileURLs.isEmpty {
                Task { await importAttachments(from: uniqueFileURLs) }
            }
            if !textChunks.isEmpty {
                appendTextChunksToComposer(textChunks)
            }

            if !dropErrors.isEmpty {
                errorMessage = dropErrors.joined(separator: "\n")
                showingError = true
            }
        }

        group.notify(queue: .main, execute: finalize)

        return true
    }

    private func importAttachments(from urls: [URL]) async {
        guard !urls.isEmpty else { return }
        guard !isStreaming else { return }

        let remainingSlots = max(0, AttachmentConstants.maxDraftAttachments - draftAttachments.count)
        guard remainingSlots > 0 else {
            await MainActor.run {
                errorMessage = "You can attach up to \(AttachmentConstants.maxDraftAttachments) files per message."
                showingError = true
            }
            return
        }

        let urlsToImport = Array(urls.prefix(remainingSlots))

        let (newAttachments, errors) = await Task.detached(priority: .userInitiated) {
            await AttachmentImportPipeline.importInBackground(from: urlsToImport)
        }.value

        await MainActor.run {
            if !newAttachments.isEmpty {
                draftAttachments.append(contentsOf: newAttachments)
            }
            if !errors.isEmpty {
                errorMessage = errors.joined(separator: "\n")
                showingError = true
            }
        }
    }

    private var selectedModelInfo: ModelInfo? {
        guard let model = ChatModelCapabilitySupport.resolvedModelInfo(
            modelID: conversationEntity.modelID,
            providerEntity: currentProvider,
            providerType: providerType,
            availableModels: currentProvider?.allModels
        ) else {
            return nil
        }

        return ChatModelCapabilitySupport.normalizedSelectedModelInfo(
            model,
            providerType: providerType
        )
    }

    private var resolvedModelSettings: ResolvedModelSettings? {
        guard let model = selectedModelInfo else { return nil }
        return ModelSettingsResolver.resolve(model: model, providerType: providerType)
    }

    private var lowerModelID: String {
        conversationEntity.modelID.lowercased()
    }

    private func resolvedModelInfo(
        for modelID: String,
        providerEntity: ProviderConfigEntity?,
        providerType: ProviderType?,
        availableModels: [ModelInfo]? = nil
    ) -> ModelInfo? {
        ChatModelCapabilitySupport.resolvedModelInfo(
            modelID: modelID,
            providerEntity: providerEntity,
            providerType: providerType,
            availableModels: availableModels
        )
    }

    private func effectiveModelID(
        for modelID: String,
        providerEntity: ProviderConfigEntity?,
        providerType: ProviderType?,
        availableModels: [ModelInfo]? = nil
    ) -> String {
        ChatModelCapabilitySupport.effectiveModelID(
            modelID: modelID,
            providerEntity: providerEntity,
            providerType: providerType,
            availableModels: availableModels
        )
    }

    private func migrateThreadModelIDIfNeeded(
        _ thread: ConversationModelThreadEntity,
        resolvedModelID: String
    ) {
        guard resolvedModelID != thread.modelID else { return }
        thread.modelID = resolvedModelID
        if conversationEntity.activeThreadID == thread.id {
            conversationEntity.modelID = resolvedModelID
        }
        conversationEntity.updatedAt = Date()
        try? modelContext.save()
    }

    private func canonicalModelID(for providerID: String, modelID: String) -> String {
        let providerEntity = providers.first(where: { $0.id == providerID })
        let providerType = providerEntity.flatMap { ProviderType(rawValue: $0.typeRaw) }
        return effectiveModelID(
            for: modelID,
            providerEntity: providerEntity,
            providerType: providerType,
            availableModels: providerEntity?.allModels
        )
    }

    private func canonicalizeThreadModelIDIfNeeded(_ thread: ConversationModelThreadEntity) {
        let resolved = canonicalModelID(for: thread.providerID, modelID: thread.modelID)
        migrateThreadModelIDIfNeeded(thread, resolvedModelID: resolved)
    }

    private func normalizedSelectedModelInfo(_ model: ModelInfo) -> ModelInfo {
        ChatModelCapabilitySupport.normalizedSelectedModelInfo(
            model,
            providerType: providerType
        )
    }

    private func normalizedFireworksModelInfo(_ model: ModelInfo) -> ModelInfo {
        ChatModelCapabilitySupport.normalizedFireworksModelInfo(model)
    }

    private var isImageGenerationModelID: Bool {
        ChatModelCapabilitySupport.isImageGenerationModelID(
            providerType: providerType,
            lowerModelID: lowerModelID,
            openAIImageGenerationModelIDs: Self.openAIImageGenerationModelIDs,
            xAIImageGenerationModelIDs: Self.xAIImageGenerationModelIDs,
            geminiImageGenerationModelIDs: Self.geminiImageGenerationModelIDs
        )
    }

    private var isVideoGenerationModelID: Bool {
        ChatModelCapabilitySupport.isVideoGenerationModelID(
            providerType: providerType,
            lowerModelID: lowerModelID,
            xAIVideoGenerationModelIDs: Self.xAIVideoGenerationModelIDs,
            googleVideoGenerationModelIDs: Self.googleVideoGenerationModelIDs
        )
    }

    private var supportsNativePDF: Bool {
        ChatModelCapabilitySupport.supportsNativePDF(
            supportsMediaGenerationControl: supportsMediaGenerationControl,
            providerType: providerType,
            resolvedModelSettings: resolvedModelSettings,
            lowerModelID: lowerModelID
        )
    }

    private var supportsVision: Bool {
        ChatModelCapabilitySupport.supportsVision(
            resolvedModelSettings: resolvedModelSettings,
            supportsImageGenerationControl: supportsImageGenerationControl,
            supportsVideoGenerationControl: supportsVideoGenerationControl
        )
    }

    private var supportsAudioInput: Bool {
        ChatModelCapabilitySupport.supportsAudioInput(
            isMistralTranscriptionOnlyModelID: isMistralTranscriptionOnlyModelID,
            resolvedModelSettings: resolvedModelSettings,
            supportsMediaGenerationControl: supportsMediaGenerationControl,
            providerType: providerType,
            lowerModelID: lowerModelID,
            openAIAudioInputModelIDs: Self.openAIAudioInputModelIDs,
            mistralAudioInputModelIDs: Self.mistralAudioInputModelIDs,
            geminiAudioInputModelIDs: Self.geminiAudioInputModelIDs,
            compatibleAudioInputModelIDs: Self.compatibleAudioInputModelIDs,
            fireworksAudioInputModelIDs: Self.fireworksAudioInputModelIDs
        )
    }

    private var isMistralTranscriptionOnlyModelID: Bool {
        ChatModelCapabilitySupport.isMistralTranscriptionOnlyModelID(
            providerType: providerType,
            lowerModelID: lowerModelID,
            mistralTranscriptionOnlyModelIDs: Self.mistralTranscriptionOnlyModelIDs
        )
    }

    private var supportsImageGenerationControl: Bool {
        resolvedModelSettings?.capabilities.contains(.imageGeneration) == true || isImageGenerationModelID
    }

    private var supportsVideoGenerationControl: Bool {
        resolvedModelSettings?.capabilities.contains(.videoGeneration) == true || isVideoGenerationModelID
    }

    private var supportsMediaGenerationControl: Bool {
        supportsImageGenerationControl || supportsVideoGenerationControl
    }

    private var supportsImageGenerationWebSearch: Bool {
        ChatModelCapabilitySupport.supportsImageGenerationWebSearch(
            supportsImageGenerationControl: supportsImageGenerationControl,
            resolvedModelSettings: resolvedModelSettings,
            providerType: providerType,
            conversationModelID: conversationEntity.modelID
        )
    }

    private var supportsPDFProcessingControl: Bool {
        guard providerType != .codexAppServer else { return false }
        return true
    }

    private var supportsCurrentModelImageSizeControl: Bool {
        ChatModelCapabilitySupport.supportsCurrentModelImageSizeControl(lowerModelID: lowerModelID)
    }

    private var supportedCurrentModelImageAspectRatios: [ImageAspectRatio] {
        ChatModelCapabilitySupport.supportedCurrentModelImageAspectRatios(lowerModelID: lowerModelID)
    }

    private var supportedCurrentModelImageSizes: [ImageOutputSize] {
        ChatModelCapabilitySupport.supportedCurrentModelImageSizes(lowerModelID: lowerModelID)
    }

    private var isImageGenerationConfigured: Bool {
        ChatModelCapabilitySupport.isImageGenerationConfigured(
            providerType: providerType,
            controls: controls
        )
    }

    private var imageGenerationBadgeText: String? {
        ChatModelCapabilitySupport.imageGenerationBadgeText(
            supportsImageGenerationControl: supportsImageGenerationControl,
            providerType: providerType,
            controls: controls,
            isImageGenerationConfigured: isImageGenerationConfigured
        )
    }

    private var imageGenerationHelpText: String {
        ChatModelCapabilitySupport.imageGenerationHelpText(
            supportsImageGenerationControl: supportsImageGenerationControl,
            providerType: providerType,
            controls: controls,
            isImageGenerationConfigured: isImageGenerationConfigured
        )
    }

    private var isVideoGenerationConfigured: Bool {
        ChatModelCapabilitySupport.isVideoGenerationConfigured(
            providerType: providerType,
            controls: controls
        )
    }

    private var videoGenerationBadgeText: String? {
        ChatModelCapabilitySupport.videoGenerationBadgeText(
            supportsVideoGenerationControl: supportsVideoGenerationControl,
            providerType: providerType,
            controls: controls,
            isVideoGenerationConfigured: isVideoGenerationConfigured
        )
    }

    private var videoGenerationHelpText: String {
        ChatModelCapabilitySupport.videoGenerationHelpText(
            supportsVideoGenerationControl: supportsVideoGenerationControl,
            providerType: providerType,
            controls: controls,
            isVideoGenerationConfigured: isVideoGenerationConfigured
        )
    }

    private var resolvedPDFProcessingMode: PDFProcessingMode {
        resolvedPDFProcessingMode(for: controls, supportsNativePDF: supportsNativePDF)
    }

    private var defaultPDFProcessingFallbackMode: PDFProcessingMode {
        ChatModelCapabilitySupport.defaultPDFProcessingFallbackMode(
            mistralOCRPluginEnabled: mistralOCRPluginEnabled,
            mistralOCRConfigured: mistralOCRConfigured,
            deepSeekOCRPluginEnabled: deepSeekOCRPluginEnabled,
            deepSeekOCRConfigured: deepSeekOCRConfigured
        )
    }

    private func isPDFProcessingModeAvailable(_ mode: PDFProcessingMode) -> Bool {
        isPDFProcessingModeAvailable(mode, supportsNativePDF: supportsNativePDF)
    }

    private func isPDFProcessingModeAvailable(_ mode: PDFProcessingMode, supportsNativePDF: Bool) -> Bool {
        ChatModelCapabilitySupport.isPDFProcessingModeAvailable(
            mode,
            supportsNativePDF: supportsNativePDF,
            mistralOCRPluginEnabled: mistralOCRPluginEnabled,
            deepSeekOCRPluginEnabled: deepSeekOCRPluginEnabled
        )
    }

    private func resolvedPDFProcessingMode(for controls: GenerationControls, supportsNativePDF: Bool) -> PDFProcessingMode {
        ChatModelCapabilitySupport.resolvedPDFProcessingMode(
            controls: controls,
            supportsNativePDF: supportsNativePDF,
            defaultPDFProcessingFallbackMode: defaultPDFProcessingFallbackMode,
            mistralOCRPluginEnabled: mistralOCRPluginEnabled,
            deepSeekOCRPluginEnabled: deepSeekOCRPluginEnabled
        )
    }

    private var pdfProcessingBadgeText: String? {
        switch resolvedPDFProcessingMode {
        case .native:
            return nil
        case .mistralOCR:
            return "OCR"
        case .deepSeekOCR:
            return "DS"
        case .macOSExtract:
            return "mac"
        }
    }

    private var pdfProcessingHelpText: String {
        switch resolvedPDFProcessingMode {
        case .native:
            return "PDF: Native"
        case .mistralOCR:
            return mistralOCRConfigured ? "PDF: Mistral OCR" : "PDF: Mistral OCR (API key required)"
        case .deepSeekOCR:
            return deepSeekOCRConfigured ? "PDF: DeepSeek OCR (DeepInfra)" : "PDF: DeepSeek OCR (API key required)"
        case .macOSExtract:
            return "PDF: macOS Extract"
        }
    }

    private var selectedReasoningConfig: ModelReasoningConfig? {
        if providerType == .vertexai,
           (lowerModelID == "gemini-3-pro-image-preview"
               || lowerModelID == "gemini-3.1-flash-image-preview") {
            return nil
        }
        return resolvedModelSettings?.reasoningConfig
    }

    private var isReasoningEnabled: Bool {
        if reasoningMustRemainEnabled {
            return true
        }
        if providerType == .fireworks, isFireworksMiniMaxM2FamilyModel(conversationEntity.modelID) {
            return true
        }
        return controls.reasoning?.enabled == true
    }

    private var isWebSearchEnabled: Bool {
        guard supportsWebSearchControl else { return false }
        switch providerType {
        case .perplexity:
            return controls.webSearch?.enabled ?? true
        case .openai, .openaiWebSocket, .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .anthropic, .groq, .cohere, .mistral, .deepinfra, .together, .xai,
             .deepseek, .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .gemini, .vertexai, .none:
            return controls.webSearch?.enabled == true
        }
    }

    private var isMCPToolsEnabled: Bool {
        controls.mcpTools?.enabled == true
    }

    private var effectiveContextCacheMode: ContextCacheMode {
        if let mode = controls.contextCache?.mode {
            return mode
        }
        if providerType == .anthropic {
            return .implicit
        }
        return .off
    }

    private var isContextCacheEnabled: Bool {
        effectiveContextCacheMode != .off
    }

    private var supportsReasoningControl: Bool {
        guard let config = selectedReasoningConfig else { return false }
        return config.type != .none
    }

    private var supportsReasoningDisableToggle: Bool {
        guard supportsReasoningControl else { return false }
        return !reasoningMustRemainEnabled
    }

    private var reasoningMustRemainEnabled: Bool {
        resolvedModelSettings?.reasoningCanDisable == false
    }

    private var supportsNativeWebSearchControl: Bool {
        guard providerType != .codexAppServer else { return false }

        if supportsMediaGenerationControl {
            if supportsImageGenerationControl {
                return supportsImageGenerationWebSearch
            }
            return false
        }

        if let resolvedModelSettings {
            return resolvedModelSettings.supportsWebSearch
        }

        return ModelCapabilityRegistry.supportsWebSearch(
            for: providerType,
            modelID: conversationEntity.modelID
        )
    }

    private var modelSupportsBuiltinSearchPluginControl: Bool {
        guard providerType != .codexAppServer else { return false }
        guard !supportsMediaGenerationControl else { return false }
        guard resolvedModelSettings?.capabilities.contains(.toolCalling) == true else { return false }
        return true
    }

    private var supportsBuiltinSearchPluginControl: Bool {
        guard modelSupportsBuiltinSearchPluginControl else { return false }
        guard webSearchPluginEnabled, webSearchPluginConfigured else { return false }
        return true
    }

    private var supportsSearchEngineModeSwitch: Bool {
        supportsNativeWebSearchControl && supportsBuiltinSearchPluginControl
    }

    private var prefersJinSearchEngine: Bool {
        controls.searchPlugin?.preferJinSearch == true
    }

    private var usesBuiltinSearchPlugin: Bool {
        guard supportsBuiltinSearchPluginControl else { return false }
        if supportsNativeWebSearchControl {
            return prefersJinSearchEngine
        }
        return true
    }

    private var modelSupportsWebSearchControl: Bool {
        supportsNativeWebSearchControl || modelSupportsBuiltinSearchPluginControl
    }

    private var supportsWebSearchControl: Bool {
        supportsNativeWebSearchControl || supportsBuiltinSearchPluginControl
    }

    private var supportsContextCacheControl: Bool {
        // Context cache is now fully automatic and intentionally hidden from the composer UI.
        false
    }

    private var supportsExplicitContextCacheMode: Bool {
        switch providerType {
        case .gemini, .vertexai:
            return true
        case .openai, .openaiWebSocket, .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together,
             .xai, .deepseek, .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .none:
            return false
        }
    }

    private var supportsContextCacheStrategy: Bool {
        providerType == .anthropic
    }

    private var supportsContextCacheTTL: Bool {
        switch providerType {
        case .openai, .openaiWebSocket, .anthropic, .xai:
            return true
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .perplexity,
             .groq, .cohere, .mistral, .deepinfra, .together, .gemini, .vertexai, .deepseek,
             .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .none:
            return false
        }
    }

    private var contextCacheSupportsAdvancedOptions: Bool {
        supportsContextCacheTTL || providerType == .openai || providerType == .xai
    }

    private var contextCacheSummaryText: String {
        switch providerType {
        case .gemini, .vertexai:
            return "Use implicit caching for normal chats, or explicit caching with a cached content resource for long reusable context."
        case .anthropic:
            return "Anthropic caches tagged prompt blocks. Keep stable system/tool prefixes to improve cache hit rates."
        case .openai, .openaiWebSocket:
            return "OpenAI uses prompt cache hints. A stable key and retention hint can improve reuse across similar prompts."
        case .xai:
            return "xAI supports prompt cache hints and optional conversation scoping for continuity across related turns."
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .perplexity,
             .groq, .cohere, .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan,
             .fireworks, .cerebras, .sambanova, .none:
            return "Context cache controls are only available for providers with native prompt caching support."
        }
    }

    private var contextCacheGuidanceText: String {
        switch providerType {
        case .gemini, .vertexai:
            return "Explicit mode requires a valid cached content resource name. Keep it stable across requests to reuse cached tokens."
        case .openai, .openaiWebSocket, .xai:
            return "Use a stable cache key when your prompt prefix is consistent."
        case .anthropic:
            return "For best results, keep system prompts and tool descriptions stable so Anthropic can reuse cacheable blocks."
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .perplexity,
             .groq, .cohere, .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan,
             .fireworks, .cerebras, .sambanova, .none:
            return "Use explicit mode for Gemini/Vertex cached content resources. Other providers use implicit cache hints."
        }
    }

    private func automaticContextCacheControls(
        providerType: ProviderType?,
        modelID: String,
        modelCapabilities: ModelCapability?
    ) -> ContextCacheControls? {
        guard !supportsMediaGenerationControl else { return nil }
        guard let providerType else { return nil }
        if providerType != .cloudflareAIGateway,
           let modelCapabilities,
           !modelCapabilities.contains(.promptCaching) {
            return nil
        }

        let conversationID = automaticContextCacheConversationID(modelID: modelID)

        switch providerType {
        case .openai, .openaiWebSocket:
            return ContextCacheControls(mode: .implicit)
        case .xai:
            return ContextCacheControls(
                mode: .implicit,
                conversationID: conversationID
            )
        case .anthropic:
            return ContextCacheControls(
                mode: .implicit,
                strategy: .prefixWindow,
                ttl: .providerDefault
            )
        case .gemini, .vertexai:
            // Explicit cachedContent resources require lifecycle management.
            // Keep implicit mode so providers can still apply native cache behavior where available.
            return ContextCacheControls(mode: .implicit)
        case .cloudflareAIGateway:
            return ContextCacheControls(mode: .implicit, ttl: .minutes5)
        case .codexAppServer, .githubCopilot, .openaiCompatible, .vercelAIGateway, .openrouter, .perplexity, .groq, .cohere,
             .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan, .fireworks,
             .cerebras, .sambanova:
            return nil
        }
    }

    private func automaticContextCacheConversationID(modelID: String) -> String {
        let conversationPart = conversationEntity.id.uuidString.lowercased()
        let modelPart = sanitizedContextCacheIdentifier(modelID, maxLength: 32)
        return "jin-conv-\(conversationPart)-\(modelPart)"
    }

    private func sanitizedContextCacheIdentifier(_ raw: String, maxLength: Int) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_")
        let lower = raw.lowercased()
        var output = ""
        output.reserveCapacity(min(lower.count, maxLength))

        var previousWasHyphen = false
        for scalar in lower.unicodeScalars {
            guard output.count < maxLength else { break }
            let character = Character(scalar)
            if allowed.contains(character) {
                output.append(character)
                previousWasHyphen = false
            } else if !previousWasHyphen {
                output.append("-")
                previousWasHyphen = true
            }
        }

        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return trimmed.isEmpty ? "model" : trimmed
    }

    private var supportsMCPToolsControl: Bool {
        guard providerType != .codexAppServer else { return false }
        guard !supportsMediaGenerationControl else { return false }
        return resolvedModelSettings?.capabilities.contains(.toolCalling) == true
    }

    private var supportsCodexSessionControl: Bool {
        providerType == .codexAppServer
    }

    private var supportsOpenAIServiceTierControl: Bool {
        guard !supportsMediaGenerationControl else { return false }
        return providerType == .openai || providerType == .openaiWebSocket
    }

    private var reasoningHelpText: String {
        guard supportsReasoningControl else { return "Reasoning: Not supported" }
        switch providerType {
        case .anthropic, .gemini, .vertexai:
            return "Thinking: \(reasoningLabel)"
        case .perplexity:
            return "Reasoning: \(reasoningLabel)"
        case .openai, .openaiWebSocket, .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .groq, .cohere, .mistral, .deepinfra, .together, .xai, .deepseek,
             .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .none:
            return "Reasoning: \(reasoningLabel)"
        }
    }

    private var webSearchHelpText: String {
        guard supportsWebSearchControl else { return "Web Search: Not supported" }
        guard isWebSearchEnabled else { return "Web Search: Off" }
        return "Web Search: \(webSearchLabel)"
    }

    private var openAIServiceTierHelpText: String {
        guard supportsOpenAIServiceTierControl else { return "Service Tier: Not supported" }
        return "Service Tier: \(openAIServiceTierLabel)"
    }

    private var mcpToolsHelpText: String {
        guard supportsMCPToolsControl else { return "MCP Tools: Not supported" }
        guard isMCPToolsEnabled else { return "MCP Tools: Off" }
        let count = selectedMCPServerIDs.count
        if count == 0 { return "MCP Tools: On (no servers)" }
        return "MCP Tools: On (\(count) server\(count == 1 ? "" : "s"))"
    }

    private var codexSessionHelpText: String {
        guard supportsCodexSessionControl else { return "Codex Session: Not supported" }

        var segments: [String] = ["Sandbox: \(controls.codexSandboxMode.displayName)"]
        if let workingDirectory = controls.codexWorkingDirectory {
            segments.append("Working Directory: \(workingDirectory)")
        } else {
            segments.append("Working Directory: app-server default")
        }
        if let personality = controls.codexPersonality {
            segments.append("Personality: \(personality.displayName)")
        }

        return "Codex Session: " + segments.joined(separator: " · ")
    }

    private var contextCacheHelpText: String {
        guard supportsContextCacheControl else { return "Context Cache: Not supported" }
        guard isContextCacheEnabled else { return "Context Cache: Off" }
        return "Context Cache: \(contextCacheLabel)"
    }

    private var webSearchLabel: String {
        if usesBuiltinSearchPlugin {
            let provider = effectiveSearchPluginProvider.displayName
            if let maxResults = controls.searchPlugin?.maxResults {
                return "\(provider) · \(maxResults) results"
            }
            return provider
        }

        switch providerType {
        case .openai, .openaiWebSocket:
            return (controls.webSearch?.contextSize ?? .medium).displayName
        case .perplexity:
            return (controls.webSearch?.contextSize ?? .low).displayName
        case .xai:
            return webSearchSourcesLabel
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .anthropic,
             .groq, .cohere, .mistral, .deepinfra, .together, .gemini, .vertexai, .deepseek,
             .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .none:
            return "On"
        }
    }

    private var openAIServiceTierLabel: String {
        controls.openAIServiceTier?.displayName ?? "Auto"
    }

    private var webSearchSourcesLabel: String {
        let sources = Set(controls.webSearch?.sources ?? [])
        if sources.isEmpty { return "On" }
        if sources == [.web] { return "Web" }
        if sources == [.x] { return "X" }
        return "Web + X"
    }

    private var effectiveSearchPluginProvider: SearchPluginProvider {
        if let provider = controls.searchPlugin?.provider {
            return provider
        }
        return WebSearchPluginSettingsStore.load().defaultProvider
    }

    private var reasoningBadgeText: String? {
        guard supportsReasoningControl, isReasoningEnabled else { return nil }

        guard let reasoningType = selectedReasoningConfig?.type, reasoningType != .none else { return nil }

        switch reasoningType {
        case .budget:
            switch controls.reasoning?.budgetTokens {
            case 1024: return "L"
            case 2048: return "M"
            case 4096: return "H"
            case 8192: return "X"
            default: return "On"
            }
        case .effort:
            guard let effort = controls.reasoning?.effort else { return "On" }
            switch effort {
            case .none: return nil
            case .minimal: return "Min"
            case .low: return "L"
            case .medium: return "M"
            case .high: return "H"
            case .xhigh: return "X"
            }
        case .toggle:
            return "On"
        case .none:
            return nil
        }
    }

    private var openAIServiceTierBadgeText: String? {
        guard supportsOpenAIServiceTierControl else { return nil }
        return controls.openAIServiceTier?.badgeText
    }

    private var webSearchBadgeText: String? {
        guard supportsWebSearchControl, isWebSearchEnabled else { return nil }

        if usesBuiltinSearchPlugin {
            return effectiveSearchPluginProvider.shortBadge
        }

        switch providerType {
        case .openai, .openaiWebSocket:
            switch controls.webSearch?.contextSize ?? .medium {
            case .low: return "L"
            case .medium: return "M"
            case .high: return "H"
            }
        case .perplexity:
            switch controls.webSearch?.contextSize ?? .medium {
            case .low: return "L"
            case .medium: return "M"
            case .high: return "H"
            }
        case .xai:
            let sources = Set(controls.webSearch?.sources ?? [])
            if sources == [.web] { return "W" }
            if sources == [.x] { return "X" }
            if sources.contains(.web), sources.contains(.x) { return "W+X" }
            return "On"
        case .anthropic:
            return "On"
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq,
             .cohere, .mistral, .deepinfra, .together, .gemini, .vertexai, .deepseek,
             .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .none:
            return "On"
        }
    }

    private var mcpToolsBadgeText: String? {
        guard supportsMCPToolsControl, isMCPToolsEnabled else { return nil }
        let count = selectedMCPServerIDs.count
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : "\(count)"
    }

    private var codexSessionBadgeText: String? {
        guard codexSessionOverrideCount > 0 else { return nil }
        return controls.codexSandboxMode.badgeText
    }

    private var codexSessionOverrideCount: Int {
        controls.codexActiveOverrideCount
    }

    private var codexWorkingDirectory: String? {
        controls.codexWorkingDirectory
    }

    private var contextCacheLabel: String {
        let mode = effectiveContextCacheMode
        switch mode {
        case .off:
            return "Off"
        case .implicit:
            return "Implicit"
        case .explicit:
            if let name = controls.contextCache?.cachedContentName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                return "Explicit (\(name))"
            }
            return "Explicit"
        }
    }

    private var contextCacheBadgeText: String? {
        guard supportsContextCacheControl, isContextCacheEnabled else { return nil }
        switch effectiveContextCacheMode {
        case .off:
            return nil
        case .implicit:
            return "I"
        case .explicit:
            return "E"
        }
    }

    private var eligibleMCPServers: [MCPServerConfigEntity] {
        mcpServers
            .filter { $0.isEnabled && $0.runToolsAutomatically }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var selectedMCPServerIDs: Set<String> {
        guard controls.mcpTools?.enabled == true else { return [] }
        let eligibleIDs = Set(eligibleMCPServers.map(\.id))
        if let allowlist = controls.mcpTools?.enabledServerIDs {
            return Set(allowlist).intersection(eligibleIDs)
        }
        return eligibleIDs
    }

    private func setPDFProcessingMode(_ mode: PDFProcessingMode) {
        guard isPDFProcessingModeAvailable(mode) else { return }
        controls.pdfProcessingMode = (mode == .native) ? nil : mode
        persistControlsToConversation()
    }

    @ViewBuilder
    private var pdfProcessingMenuContent: some View {
        if supportsNativePDF {
            Button { setPDFProcessingMode(.native) } label: { menuItemLabel("Native", isSelected: resolvedPDFProcessingMode == .native) }
        }

        if mistralOCRPluginEnabled {
            Button { setPDFProcessingMode(.mistralOCR) } label: { menuItemLabel("Mistral OCR", isSelected: resolvedPDFProcessingMode == .mistralOCR) }
        }

        if deepSeekOCRPluginEnabled {
            Button { setPDFProcessingMode(.deepSeekOCR) } label: { menuItemLabel("DeepSeek OCR (DeepInfra)", isSelected: resolvedPDFProcessingMode == .deepSeekOCR) }
        }

        Button { setPDFProcessingMode(.macOSExtract) } label: { menuItemLabel("macOS Extract", isSelected: resolvedPDFProcessingMode == .macOSExtract) }

        if resolvedPDFProcessingMode == .mistralOCR, !mistralOCRConfigured {
            Divider()
            Text("Set API key in Settings → Plugins → Mistral OCR.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if resolvedPDFProcessingMode == .deepSeekOCR, !deepSeekOCRConfigured {
            Divider()
            Text("Set API key in Settings → Plugins → DeepSeek OCR (DeepInfra).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if !mistralOCRPluginEnabled && !deepSeekOCRPluginEnabled {
            Divider()
            Text("OCR plugins are turned off. Enable them in Settings → Plugins to show OCR modes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var detailHeaderBar: some View {
        ChatHeaderBarView(
            isSidebarHidden: isSidebarHidden,
            onToggleSidebar: onToggleSidebar,
            currentProviderIconID: currentProviderIconID,
            currentModelName: currentModelName,
            toolbarThreads: headerToolbarThreads,
            isModelPickerPresented: $isModelPickerPresented,
            isAddModelPickerPresented: $isAddModelPickerPresented,
            isStarred: conversationEntity.isStarred == true,
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

    private var headerToolbarThreads: [ChatHeaderToolbarThread] {
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

    private func modelPickerPopoverContent(onSelect: @escaping (String, String) -> Void) -> some View {
        ModelPickerPopover(
            favoritesStore: favoriteModelsStore,
            providers: providers,
            selectedProviderID: conversationEntity.providerID,
            selectedModelID: conversationEntity.modelID,
            onSelect: onSelect
        )
    }

    private var currentModelName: String {
        ChatThreadSupport.currentModelName(
            providerID: conversationEntity.providerID,
            modelID: conversationEntity.modelID,
            providers: providers,
            providerType: providerType,
            resolveModelInfo: { modelID, providerEntity, providerType in
                resolvedModelInfo(
                    for: modelID,
                    providerEntity: providerEntity,
                    providerType: providerType
                )
            }
        )
    }

    private var currentProvider: ProviderConfigEntity? {
        ChatThreadSupport.currentProvider(
            for: conversationEntity.providerID,
            in: providers
        )
    }

    private var currentProviderIconID: String? {
        ChatThreadSupport.providerIconID(
            for: conversationEntity.providerID,
            in: providers
        )
    }

    private func providerIconID(for providerID: String) -> String? {
        ChatThreadSupport.providerIconID(
            for: providerID,
            in: providers
        )
    }

    private func modelName(id modelID: String, providerID: String) -> String {
        ChatThreadSupport.modelName(
            modelID: modelID,
            providerID: providerID,
            providers: providers,
            resolveModelInfo: { modelID, providerEntity, providerType in
                resolvedModelInfo(
                    for: modelID,
                    providerEntity: providerEntity,
                    providerType: providerType
                )
            }
        )
    }

    private func isActiveThread(_ thread: ConversationModelThreadEntity) -> Bool {
        activeModelThread?.id == thread.id
    }

    private func toggleThreadSelection(_ thread: ConversationModelThreadEntity) {
        ChatThreadSupport.toggleThreadSelection(
            thread: thread,
            conversationEntity: conversationEntity,
            sortedThreads: sortedModelThreads,
            activeThread: activeModelThread,
            modelContext: modelContext,
            activateThread: { thread in
                activateThread(thread)
            },
            rebuildMessageCaches: {
                rebuildMessageCaches()
            }
        )
    }

    private func synchronizeLegacyConversationModelFields(with thread: ConversationModelThreadEntity) {
        ChatThreadSupport.synchronizeLegacyConversationModelFields(
            conversationEntity: conversationEntity,
            activeThreadID: &activeThreadID,
            thread: thread
        )
    }

    private func activateThread(_ thread: ConversationModelThreadEntity) {
        guard conversationEntity.modelThreads.contains(where: { $0.id == thread.id }) else { return }

        thread.lastActivatedAt = Date()
        thread.updatedAt = Date()
        thread.isSelected = true
        synchronizeLegacyConversationModelFields(with: thread)
        canonicalizeThreadModelIDIfNeeded(thread)
        loadControlsFromConversation()
        normalizeControlsForCurrentSelection()
        rebuildMessageCaches()
        try? modelContext.save()
    }

    private func activateThread(by threadID: UUID) {
        guard let thread = sortedModelThreads.first(where: { $0.id == threadID }) else { return }
        activateThread(thread)
    }

    private func removeModelThread(_ thread: ConversationModelThreadEntity) {
        ChatThreadSupport.removeModelThread(
            thread: thread,
            conversationEntity: conversationEntity,
            sortedThreads: sortedModelThreads,
            activeThreadID: activeThreadID,
            streamingStore: streamingStore,
            modelContext: modelContext,
            rebuildMessageCaches: {
                rebuildMessageCaches()
            },
            activateThread: { thread in
                activateThread(thread)
            }
        )
    }

    private func addOrActivateThread(providerID: String, modelID: String) {
        ChatThreadSupport.addOrActivateThread(
            providerID: providerID,
            modelID: modelID,
            conversationEntity: conversationEntity,
            sortedThreads: sortedModelThreads,
            canonicalModelID: { providerID, modelID in
                canonicalModelID(for: providerID, modelID: modelID)
            },
            activateThread: { thread in
                activateThread(thread)
            },
            showError: { message in
                errorMessage = message
                showingError = true
            }
        )
    }

    private var availableModels: [ModelInfo] {
        currentProvider?.enabledModels ?? []
    }

    private func isFullySupportedModel(modelID: String) -> Bool {
        guard let providerType else { return false }
        return JinModelSupport.isFullySupported(providerType: providerType, modelID: modelID)
    }

    private func setProvider(_ providerID: String) {
        ChatModelSelectionSupport.setProvider(
            providerID: providerID,
            activeThread: activeModelThread,
            providers: providers,
            modelContext: modelContext,
            clearCodexThreadPersistence: { thread in
                clearCodexThreadPersistence(for: thread)
            },
            synchronizeLegacyConversationModelFields: { thread in
                synchronizeLegacyConversationModelFields(with: thread)
            },
            normalizeControlsForCurrentSelection: {
                normalizeControlsForCurrentSelection()
            },
            preferredModelID: { models, providerID in
                preferredModelID(in: models, providerID: providerID)
            }
        )
    }

    private func setModel(_ modelID: String) {
        ChatModelSelectionSupport.setModel(
            modelID: modelID,
            activeThread: activeModelThread,
            modelContext: modelContext,
            canonicalModelID: { providerID, modelID in
                canonicalModelID(for: providerID, modelID: modelID)
            },
            synchronizeLegacyConversationModelFields: { thread in
                synchronizeLegacyConversationModelFields(with: thread)
            },
            normalizeControlsForCurrentSelection: {
                normalizeControlsForCurrentSelection()
            }
        )
    }

    private func setProviderAndModel(providerID: String, modelID: String) {
        ChatModelSelectionSupport.setProviderAndModel(
            providerID: providerID,
            modelID: modelID,
            activeThread: activeModelThread,
            sortedThreads: sortedModelThreads,
            clearCodexThreadPersistence: { thread in
                clearCodexThreadPersistence(for: thread)
            },
            canonicalModelID: { providerID, modelID in
                canonicalModelID(for: providerID, modelID: modelID)
            },
            addOrActivateThread: { providerID, modelID in
                addOrActivateThread(providerID: providerID, modelID: modelID)
            },
            activateThread: { thread in
                activateThread(thread)
            },
            synchronizeLegacyConversationModelFields: { thread in
                synchronizeLegacyConversationModelFields(with: thread)
            },
            normalizeControlsForCurrentSelection: {
                normalizeControlsForCurrentSelection()
            },
            persistControlsToConversation: {
                persistControlsToConversation()
            }
        )
    }

    private func preferredModelID(in models: [ModelInfo], providerID: String) -> String? {
        ChatModelSelectionSupport.preferredModelID(
            in: models,
            providerID: providerID,
            providers: providers,
            geminiPreferredModelOrder: Self.geminiPreferredModelOrder,
            isFireworksModelID: { modelID, canonicalID in
                isFireworksModelID(modelID, canonicalID: canonicalID)
            }
        )
    }


    private func orderedConversationMessages(threadID: UUID? = nil) -> [MessageEntity] {
        ChatMessageRenderPipeline.orderedMessages(
            from: conversationEntity.messages,
            threadID: threadID
        )
    }

    private func rebuildMessageCachesIfNeeded() {
        guard conversationEntity.messages.count != lastCacheRebuildMessageCount
            || conversationEntity.updatedAt != lastCacheRebuildUpdatedAt else {
            return
        }

        rebuildMessageCaches()
    }

    private func rebuildMessageCaches() {
        let ordered = orderedConversationMessages(threadID: activeModelThread?.id)
        let context = ChatMessageRenderPipeline.makeRenderContext(
            from: ordered,
            fallbackModelLabel: currentModelName,
            assistantProviderIconID: { providerID in
                providerIconID(for: providerID)
            }
        )

        cachedVisibleMessages = context.visibleMessages
        cachedMessageEntitiesByID = context.messageEntitiesByID
        cachedToolResultsByCallID = context.toolResultsByCallID
        cachedMessagesVersion &+= 1
        lastCacheRebuildMessageCount = ordered.count
        lastCacheRebuildUpdatedAt = conversationEntity.updatedAt
    }

    private func regenerateMessage(_ messageEntity: MessageEntity) {
        guard !isStreaming else { return }

        cancelEditingUserMessage()

        switch messageEntity.role {
        case "user":
            regenerateFromUserMessage(messageEntity)
        case "assistant":
            regenerateFromAssistantMessage(messageEntity)
        default:
            break
        }
    }

    private func beginEditingUserMessage(_ messageEntity: MessageEntity) {
        guard !isStreaming else { return }
        guard messageEntity.role == "user" else { return }

        if editingUserMessageID != messageEntity.id {
            cancelEditingUserMessage()
        }

        guard let message = try? messageEntity.toDomain() else { return }
        guard let editableText = editableUserText(from: message), !editableText.isEmpty else { return }

        editingUserMessageID = messageEntity.id
        editingUserMessageText = editableText

        DispatchQueue.main.async {
            isEditingUserMessageFocused = true
        }
    }

    private func submitEditingUserMessage(_ messageEntity: MessageEntity) {
        guard !isStreaming else { return }
        guard messageEntity.role == "user" else { return }
        guard editingUserMessageID == messageEntity.id else { return }

        let trimmed = editingUserMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil else {
            cancelEditingUserMessage()
            return
        }

        do {
            try updateUserMessageContent(messageEntity, newText: trimmed)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            return
        }

        if let threadID = messageEntity.contextThreadID ?? activeModelThread?.id {
            invalidateCodexThreadPersistence(forThreadID: threadID)
        }

        cancelEditingUserMessage()
        regenerateFromUserMessage(messageEntity)
    }

    private func cancelEditingUserMessage() {
        editingUserMessageID = nil
        editingUserMessageText = ""
        isEditingUserMessageFocused = false
    }

    private func regenerateFromUserMessage(_ messageEntity: MessageEntity) {
        guard let threadID = messageEntity.contextThreadID ?? activeModelThread?.id else { return }
        guard let keepCount = keepCountForRegeneratingUserMessage(messageEntity, threadID: threadID) else { return }
        let askedAt = Date()
        truncateConversation(keepingMessages: keepCount, in: threadID)
        messageEntity.timestamp = askedAt
        conversationEntity.updatedAt = askedAt
        activateThread(by: threadID)
        startStreamingResponse(for: threadID, triggeredByUserSend: false)
    }

    private func regenerateFromAssistantMessage(_ messageEntity: MessageEntity) {
        guard let threadID = messageEntity.contextThreadID ?? activeModelThread?.id else { return }
        guard let keepCount = keepCountForRegeneratingAssistantMessage(messageEntity, threadID: threadID) else { return }
        truncateConversation(keepingMessages: keepCount, in: threadID)
        activateThread(by: threadID)
        startStreamingResponse(for: threadID, triggeredByUserSend: false)
    }

    private func keepCountForRegeneratingUserMessage(_ messageEntity: MessageEntity, threadID: UUID) -> Int? {
        let ordered = orderedConversationMessages(threadID: threadID)
        guard let index = ordered.firstIndex(where: { $0.id == messageEntity.id }) else { return nil }
        let keepCount = index + 1
        guard keepCount > 0 else { return nil }
        return keepCount
    }

    private func keepCountForRegeneratingAssistantMessage(_ messageEntity: MessageEntity, threadID: UUID) -> Int? {
        let ordered = orderedConversationMessages(threadID: threadID)
        guard let index = ordered.firstIndex(where: { $0.id == messageEntity.id }) else { return nil }
        let keepCount = index
        guard keepCount > 0 else { return nil }
        return keepCount
    }

    private func truncateConversation(keepingMessages keepCount: Int, in threadID: UUID) {
        let ordered = orderedConversationMessages(threadID: threadID)
        let normalizedKeepCount = max(0, min(keepCount, ordered.count))
        let keepIDs = Set(ordered.prefix(normalizedKeepCount).map(\.id))
        let messagesToDelete = Array(ordered.suffix(from: normalizedKeepCount))
        recordCodexThreadHistoryMutation(forThreadID: threadID, removedMessages: messagesToDelete)

        for message in messagesToDelete {
            modelContext.delete(message)
        }

        conversationEntity.messages.removeAll {
            $0.contextThreadID == threadID && !keepIDs.contains($0.id)
        }
        refreshConversationActivityTimestampFromLatestUserMessage()
        pendingRestoreScrollMessageID = nil
        isPinnedToBottom = true
        rebuildMessageCaches()
    }

    private func injectCodexThreadPersistence(into controls: inout GenerationControls, from thread: ConversationModelThreadEntity) {
        guard providerType(forProviderID: thread.providerID) == .codexAppServer else {
            controls.codexResumeThreadID = nil
            controls.codexPendingRollbackTurns = 0
            return
        }

        let storedControls = storedGenerationControls(for: thread) ?? GenerationControls()
        controls.codexResumeThreadID = storedControls.codexResumeThreadID
        controls.codexPendingRollbackTurns = storedControls.codexPendingRollbackTurns
    }

    private func persistCodexThreadState(_ state: CodexThreadState, forLocalThreadID threadID: UUID) {
        guard let thread = sortedModelThreads.first(where: { $0.id == threadID }) else { return }
        guard providerType(forProviderID: thread.providerID) == .codexAppServer else { return }

        mutateStoredGenerationControls(for: thread) { storedControls in
            storedControls.codexResumeThreadID = state.remoteThreadID
            storedControls.codexPendingRollbackTurns = 0
        }
    }

    private func clearCodexThreadPersistence(for thread: ConversationModelThreadEntity) {
        guard providerType(forProviderID: thread.providerID) == .codexAppServer else { return }
        mutateStoredGenerationControls(for: thread) { storedControls in
            storedControls.codexResumeThreadID = nil
            storedControls.codexPendingRollbackTurns = 0
        }
    }

    private func invalidateCodexThreadPersistence(forThreadID threadID: UUID) {
        guard let thread = sortedModelThreads.first(where: { $0.id == threadID }) else { return }
        guard providerType(forProviderID: thread.providerID) == .codexAppServer else { return }
        clearCodexThreadPersistence(for: thread)
    }

    private func recordCodexThreadHistoryMutation(forThreadID threadID: UUID, removedMessages: [MessageEntity]) {
        guard !removedMessages.isEmpty else { return }
        guard let thread = sortedModelThreads.first(where: { $0.id == threadID }) else { return }
        guard providerType(forProviderID: thread.providerID) == .codexAppServer else { return }

        let storedControls = storedGenerationControls(for: thread) ?? GenerationControls()
        guard storedControls.codexResumeThreadID != nil else { return }

        if removedMessages.contains(where: { $0.turnID == nil }) {
            clearCodexThreadPersistence(for: thread)
            return
        }

        let removedTurnCount = Set(removedMessages.compactMap(\.turnID)).count
        guard removedTurnCount > 0 else { return }
        mutateStoredGenerationControls(for: thread) { controls in
            controls.codexPendingRollbackTurns += removedTurnCount
        }
    }

    private func storedGenerationControls(for thread: ConversationModelThreadEntity) -> GenerationControls? {
        try? JSONDecoder().decode(GenerationControls.self, from: thread.modelConfigData)
    }

    private func mutateStoredGenerationControls(
        for thread: ConversationModelThreadEntity,
        _ mutate: (inout GenerationControls) -> Void
    ) {
        var controls = storedGenerationControls(for: thread) ?? GenerationControls()
        let previousResumeThreadID = controls.codexResumeThreadID
        let previousRollbackTurns = controls.codexPendingRollbackTurns
        mutate(&controls)
        guard controls.codexResumeThreadID != previousResumeThreadID
            || controls.codexPendingRollbackTurns != previousRollbackTurns else {
            return
        }

        do {
            thread.modelConfigData = try JSONEncoder().encode(controls)
            thread.updatedAt = Date()
            if conversationEntity.activeThreadID == thread.id {
                conversationEntity.modelConfigData = thread.modelConfigData
            }
            conversationEntity.updatedAt = max(conversationEntity.updatedAt, thread.updatedAt)
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func refreshConversationActivityTimestampFromLatestUserMessage() {
        let latestUserTimestamp = conversationEntity.messages
            .filter { $0.role == MessageRole.user.rawValue }
            .map(\.timestamp)
            .max()

        conversationEntity.updatedAt = latestUserTimestamp ?? conversationEntity.createdAt
    }

    private func editableUserText(from message: Message) -> String? {
        ChatMessageRenderPipeline.editableUserText(from: message)
    }

    private func updateUserMessageContent(_ entity: MessageEntity, newText: String) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        let originalContent = try decoder.decode([ContentPart].self, from: entity.contentData)
        var newContent: [ContentPart] = []
        newContent.reserveCapacity(max(1, originalContent.count))

        var didInsertText = false
        for part in originalContent {
            switch part {
            case .text:
                if !didInsertText {
                    newContent.append(.text(newText))
                    didInsertText = true
                }
            default:
                newContent.append(part)
            }
        }

        if !didInsertText {
            newContent.append(.text(newText))
        }

        entity.contentData = try encoder.encode(newContent)
    }

    private func resolvedSystemPrompt(conversationSystemPrompt: String?, assistant: AssistantEntity?) -> String? {
        let conversationPrompt = conversationSystemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistantPrompt = assistant?.systemInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let replyLanguage = assistant?.replyLanguage?.trimmingCharacters(in: .whitespacesAndNewlines)

        var prompt = conversationPrompt
        if prompt?.isEmpty != false {
            prompt = assistantPrompt
        }

        if let replyLanguage, !replyLanguage.isEmpty {
            if prompt?.isEmpty != false {
                prompt = "Always reply in \(replyLanguage)."
            } else {
                prompt = "\(prompt!)\n\nAlways reply in \(replyLanguage)."
            }
        }

        let trimmed = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func sendMessage() {
        sendMessageInternal()
    }

    private func sendMessageInternal() {
        if isStreaming {
            streamingStore.cancel(conversationID: conversationEntity.id)
            return
        }

        if isPreparingToSend {
            prepareToSendTask?.cancel()
            return
        }

        guard canSendDraft else { return }
        cancelEditingUserMessage()
        ensureModelThreadsInitializedIfNeeded()

        guard let activeThread = activeModelThread else {
            errorMessage = "No active model is available for this chat."
            showingError = true
            return
        }

        let targetThreadIDs = selectedModelThreads.map(\.id)
        guard !targetThreadIDs.isEmpty else {
            errorMessage = "Please add a model before sending."
            showingError = true
            return
        }
        let targetThreads = targetThreadIDs.compactMap { targetID in
            sortedModelThreads.first(where: { $0.id == targetID })
        }
        guard !targetThreads.isEmpty else {
            errorMessage = "Please add a model before sending."
            showingError = true
            return
        }
        let namingThreadID = targetThreadIDs.contains(activeThread.id) ? activeThread.id : targetThreadIDs.first

        let messageTextSnapshot = trimmedMessageText
        let remoteVideoURLTextSnapshot = trimmedRemoteVideoInputURLText
        let attachmentsSnapshot = draftAttachments
        let askedAt = Date()
        let turnID = UUID()

        let remoteVideoURLSnapshot: URL?
        do {
            remoteVideoURLSnapshot = try resolvedRemoteVideoInputURL(from: remoteVideoURLTextSnapshot)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            return
        }

        messageText = ""
        remoteVideoInputURLText = ""
        composerTextContentHeight = 36
        draftAttachments = []

        isPreparingToSend = true
        prepareToSendStatus = nil

        let task = Task {
            do {
                let preparedMessages = try await buildUserMessagePartsForThreads(
                    threads: targetThreads,
                    messageText: messageTextSnapshot,
                    attachments: attachmentsSnapshot,
                    remoteVideoURL: remoteVideoURLSnapshot
                )

                await MainActor.run {
                    if conversationEntity.messages.isEmpty {
                        onPersistConversationIfNeeded()
                    }

                    for prepared in preparedMessages {
                        let message = Message(role: .user, content: prepared.parts, timestamp: askedAt)
                        guard let messageEntity = try? MessageEntity.fromDomain(message) else { continue }
                        messageEntity.contextThreadID = prepared.threadID
                        messageEntity.turnID = turnID
                        messageEntity.conversation = conversationEntity
                        conversationEntity.messages.append(messageEntity)
                    }

                    if conversationEntity.title == "New Chat", !isChatNamingPluginEnabled {
                        if !messageTextSnapshot.isEmpty {
                            conversationEntity.title = makeConversationTitle(from: messageTextSnapshot)
                        } else if let firstAttachment = attachmentsSnapshot.first {
                            conversationEntity.title = makeConversationTitle(from: (firstAttachment.filename as NSString).deletingPathExtension)
                        }
                    }
                    conversationEntity.updatedAt = askedAt
                    rebuildMessageCaches()
                    try? modelContext.save()
                }

                await MainActor.run {
                    isPreparingToSend = false
                    prepareToSendStatus = nil
                    prepareToSendTask = nil
                    for threadID in targetThreadIDs {
                        startStreamingResponse(
                            for: threadID,
                            triggeredByUserSend: threadID == namingThreadID,
                            turnID: turnID
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    isPreparingToSend = false
                    prepareToSendStatus = nil
                    prepareToSendTask = nil
                    messageText = messageTextSnapshot
                    remoteVideoInputURLText = remoteVideoURLTextSnapshot
                    draftAttachments = attachmentsSnapshot
                    if !(error is CancellationError) {
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                }
            }
        }

        prepareToSendTask = task
    }

    private struct ThreadPreparedUserMessage {
        let threadID: UUID
        let parts: [ContentPart]
    }

    private struct MessagePreparationProfile {
        let threadID: UUID
        let modelName: String
        let supportsVideoGenerationControl: Bool
        let supportsMediaGenerationControl: Bool
        let supportsNativePDF: Bool
        let supportsVision: Bool
        let pdfProcessingMode: PDFProcessingMode
    }

    private func buildUserMessagePartsForThreads(
        threads: [ConversationModelThreadEntity],
        messageText: String,
        attachments: [DraftAttachment],
        remoteVideoURL: URL?
    ) async throws -> [ThreadPreparedUserMessage] {
        var preparedMessages: [ThreadPreparedUserMessage] = []
        preparedMessages.reserveCapacity(threads.count)

        for thread in threads {
            try Task.checkCancellation()
            let profile = try messagePreparationProfile(for: thread)
            if profile.supportsMediaGenerationControl && messageText.isEmpty {
                let mediaType = profile.supportsVideoGenerationControl ? "Video" : "Image"
                throw LLMError.invalidRequest(message: "\(mediaType) generation models require a text prompt. (\(profile.modelName))")
            }

            let parts = try await buildUserMessageParts(
                messageText: messageText,
                attachments: attachments,
                remoteVideoURL: remoteVideoURL,
                profile: profile
            )
            preparedMessages.append(ThreadPreparedUserMessage(threadID: profile.threadID, parts: parts))
        }

        return preparedMessages
    }

    private func messagePreparationProfile(for thread: ConversationModelThreadEntity) throws -> MessagePreparationProfile {
        let providerTypeSnapshot = providerType(forProviderID: thread.providerID)
        let providerEntity = providers.first(where: { $0.id == thread.providerID })
        let resolvedModelID = effectiveModelID(
            for: thread.modelID,
            providerEntity: providerEntity,
            providerType: providerTypeSnapshot
        )
        let lowerModelID = resolvedModelID.lowercased()
        let modelInfo = resolvedModelInfo(
            for: thread.modelID,
            providerEntity: providerEntity,
            providerType: providerTypeSnapshot
        )
        let normalizedModelInfoSnapshot = modelInfo.map { normalizedModelInfo($0, for: providerTypeSnapshot) }
        let resolvedModelSettings = normalizedModelInfoSnapshot.map {
            ModelSettingsResolver.resolve(model: $0, providerType: providerTypeSnapshot)
        }

        let supportsImageGenerationControl = (resolvedModelSettings?.capabilities.contains(.imageGeneration) == true)
            || supportsImageGenerationModel(providerType: providerTypeSnapshot, lowerModelID: lowerModelID)
        let supportsVideoGenerationControl = (resolvedModelSettings?.capabilities.contains(.videoGeneration) == true)
            || supportsVideoGenerationModel(providerType: providerTypeSnapshot, lowerModelID: lowerModelID)
        let supportsMediaGenerationControl = supportsImageGenerationControl || supportsVideoGenerationControl
        let nativePDFSupported = supportsNativePDFForThread(
            providerType: providerTypeSnapshot,
            lowerModelID: lowerModelID,
            supportsMediaGenerationControl: supportsMediaGenerationControl,
            resolvedModelSettings: resolvedModelSettings
        )
        let supportsVision = (resolvedModelSettings?.capabilities.contains(.vision) == true)
            || supportsImageGenerationControl
            || supportsVideoGenerationControl
        let controls: GenerationControls
        do {
            controls = try JSONDecoder().decode(GenerationControls.self, from: thread.modelConfigData)
        } catch {
            throw LLMError.decodingError(message: "Failed to load conversation settings: \(error.localizedDescription)")
        }
        let pdfMode = resolvedPDFProcessingMode(for: controls, supportsNativePDF: nativePDFSupported)
        let modelName = modelInfo?.name ?? resolvedModelID

        return MessagePreparationProfile(
            threadID: thread.id,
            modelName: modelName,
            supportsVideoGenerationControl: supportsVideoGenerationControl,
            supportsMediaGenerationControl: supportsMediaGenerationControl,
            supportsNativePDF: nativePDFSupported,
            supportsVision: supportsVision,
            pdfProcessingMode: pdfMode
        )
    }

    private func providerType(forProviderID providerID: String) -> ProviderType? {
        if let provider = providers.first(where: { $0.id == providerID }),
           let resolvedType = ProviderType(rawValue: provider.typeRaw) {
            return resolvedType
        }
        return ProviderType(rawValue: providerID)
    }

    private func normalizedModelInfo(_ model: ModelInfo, for providerType: ProviderType?) -> ModelInfo {
        guard providerType == .fireworks else { return model }
        return normalizedFireworksModelInfo(model)
    }

    private func supportsImageGenerationModel(providerType: ProviderType?, lowerModelID: String) -> Bool {
        switch providerType {
        case .openai, .openaiWebSocket:
            return Self.openAIImageGenerationModelIDs.contains(lowerModelID)
        case .xai:
            return Self.xAIImageGenerationModelIDs.contains(lowerModelID)
        case .gemini, .vertexai:
            return Self.geminiImageGenerationModelIDs.contains(lowerModelID)
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together,
             .deepseek, .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .none:
            return false
        }
    }

    private func supportsVideoGenerationModel(providerType: ProviderType?, lowerModelID: String) -> Bool {
        switch providerType {
        case .xai:
            return Self.xAIVideoGenerationModelIDs.contains(lowerModelID)
        case .gemini, .vertexai:
            return Self.googleVideoGenerationModelIDs.contains(lowerModelID)
        default:
            return false
        }
    }

    private func supportsNativePDFForThread(
        providerType: ProviderType?,
        lowerModelID: String,
        supportsMediaGenerationControl: Bool,
        resolvedModelSettings: ResolvedModelSettings?
    ) -> Bool {
        guard !supportsMediaGenerationControl else { return false }
        guard let providerType else { return false }

        switch providerType {
        case .openai, .openaiWebSocket, .anthropic, .perplexity, .xai, .gemini, .vertexai:
            break
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq,
             .cohere, .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan,
             .fireworks, .cerebras, .sambanova:
            return false
        }

        if resolvedModelSettings?.capabilities.contains(.nativePDF) == true {
            return true
        }

        return JinModelSupport.supportsNativePDF(providerType: providerType, modelID: lowerModelID)
    }

    private func buildUserMessageParts(
        messageText: String,
        attachments: [DraftAttachment],
        remoteVideoURL: URL?,
        profile: MessagePreparationProfile
    ) async throws -> [ContentPart] {
        var parts: [ContentPart] = []
        parts.reserveCapacity(attachments.count + (messageText.isEmpty ? 0 : 1) + (remoteVideoURL == nil ? 0 : 1))

        if let remoteVideoURL {
            guard profile.supportsVideoGenerationControl else {
                throw LLMError.invalidRequest(
                    message: "Remote video URL is only supported by video-capable models. (\(profile.modelName))"
                )
            }
            parts.append(.video(VideoContent(mimeType: inferredVideoMIMEType(from: remoteVideoURL), data: nil, url: remoteVideoURL)))
        }

        let pdfCount = attachments.filter(\.isPDF).count

        let requestedMode = profile.pdfProcessingMode
        if pdfCount > 0, requestedMode == .native, !profile.supportsNativePDF {
            throw PDFProcessingError.nativePDFNotSupported(modelName: profile.modelName)
        }

        let mistralClient: MistralOCRClient?
        if pdfCount > 0, requestedMode == .mistralOCR {
            let key = UserDefaults.standard.string(forKey: AppPreferenceKeys.pluginMistralOCRAPIKey)
            let trimmed = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                throw PDFProcessingError.mistralAPIKeyMissing
            }

            mistralClient = MistralOCRClient(apiKey: trimmed)
        } else {
            mistralClient = nil
        }

        let deepSeekClient: DeepInfraDeepSeekOCRClient?
        if pdfCount > 0, requestedMode == .deepSeekOCR {
            let key = UserDefaults.standard.string(forKey: AppPreferenceKeys.pluginDeepSeekOCRAPIKey)
            let trimmed = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                throw PDFProcessingError.deepInfraAPIKeyMissing
            }

            deepSeekClient = DeepInfraDeepSeekOCRClient(apiKey: trimmed)
        } else {
            deepSeekClient = nil
        }

        var pdfOrdinal = 0
        for attachment in attachments {
            try Task.checkCancellation()

            if attachment.isImage {
                parts.append(.image(ImageContent(mimeType: attachment.mimeType, data: nil, url: attachment.fileURL)))
                continue
            }

            if attachment.isVideo {
                parts.append(.video(VideoContent(mimeType: attachment.mimeType, data: nil, url: attachment.fileURL)))
                continue
            }

            if attachment.isAudio {
                parts.append(.audio(AudioContent(mimeType: attachment.mimeType, data: nil, url: attachment.fileURL)))
                continue
            }

            if attachment.isPDF {
                pdfOrdinal += 1
                let prepared = try await preparedContentForPDF(
                    attachment,
                    profile: profile,
                    requestedMode: requestedMode,
                    totalPDFCount: pdfCount,
                    pdfOrdinal: pdfOrdinal,
                    mistralClient: mistralClient,
                    deepSeekClient: deepSeekClient
                )

                parts.append(
                    .file(
                        FileContent(
                            mimeType: attachment.mimeType,
                            filename: attachment.filename,
                            data: nil,
                            url: attachment.fileURL,
                            extractedText: prepared.extractedText
                        )
                    )
                )
                parts.append(contentsOf: prepared.additionalParts)
                continue
            }

            parts.append(
                .file(
                    FileContent(
                        mimeType: attachment.mimeType,
                        filename: attachment.filename,
                        data: nil,
                        url: attachment.fileURL,
                        extractedText: attachment.extractedText
                    )
                )
            )
        }

        if !messageText.isEmpty {
            parts.append(.text(messageText))
        }

        return parts
    }

    private func resolvedRemoteVideoInputURL(from raw: String) throws -> URL? {
        guard supportsExplicitRemoteVideoURLInput else { return nil }
        guard !raw.isEmpty else { return nil }

        guard let url = URL(string: raw),
              !url.isFileURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw LLMError.invalidRequest(message: "Video URL must be a valid http(s) link.")
        }

        return url
    }

    private func inferredVideoMIMEType(from url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        case "avi": return "video/x-msvideo"
        case "mkv": return "video/x-matroska"
        case "mpeg", "mpg": return "video/mpeg"
        case "wmv": return "video/x-ms-wmv"
        case "flv": return "video/x-flv"
        case "3gp", "3gpp": return "video/3gpp"
        default: return "video/mp4"
        }
    }

    private struct PreparedPDFContent {
        let extractedText: String?
        let additionalParts: [ContentPart]
    }

    private func preparedContentForPDF(
        _ attachment: DraftAttachment,
        profile: MessagePreparationProfile,
        requestedMode: PDFProcessingMode,
        totalPDFCount: Int,
        pdfOrdinal: Int,
        mistralClient: MistralOCRClient?,
        deepSeekClient: DeepInfraDeepSeekOCRClient?
    ) async throws -> PreparedPDFContent {
        let shouldSendNativePDF = profile.supportsNativePDF && requestedMode == .native
        guard !shouldSendNativePDF else {
            return PreparedPDFContent(extractedText: nil, additionalParts: [])
        }

        switch requestedMode {
        case .macOSExtract:
            await MainActor.run {
                prepareToSendStatus = "Extracting PDF \(pdfOrdinal)/\(max(1, totalPDFCount)) (macOS): \(attachment.filename)"
            }

            guard let extracted = PDFKitTextExtractor.extractText(
                from: attachment.fileURL,
                maxCharacters: AttachmentConstants.maxPDFExtractedCharacters
            ) else {
                throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: "macOS Extract")
            }

            var output = "macOS Extract (PDF): \(attachment.filename)\n\n\(extracted)"
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.count > AttachmentConstants.maxPDFExtractedCharacters {
                let prefix = output.prefix(AttachmentConstants.maxPDFExtractedCharacters)
                output = "\(prefix)\n\n[Truncated]"
            }

            return PreparedPDFContent(extractedText: output, additionalParts: [])

        case .mistralOCR:
            guard let mistralClient else { throw PDFProcessingError.mistralAPIKeyMissing }

            await MainActor.run {
                prepareToSendStatus = "OCR PDF \(pdfOrdinal)/\(max(1, totalPDFCount)) (Mistral): \(attachment.filename)"
            }

            guard let data = try? Data(contentsOf: attachment.fileURL) else {
                throw PDFProcessingError.fileReadFailed(filename: attachment.filename)
            }

            let includeImageBase64 = profile.supportsVision
            let response = try await mistralClient.ocrPDF(data, includeImageBase64: includeImageBase64)
            let pages = response.pages
                .sorted { $0.index < $1.index }
            var combinedMarkdown = pages
                .map(\.markdown)
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // If Mistral returns extracted tables separately (via `table_format`), inline them so the model
            // doesn't see placeholder links like `[tbl-3.html](tbl-3.html)`.
            var tablesByID: [String: String] = [:]
            for page in pages {
                for table in page.tables ?? [] {
                    let id = table.id.trimmingCharacters(in: .whitespacesAndNewlines)
                    let content = table.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !id.isEmpty, !content.isEmpty else { continue }
                    tablesByID[id] = content
                    tablesByID[(id as NSString).lastPathComponent] = content
                }
            }

            if !tablesByID.isEmpty {
                combinedMarkdown = MistralOCRMarkdown.replacingTableLinks(from: combinedMarkdown) { id in
                    guard !id.isEmpty else { return "" }
                    if let content = tablesByID[id] { return content }
                    return "[\(id)](\(id))"
                }
                .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard !combinedMarkdown.isEmpty else {
                throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: "Mistral OCR")
            }

            let textOnlyMarkdown = MistralOCRMarkdown.removingImageMarkdown(from: combinedMarkdown)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let hasText = !textOnlyMarkdown.isEmpty

            var imageParts: [ContentPart] = []
            var attachedImageIDs = Set<String>()
            var totalAttachedImageBytes = 0

            if includeImageBase64 {
                // Decode a limited number of extracted images and attach them for vision-capable models.
                var base64ByID: [String: String] = [:]
                var idsInPageOrder: [String] = []
                var seenIDs = Set<String>()

                for page in pages {
                    for image in page.images ?? [] {
                        let id = image.id
                        if seenIDs.insert(id).inserted {
                            idsInPageOrder.append(id)
                        }
                        if let base64 = image.imageBase64, !base64.isEmpty {
                            base64ByID[id] = base64
                        }
                    }
                }

                let referencedIDs = MistralOCRMarkdown.referencedImageIDs(in: combinedMarkdown)
                var orderedIDs: [String] = []
                orderedIDs.reserveCapacity(max(referencedIDs.count, idsInPageOrder.count))

                var used = Set<String>()
                for id in referencedIDs {
                    if used.insert(id).inserted { orderedIDs.append(id) }
                }
                for id in idsInPageOrder {
                    if used.insert(id).inserted { orderedIDs.append(id) }
                }

                for id in orderedIDs {
                    guard imageParts.count < AttachmentConstants.maxMistralOCRImagesToAttach else { break }
                    guard let base64 = base64ByID[id] else { continue }
                    guard let decoded = PDFProcessingUtilities.decodeMistralOCRImageBase64(base64, imageID: id) else { continue }
                    guard let decodedData = decoded.data else { continue }

                    let nextTotal = totalAttachedImageBytes + decodedData.count
                    guard nextTotal <= AttachmentConstants.maxMistralOCRTotalImageBytes else { break }
                    totalAttachedImageBytes = nextTotal

                    attachedImageIDs.insert(id)
                    imageParts.append(.image(decoded))
                }
            }

            let extractedText: String
            if includeImageBase64 {
                let replaced = MistralOCRMarkdown.replacingImageMarkdown(from: combinedMarkdown) { id in
                    let label = attachedImageIDs.contains(id) ? "Image attached" : "Image omitted"
                    if id.isEmpty { return "[\(label)]" }
                    return "[\(label): \(id)]"
                }
                extractedText = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                extractedText = textOnlyMarkdown
            }

            if !hasText, imageParts.isEmpty {
                // Mistral may return image-only markdown placeholders for scanned PDFs. In that case,
                // text-only models should error, and vision models need extracted images attached.
                throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: "Mistral OCR (image-only — requires vision)")
            }

            var output = extractedText
            if !hasText, !imageParts.isEmpty {
                output = "Mistral OCR extracted images (no text) from this PDF. See attached images."
            }

            let extractedImageCount = pages.reduce(0) { $0 + (($1.images ?? []).count) }
            let omittedCount = max(0, extractedImageCount - attachedImageIDs.count)
            if includeImageBase64, omittedCount > 0 {
                output += "\n\n[Note: \(omittedCount) extracted image(s) omitted due to size limits.]"
            }

            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            output = "Mistral OCR (Markdown): \(attachment.filename)\n\n\(output)"
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.count > AttachmentConstants.maxPDFExtractedCharacters {
                let prefix = output.prefix(AttachmentConstants.maxPDFExtractedCharacters)
                output = "\(prefix)\n\n[Truncated]"
            }
            return PreparedPDFContent(extractedText: output, additionalParts: imageParts)

        case .deepSeekOCR:
            guard let deepSeekClient else { throw PDFProcessingError.deepInfraAPIKeyMissing }

            let includePageImages = profile.supportsVision
            let renderedPages = try PDFKitImageRenderer.renderAllPagesAsJPEG(from: attachment.fileURL)
            let totalPages = max(1, renderedPages.count)

            var pageMarkdown: [String] = []
            pageMarkdown.reserveCapacity(renderedPages.count)

            var imageParts: [ContentPart] = []
            var totalAttachedBytes = 0

            for rendered in renderedPages {
                try Task.checkCancellation()

                await MainActor.run {
                    prepareToSendStatus = "OCR PDF \(pdfOrdinal)/\(max(1, totalPDFCount)) (DeepSeek): \(attachment.filename) — page \(rendered.pageIndex + 1)/\(totalPages)"
                }

                let prompt = "Convert this page to Markdown. Preserve layout and tables. Return only the Markdown."
                let raw = try await deepSeekClient.ocrImage(
                    rendered.data,
                    mimeType: rendered.mimeType,
                    prompt: prompt,
                    timeoutSeconds: 120
                )

                let normalized = PDFProcessingUtilities.normalizedDeepSeekOCRMarkdown(raw)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    pageMarkdown.append(normalized)
                }

                if includePageImages,
                   imageParts.count < AttachmentConstants.maxMistralOCRImagesToAttach {
                    let nextTotal = totalAttachedBytes + rendered.data.count
                    if nextTotal <= AttachmentConstants.maxMistralOCRTotalImageBytes {
                        totalAttachedBytes = nextTotal
                        imageParts.append(.image(ImageContent(mimeType: rendered.mimeType, data: rendered.data, url: nil)))
                    }
                }
            }

            let combined = pageMarkdown
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !combined.isEmpty else {
                throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: "DeepSeek OCR (DeepInfra)")
            }

            var output = combined
            if includePageImages, !imageParts.isEmpty {
                let omitted = max(0, renderedPages.count - imageParts.count)
                output += "\n\n[Note: Attached \(imageParts.count) page image(s) for vision context.]"
                if omitted > 0 {
                    output += "\n[Note: \(omitted) page image(s) omitted due to size limits.]"
                }
            }

            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            output = "DeepSeek OCR (Markdown): \(attachment.filename)\n\n\(output)"
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.count > AttachmentConstants.maxPDFExtractedCharacters {
                let prefix = output.prefix(AttachmentConstants.maxPDFExtractedCharacters)
                output = "\(prefix)\n\n[Truncated]"
            }
            return PreparedPDFContent(extractedText: output, additionalParts: imageParts)

        case .native:
            throw PDFProcessingError.nativePDFNotSupported(modelName: profile.modelName)
        }
    }

    private func makeConversationTitle(from userText: String) -> String {
        let firstLine = userText.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New Chat" }
        return String(trimmed.prefix(48))
    }

    @MainActor
    private func startStreamingResponse(for threadID: UUID, triggeredByUserSend: Bool = false, turnID: UUID? = nil) {
        let conversationID = conversationEntity.id
        guard !streamingStore.isStreaming(conversationID: conversationID, threadID: threadID) else { return }

        guard let thread = sortedModelThreads.first(where: { $0.id == threadID }) else { return }
        let providerID = thread.providerID
        let providerEntity = providers.first(where: { $0.id == providerID })
        let providerTypeSnapshot = providerEntity.flatMap { ProviderType(rawValue: $0.typeRaw) } ?? ProviderType(rawValue: providerID)
        let modelID = effectiveModelID(
            for: thread.modelID,
            providerEntity: providerEntity,
            providerType: providerTypeSnapshot
        )
        migrateThreadModelIDIfNeeded(thread, resolvedModelID: modelID)
        let modelInfoSnapshot = resolvedModelInfo(
            for: modelID,
            providerEntity: providerEntity,
            providerType: providerTypeSnapshot
        )
        let normalizedModelInfoSnapshot = modelInfoSnapshot.map {
            normalizedModelInfo($0, for: providerTypeSnapshot)
        }
        let resolvedModelSettingsSnapshot = normalizedModelInfoSnapshot.map {
            ModelSettingsResolver.resolve(model: $0, providerType: providerTypeSnapshot)
        }
        let modelNameSnapshot = normalizedModelInfoSnapshot?.name ?? modelID
        let streamingState = streamingStore.beginSession(
            conversationID: conversationID,
            threadID: threadID,
            modelLabel: modelNameSnapshot
        )
        streamingState.reset()

        let providerConfig: ProviderConfig?
        if let entity = providerEntity {
            do {
                providerConfig = try entity.toDomain()
            } catch {
                errorMessage = "Failed to load provider configuration: \(error.localizedDescription)"
                showingError = true
                streamingStore.endSession(conversationID: conversationID, threadID: threadID)
                return
            }
        } else {
            providerConfig = nil
        }
        let messageSnapshots = conversationEntity.messages.map { PersistedMessageSnapshot($0) }
        let assistant = conversationEntity.assistant
        let systemPrompt = resolvedSystemPrompt(
            conversationSystemPrompt: conversationEntity.systemPrompt,
            assistant: assistant
        )
        var controlsToUse: GenerationControls
        do {
            controlsToUse = try JSONDecoder().decode(GenerationControls.self, from: thread.modelConfigData)
        } catch {
            errorMessage = "Failed to load conversation settings: \(error.localizedDescription)"
            showingError = true
            streamingStore.endSession(conversationID: conversationID, threadID: threadID)
            return
        }
        controlsToUse = GenerationControlsResolver.resolvedForRequest(
            base: controlsToUse,
            assistantTemperature: assistant?.temperature,
            assistantMaxOutputTokens: assistant?.maxOutputTokens,
            modelMaxOutputTokens: resolvedModelSettingsSnapshot?.maxOutputTokens
        )
        controlsToUse.contextCache = automaticContextCacheControls(
            providerType: providerTypeSnapshot,
            modelID: modelID,
            modelCapabilities: resolvedModelSettingsSnapshot?.capabilities
        )
        Self.sanitizeProviderSpecificForProvider(providerTypeSnapshot, controls: &controlsToUse)
        injectCodexThreadPersistence(into: &controlsToUse, from: thread)

        let shouldTruncateMessages = assistant?.truncateMessages ?? false
        let maxHistoryMessages = assistant?.maxHistoryMessages
        let modelContextWindow = resolvedModelSettingsSnapshot?.contextWindow ?? 128000
        let reservedOutputTokens = max(0, controlsToUse.maxTokens ?? 2048)
        let mcpServerConfigs: [MCPServerConfig]
        do {
            mcpServerConfigs = try resolvedMCPServerConfigs(for: controlsToUse)
        } catch {
            errorMessage = "Failed to load MCP server configs: \(error.localizedDescription)"
            showingError = true
            streamingStore.endSession(conversationID: conversationID, threadID: threadID)
            return
        }
        let chatNamingTarget = resolvedChatNamingTarget()
        let supportsBuiltinSearchPlugin = (resolvedModelSettingsSnapshot?.capabilities.contains(.toolCalling) == true)
            && webSearchPluginEnabled
            && webSearchPluginConfigured
        let supportsNativeSearch = ModelCapabilityRegistry.supportsWebSearch(for: providerTypeSnapshot, modelID: modelID)
        let shouldOfferBuiltinSearch = supportsBuiltinSearchPlugin
            && (!supportsNativeSearch || controlsToUse.searchPlugin?.preferJinSearch == true)
        let networkLogContext = NetworkDebugLogContext(
            conversationID: conversationID.uuidString,
            threadID: threadID.uuidString,
            turnID: turnID?.uuidString
        )

        responseCompletionNotifier.prepareAuthorizationIfNeededWhileActive()

        let task = Task.detached(priority: .userInitiated) {
            await NetworkDebugLogScope.$current.withValue(networkLogContext) {
                var shouldNotifyCompletion = false
                var completionPreview: String?

                do {
                    guard let providerConfig else {
                        throw LLMError.invalidRequest(message: "Provider not found. Configure it in Settings.")
                    }

                let decoder = JSONDecoder()
                var history = messageSnapshots
                    .filter { $0.contextThreadID == threadID }
                    .sorted { lhs, rhs in
                        if lhs.timestamp != rhs.timestamp {
                            return lhs.timestamp < rhs.timestamp
                        }
                        return lhs.id.uuidString < rhs.id.uuidString
                    }
                    .compactMap { $0.toDomain(using: decoder) }
                if let systemPrompt, !systemPrompt.isEmpty {
                    history.insert(Message(role: .system, content: [.text(systemPrompt)]), at: 0)
                }

                // Apply message count limit first if set
                if let maxMessages = maxHistoryMessages, shouldTruncateMessages, history.count > maxMessages {
                    // Keep system messages + last N messages
                    let systemMessages = history.prefix(while: { $0.role == .system })
                    let nonSystemMessages = history.drop(while: { $0.role == .system })
                    let kept = Array(nonSystemMessages.suffix(maxMessages))
                    history = Array(systemMessages) + kept
                }

                // Then apply token-based truncation if enabled
                if shouldTruncateMessages {
                    history = ChatHistoryTruncator.truncatedHistory(
                        history,
                        contextWindow: modelContextWindow,
                        reservedOutputTokens: reservedOutputTokens
                    )
                }

                let providerManager = ProviderManager()
                let adapter = try await providerManager.createAdapter(for: providerConfig)
                let mcpDefinitionsAndRoutes = try await MCPHub.shared.toolDefinitions(for: mcpServerConfigs)
                let (mcpTools, mcpRoutes) = mcpDefinitionsAndRoutes
                let (builtinTools, builtinRoutes) = await BuiltinSearchToolHub.shared.toolDefinitions(
                    for: controlsToUse,
                    useBuiltinSearch: shouldOfferBuiltinSearch
                )
                let allTools = mcpTools + builtinTools
                let providerType = providerConfig.type

                var requestControls = controlsToUse
                let optimizedContextCache = await ContextCacheUtilities.applyAutomaticContextCacheOptimizations(
                    adapter: adapter,
                    providerType: providerType,
                    modelID: modelID,
                    messages: history,
                    controls: requestControls,
                    tools: allTools
                )
                history = optimizedContextCache.messages
                requestControls = optimizedContextCache.controls
                Self.sanitizeProviderSpecificForProvider(providerType, controls: &requestControls)

                var iteration = 0
                let maxToolIterations = 8

                while iteration < maxToolIterations {
                    try Task.checkCancellation()

                    var accumulator = StreamingResponseAccumulator(providerType: providerConfig.type)
                    var metricsCollector = StreamingResponseMetricsCollector()
                    metricsCollector.begin(at: Date())

                    await MainActor.run {
                        streamingState.reset()
                    }

                    let stream = try await adapter.sendMessage(
                        messages: history,
                        modelID: modelID,
                        controls: requestControls,
                        tools: allTools,
                        streaming: resolvedModelSettingsSnapshot?.capabilities.contains(.streaming) ?? true
                    )

                    // Streaming can yield very frequent deltas. Throttle how often we publish changes
                    // to SwiftUI to avoid re-layout/scrolling on every token.
                    var lastUIFlushUptime: TimeInterval = 0
                    var pendingTextDelta = ""
                    var pendingThinkingDelta = ""
                    var streamedCharacterCount = 0

                    func uiFlushInterval() -> TimeInterval {
                        switch streamedCharacterCount {
                        case 0..<4_000:
                            return 0.08
                        case 4_000..<12_000:
                            return 0.10
                        default:
                            return 0.12
                        }
                    }

                    func flushStreamingUI(force: Bool = false) async {
                        let now = ProcessInfo.processInfo.systemUptime
                        guard force || now - lastUIFlushUptime >= uiFlushInterval() else { return }
                        guard force || !pendingTextDelta.isEmpty || !pendingThinkingDelta.isEmpty else { return }

                        lastUIFlushUptime = now
                        let textDelta = pendingTextDelta
                        let thinkingDelta = pendingThinkingDelta
                        pendingTextDelta = ""
                        pendingThinkingDelta = ""

                        await MainActor.run {
                            streamingState.appendDeltas(textDelta: textDelta, thinkingDelta: thinkingDelta)
                        }
                    }

                    for try await event in stream {
                        try Task.checkCancellation()
                        let eventTimestamp = Date()
                        metricsCollector.observe(event: event, at: eventTimestamp)

                        switch event {
                        case .messageStart:
                            break
                        case .contentDelta(let part):
                            if case .text(let delta) = part {
                                accumulator.appendTextDelta(delta)
                                pendingTextDelta.append(delta)
                                streamedCharacterCount += delta.count
                            } else if case .image(let image) = part {
                                accumulator.appendImage(image)
                            } else if case .video(let video) = part {
                                accumulator.appendVideo(video)
                            }
                        case .thinkingDelta(let delta):
                            accumulator.appendThinkingDelta(delta)
                            switch delta {
                            case .thinking(let textDelta, _):
                                if !textDelta.isEmpty {
                                    pendingThinkingDelta.append(textDelta)
                                    streamedCharacterCount += textDelta.count
                                }
                            case .redacted:
                                break
                            }
                        case .toolCallStart(let call):
                            accumulator.upsertToolCall(call)
                            if builtinRoutes.contains(functionName: call.name),
                               let searchActivity = ToolSearchActivityFactory.activityForToolCallStart(
                                   call: call,
                                   providerOverride: builtinRoutes.provider(for: call.name)
                               ) {
                                accumulator.upsertSearchActivity(searchActivity)
                                await MainActor.run {
                                    streamingState.upsertSearchActivity(searchActivity)
                                }
                            }
                            let visibleToolCalls = accumulator.buildToolCalls()
                            await MainActor.run {
                                streamingState.setToolCalls(visibleToolCalls)
                            }
                        case .toolCallDelta:
                            break
                        case .toolCallEnd(let call):
                            accumulator.upsertToolCall(call)
                            let visibleToolCalls = accumulator.buildToolCalls()
                            await MainActor.run {
                                streamingState.setToolCalls(visibleToolCalls)
                            }
                        case .searchActivity(let activity):
                            accumulator.upsertSearchActivity(activity)
                            await MainActor.run {
                                streamingState.upsertSearchActivity(activity)
                            }
                        case .codexToolActivity(let activity):
                            accumulator.upsertCodexToolActivity(activity)
                            await MainActor.run {
                                streamingState.upsertCodexToolActivity(activity)
                            }
                        case .codexInteractionRequest(let request):
                            await flushStreamingUI(force: true)
                            await MainActor.run {
                                pendingCodexInteractions.append(PendingCodexInteraction(localThreadID: threadID, request: request))
                            }
                        case .codexThreadState(let state):
                            requestControls.codexResumeThreadID = state.remoteThreadID
                            requestControls.codexPendingRollbackTurns = 0
                            await MainActor.run {
                                persistCodexThreadState(state, forLocalThreadID: threadID)
                            }
                        case .messageEnd:
                            await MainActor.run {
                                streamingState.markThinkingComplete()
                            }
                        case .error(let err):
                            throw err
                        }

                        await flushStreamingUI()
                    }

                    await flushStreamingUI(force: true)
                    metricsCollector.end(at: Date())

                    let toolCalls = accumulator.buildToolCalls()
                    let assistantParts = accumulator.buildAssistantParts()
                    let searchActivities = accumulator.buildSearchActivities()
                    let codexToolActivities = accumulator.buildCodexToolActivities()
                    let responseMetrics = metricsCollector.metrics
                    var persistedAssistantMessageID: UUID?
                    if !assistantParts.isEmpty || !toolCalls.isEmpty || !searchActivities.isEmpty || !codexToolActivities.isEmpty {
                        let persistedParts = await AttachmentImportPipeline.persistImagesToDisk(assistantParts)
                        let assistantMessage = Message(
                            role: .assistant,
                            content: persistedParts,
                            toolCalls: toolCalls.isEmpty ? nil : toolCalls,
                            searchActivities: searchActivities.isEmpty ? nil : searchActivities,
                            codexToolActivities: codexToolActivities.isEmpty ? nil : codexToolActivities
                        )
                        if let preview = AttachmentImportPipeline.completionNotificationPreview(from: persistedParts) {
                            completionPreview = preview
                        }

                        persistedAssistantMessageID = await MainActor.run {
                            do {
                                let entity = try MessageEntity.fromDomain(assistantMessage)
                                entity.generatedProviderID = providerID
                                entity.generatedModelID = modelID
                                entity.generatedModelName = modelNameSnapshot
                                entity.contextThreadID = threadID
                                entity.turnID = turnID
                                entity.responseMetrics = responseMetrics
                                entity.conversation = conversationEntity
                                conversationEntity.messages.append(entity)
                                conversationEntity.updatedAt = Date()
                                rebuildMessageCaches()
                                try? modelContext.save()
                                // Preserve the assistant bubble so search timeline updates can be merged after tool results.
                                return entity.id
                            } catch {
                                errorMessage = error.localizedDescription
                                showingError = true
                                return nil
                            }
                        }

                        // End streaming atomically with assistant message persistence
                        // to prevent the brief duplicate message flash.
                        if toolCalls.isEmpty {
                            await MainActor.run {
                                streamingStore.endSession(conversationID: conversationID, threadID: threadID)
                            }
                        }

                        history.append(assistantMessage)

                        if triggeredByUserSend,
                           toolCalls.isEmpty,
                           let target = chatNamingTarget {
                            await maybeAutoRenameConversation(
                                targetProvider: target.provider,
                                targetModelID: target.modelID,
                                history: history,
                                finalAssistantMessage: assistantMessage
                            )
                        }
                    }

                    guard !toolCalls.isEmpty else {
                        shouldNotifyCompletion = !assistantParts.isEmpty
                        break
                    }

                    await MainActor.run {
                        streamingState.reset()
                        streamingState.setToolCalls(toolCalls)
                    }

                    var toolResults: [ToolResult] = []
                    var toolOutputLines: [String] = []
                    var toolSearchActivitiesByID: [String: SearchActivity] = [:]
                    var toolSearchActivityOrder: [String] = []

                    func upsertToolSearchActivity(_ activity: SearchActivity) {
                        if let existing = toolSearchActivitiesByID[activity.id] {
                            toolSearchActivitiesByID[activity.id] = existing.merged(with: activity)
                        } else {
                            toolSearchActivityOrder.append(activity.id)
                            toolSearchActivitiesByID[activity.id] = activity
                        }
                    }

                    for call in toolCalls {
                        let callStart = Date()
                        do {
                            let result: MCPToolCallResult
                            if builtinRoutes.contains(functionName: call.name) {
                                result = try await BuiltinSearchToolHub.shared.executeTool(
                                    functionName: call.name,
                                    arguments: call.arguments,
                                    routes: builtinRoutes
                                )
                            } else {
                                result = try await MCPHub.shared.executeTool(
                                    functionName: call.name,
                                    arguments: call.arguments,
                                    routes: mcpRoutes
                                )
                            }
                            let duration = Date().timeIntervalSince(callStart)
                            let normalizedContent = ToolSearchActivityFactory.normalizedToolResultContent(
                                result.text,
                                toolName: call.name,
                                isError: result.isError
                            )
                            let toolResult = ToolResult(
                                toolCallID: call.id,
                                toolName: call.name,
                                content: normalizedContent,
                                isError: result.isError,
                                signature: call.signature,
                                durationSeconds: duration
                            )
                            toolResults.append(toolResult)
                            await MainActor.run {
                                streamingState.upsertToolResult(toolResult)
                            }

                            if result.isError {
                                toolOutputLines.append("Tool \(call.name) failed:\n\(normalizedContent)")
                            } else {
                                toolOutputLines.append("Tool \(call.name):\n\(normalizedContent)")
                            }

                            if builtinRoutes.contains(functionName: call.name),
                               let activity = ToolSearchActivityFactory.activityFromToolResult(
                                call: call,
                                toolResultText: result.text,
                                isError: result.isError,
                                providerOverride: builtinRoutes.provider(for: call.name)
                            ) {
                                upsertToolSearchActivity(activity)
                                await MainActor.run {
                                    streamingState.upsertSearchActivity(activity)
                                }
                            }
                        } catch {
                            let duration = Date().timeIntervalSince(callStart)
                            let normalizedError = ToolSearchActivityFactory.normalizedToolResultContent(
                                error.localizedDescription,
                                toolName: call.name,
                                isError: true
                            )
                            let llmErrorContent = "Tool execution failed: \(normalizedError). You may retry this tool call with corrected arguments."
                            let toolResult = ToolResult(
                                toolCallID: call.id,
                                toolName: call.name,
                                content: llmErrorContent,
                                isError: true,
                                signature: call.signature,
                                durationSeconds: duration
                            )
                            toolResults.append(toolResult)
                            await MainActor.run {
                                streamingState.upsertToolResult(toolResult)
                            }
                            toolOutputLines.append("Tool \(call.name) failed:\n\(llmErrorContent)")

                            if builtinRoutes.contains(functionName: call.name),
                               let activity = ToolSearchActivityFactory.activityFromToolResult(
                                call: call,
                                toolResultText: llmErrorContent,
                                isError: true,
                                providerOverride: builtinRoutes.provider(for: call.name)
                            ) {
                                upsertToolSearchActivity(activity)
                                await MainActor.run {
                                    streamingState.upsertSearchActivity(activity)
                                }
                            }
                        }
                    }

                    let toolSearchActivities = toolSearchActivityOrder.compactMap { toolSearchActivitiesByID[$0] }
                    if let assistantMessageID = persistedAssistantMessageID, !toolSearchActivities.isEmpty {
                        await MainActor.run {
                            mergeSearchActivitiesIntoAssistantMessage(
                                messageID: assistantMessageID,
                                newActivities: toolSearchActivities
                            )
                        }
                    }

                    let toolMessage = Message(
                        role: .tool,
                        content: toolOutputLines.isEmpty ? [] : [.text(toolOutputLines.joined(separator: "\n\n"))],
                        toolResults: toolResults,
                        searchActivities: toolSearchActivities.isEmpty ? nil : toolSearchActivities
                    )
                    await MainActor.run {
                        do {
                            let entity = try MessageEntity.fromDomain(toolMessage)
                            entity.contextThreadID = threadID
                            entity.turnID = turnID
                            entity.conversation = conversationEntity
                            conversationEntity.messages.append(entity)
                            conversationEntity.updatedAt = Date()
                            rebuildMessageCaches()
                            try? modelContext.save()
                        } catch {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                    }
                    history.append(toolMessage)
                    iteration += 1
                }
                } catch is CancellationError {
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                }
                let shouldNotifyNow = shouldNotifyCompletion
                let previewForNotification = completionPreview
                await MainActor.run {
                    if shouldNotifyNow {
                        responseCompletionNotifier.notifyCompletionIfNeeded(
                            conversationID: conversationID,
                            conversationTitle: conversationEntity.title,
                            replyPreview: previewForNotification
                        )
                    }
                    streamingStore.endSession(conversationID: conversationID, threadID: threadID)
                    pendingCodexInteractions.removeAll { $0.localThreadID == threadID }
                }
            }
        }
        streamingStore.attachTask(task, conversationID: conversationID, threadID: threadID)
    }

    private var isChatNamingPluginEnabled: Bool {
        AppPreferences.isPluginEnabled("chat_naming")
    }

    private var chatNamingMode: ChatNamingMode {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: AppPreferenceKeys.chatNamingMode) ?? ChatNamingMode.firstRoundFixed.rawValue
        return ChatNamingMode(rawValue: raw) ?? .firstRoundFixed
    }

    @MainActor
    private func resolvedChatNamingTarget() -> (provider: ProviderConfig, modelID: String)? {
        guard isChatNamingPluginEnabled else { return nil }

        let defaults = UserDefaults.standard
        let providerID = (defaults.string(forKey: AppPreferenceKeys.chatNamingProviderID) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let modelID = (defaults.string(forKey: AppPreferenceKeys.chatNamingModelID) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !providerID.isEmpty, !modelID.isEmpty else { return nil }
        guard let providerEntity = providers.first(where: { $0.id == providerID }),
              let provider = try? providerEntity.toDomain() else {
            return nil
        }

        let models = providerEntity.enabledModels
        guard models.contains(where: { $0.id == modelID }) else { return nil }

        return (provider, modelID)
    }

    @MainActor
    private func maybeAutoRenameConversation(
        targetProvider: ProviderConfig,
        targetModelID: String,
        history: [Message],
        finalAssistantMessage: Message
    ) async {
        guard let latestUser = history.last(where: { $0.role == .user }) else { return }

        if chatNamingMode == .firstRoundFixed {
            let current = conversationEntity.title
            if current != "New Chat" {
                return
            }
        }

        do {
            let title = try await conversationTitleGenerator.generateTitle(
                providerConfig: targetProvider,
                modelID: targetModelID,
                contextMessages: [latestUser, finalAssistantMessage],
                maxCharacters: 40
            )

            let normalized = ConversationTitleGenerator.normalizeTitle(title, maxCharacters: 40)
            guard !normalized.isEmpty else { return }
            conversationEntity.title = normalized
            try? modelContext.save()
        } catch {
            if chatNamingMode == .firstRoundFixed {
                if conversationEntity.title == "New Chat" {
                    conversationEntity.title = fallbackTitleFromMessage(latestUser)
                    try? modelContext.save()
                }
            }
        }
    }

    private func fallbackTitleFromMessage(_ message: Message) -> String {
        let text = message.content.compactMap { part -> String? in
            switch part {
            case .text(let value):
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            case .file(let file):
                let base = (file.filename as NSString).deletingPathExtension
                let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            case .image:
                return "Image"
            case .thinking, .redactedThinking, .audio, .video:
                return nil
            }
        }.first

        guard let text else { return "New Chat" }
        return makeConversationTitle(from: text)
    }

    @MainActor
    private func mergeSearchActivitiesIntoAssistantMessage(
        messageID: UUID,
        newActivities: [SearchActivity]
    ) {
        guard !newActivities.isEmpty else { return }
        guard let entity = conversationEntity.messages.first(where: { $0.id == messageID && $0.role == "assistant" }) else {
            return
        }

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        let existingActivities: [SearchActivity]
        if let data = entity.searchActivitiesData,
           let decoded = try? decoder.decode([SearchActivity].self, from: data) {
            existingActivities = decoded
        } else {
            existingActivities = []
        }

        var order: [String] = []
        var byID: [String: SearchActivity] = [:]

        for activity in existingActivities {
            if byID[activity.id] == nil {
                order.append(activity.id)
            }
            byID[activity.id] = activity
        }

        for activity in newActivities {
            if let existing = byID[activity.id] {
                byID[activity.id] = existing.merged(with: activity)
            } else {
                order.append(activity.id)
                byID[activity.id] = activity
            }
        }

        let mergedActivities = order.compactMap { byID[$0] }
        entity.searchActivitiesData = mergedActivities.isEmpty ? nil : (try? encoder.encode(mergedActivities))
        conversationEntity.updatedAt = Date()
        rebuildMessageCaches()
        try? modelContext.save()
    }
    
    // MARK: - Model Controls (Shortened for brevity, preserving existing logic)
    
    private var providerType: ProviderType? {
        if let provider = providers.first(where: { $0.id == conversationEntity.providerID }),
           let providerType = ProviderType(rawValue: provider.typeRaw) {
            return providerType
        }

        // Fallback: for the built-in providers, `providerID` matches the provider type.
        return ProviderType(rawValue: conversationEntity.providerID)
    }

    private var reasoningLabel: String {
        guard supportsReasoningControl else { return "Not supported" }
        guard isReasoningEnabled else { return "Off" }

        guard let reasoningType = selectedReasoningConfig?.type, reasoningType != .none else { return "Not supported" }

        switch reasoningType {
        case .budget:
            guard let budgetTokens = controls.reasoning?.budgetTokens else { return "On" }
            return "\(budgetTokens) tokens"
        case .effort:
            if providerType == .anthropic {
                if anthropicUsesEffortMode {
                    let effort = controls.reasoning?.effort ?? selectedReasoningConfig?.defaultEffort ?? .high
                    return effort == .xhigh ? "Max" : effort.displayName
                }
                let budgetTokens = controls.reasoning?.budgetTokens ?? anthropicDefaultBudgetTokens
                return "\(budgetTokens) tokens"
            }
            return controls.reasoning?.effort?.displayName ?? "On"
        case .toggle:
            return "On"
        case .none:
            return "Not supported"
        }
    }

    private var supportsReasoningSummaryControl: Bool {
        providerType == .openai || providerType == .openaiWebSocket || providerType == .codexAppServer
    }

    @ViewBuilder
    private var reasoningMenuContent: some View {
        if let reasoningConfig = selectedReasoningConfig, reasoningConfig.type != .none {
            if supportsReasoningDisableToggle {
                Button { setReasoningOff() } label: { menuItemLabel("Off", isSelected: !isReasoningEnabled) }
            }

            switch reasoningConfig.type {
            case .toggle:
                Button { setReasoningOn() } label: { menuItemLabel("On", isSelected: isReasoningEnabled) }

                if supportsCerebrasPreservedThinkingToggle {
                    Divider()
                    Toggle("Preserve thinking", isOn: cerebrasPreserveThinkingBinding)
                        .help("Keeps GLM thinking across turns (maps to clear_thinking: false).")
                }

            case .effort:
                if providerType == .anthropic {
                    Button { openThinkingBudgetEditor() } label: {
                        menuItemLabel("Configure thinking\u{2026}", isSelected: isReasoningEnabled)
                    }
                } else {
                    effortLevelButtons(for: availableReasoningEffortLevels)

                    if supportsReasoningSummaryControl {
                        Divider()
                        Text("Reasoning summary")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(ReasoningSummary.allCases, id: \.self) { summary in
                            Button {
                                setReasoningSummary(summary)
                            } label: {
                                menuItemLabel(summary.displayName, isSelected: (controls.reasoning?.summary ?? .auto) == summary)
                            }
                        }
                    }
                }

                if supportsFireworksReasoningHistoryToggle {
                    Divider()
                    Text("Thinking history")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button { setFireworksReasoningHistory(nil) } label: { menuItemLabel("Default (model)", isSelected: fireworksReasoningHistory == nil) }
                    ForEach(fireworksReasoningHistoryOptions, id: \.self) { option in
                        Button {
                            setFireworksReasoningHistory(option)
                        } label: {
                            menuItemLabel(
                                fireworksReasoningHistoryLabel(for: option),
                                isSelected: fireworksReasoningHistory == option
                            )
                        }
                    }
                }

            case .budget:
                Button { openThinkingBudgetEditor() } label: {
                    let current = controls.reasoning?.budgetTokens ?? reasoningConfig.defaultBudget ?? 1024
                    menuItemLabel("Budget tokens… (\(current))", isSelected: isReasoningEnabled)
                }

            case .none:
                EmptyView()
            }
        } else {
            Text("Not supported")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var openAIServiceTierMenuContent: some View {
        Button { setOpenAIServiceTier(nil) } label: {
            menuItemLabel("Auto (OpenAI default)", isSelected: controls.openAIServiceTier == nil)
        }

        Divider()

        ForEach(OpenAIServiceTier.allCases, id: \.self) { serviceTier in
            Button {
                setOpenAIServiceTier(serviceTier)
            } label: {
                menuItemLabel(serviceTier.displayName, isSelected: controls.openAIServiceTier == serviceTier)
            }
        }
    }

    private func setOpenAIServiceTier(_ serviceTier: OpenAIServiceTier?) {
        controls.openAIServiceTier = serviceTier
        persistControlsToConversation()
    }

    private var supportsFireworksReasoningHistoryToggle: Bool {
        !fireworksReasoningHistoryOptions.isEmpty
    }

    private var fireworksReasoningHistoryOptions: [String] {
        guard providerType == .fireworks else { return [] }
        if isFireworksMiniMaxM2FamilyModel(conversationEntity.modelID) {
            return ["interleaved", "disabled"]
        }
        if isFireworksModelID(conversationEntity.modelID, canonicalID: "kimi-k2p5")
            || isFireworksModelID(conversationEntity.modelID, canonicalID: "glm-4p7")
            || isFireworksModelID(conversationEntity.modelID, canonicalID: "glm-5") {
            return ["preserved", "interleaved", "disabled"]
        }
        return []
    }

    private var fireworksReasoningHistory: String? {
        controls.providerSpecific["reasoning_history"]?.value as? String
    }

    private func setFireworksReasoningHistory(_ value: String?) {
        if let value {
            controls.providerSpecific["reasoning_history"] = AnyCodable(value)
        } else {
            controls.providerSpecific.removeValue(forKey: "reasoning_history")
        }
        persistControlsToConversation()
    }

    private func isFireworksModelID(_ modelID: String, canonicalID: String) -> Bool {
        fireworksCanonicalModelID(modelID) == canonicalID
    }

    private func fireworksReasoningHistoryLabel(for option: String) -> String {
        switch option {
        case "preserved":
            return "Preserved"
        case "interleaved":
            return "Interleaved"
        case "disabled":
            return "Disabled"
        default:
            return option
        }
    }

    private var supportsCerebrasPreservedThinkingToggle: Bool {
        guard providerType == .cerebras else { return false }
        return conversationEntity.modelID.lowercased() == "zai-glm-4.7"
    }

    private var cerebrasPreserveThinkingBinding: Binding<Bool> {
        Binding(
            get: {
                // Cerebras `clear_thinking` defaults to true. Preserve thinking == clear_thinking false.
                let clear = (controls.providerSpecific["clear_thinking"]?.value as? Bool) ?? true
                return clear == false
            },
            set: { preserve in
                if preserve {
                    controls.providerSpecific["clear_thinking"] = AnyCodable(false)
                } else {
                    // Use provider default (clear_thinking true).
                    controls.providerSpecific.removeValue(forKey: "clear_thinking")
                }
                persistControlsToConversation()
            }
        )
    }

    private func menuItemLabel(_ title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
                .fixedSize()
            if isSelected {
                Spacer()
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var availableReasoningEffortLevels: [ReasoningEffort] {
        ModelCapabilityRegistry.supportedReasoningEfforts(
            for: providerType,
            modelID: conversationEntity.modelID
        )
    }

    @ViewBuilder
    private func effortLevelButtons(for levels: [ReasoningEffort]) -> some View {
        ForEach(levels, id: \.self) { level in
            Button { setReasoningEffort(level) } label: {
                menuItemLabel(
                    level == .xhigh ? "Extreme" : level.displayName,
                    isSelected: isReasoningEnabled && controls.reasoning?.effort == level
                )
            }
        }
    }

    private var webSearchEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                if providerType == .perplexity {
                    return controls.webSearch?.enabled ?? true
                }
                return controls.webSearch?.enabled ?? false
            },
            set: { enabled in
                if controls.webSearch == nil {
                    controls.webSearch = defaultWebSearchControls(enabled: enabled)
                } else {
                    controls.webSearch?.enabled = enabled
                    ensureValidWebSearchDefaultsIfEnabled()
                }
                persistControlsToConversation()
            }
        )
    }

    @ViewBuilder
    private var webSearchMenuContent: some View {
        Toggle("Web Search", isOn: webSearchEnabledBinding)
        if isWebSearchEnabled {
            if supportsSearchEngineModeSwitch {
                Divider()
                Menu("Engine") {
                    Button {
                        setSearchEnginePreference(useJinSearch: false)
                    } label: {
                        menuItemLabel("Native", isSelected: !usesBuiltinSearchPlugin)
                    }

                    Button {
                        setSearchEnginePreference(useJinSearch: true)
                    } label: {
                        menuItemLabel("Jin Search", isSelected: usesBuiltinSearchPlugin)
                    }
                }
            }

            if usesBuiltinSearchPlugin {
                Divider()
                Menu("Provider") {
                    ForEach(SearchPluginProvider.allCases) { provider in
                        Button {
                            if controls.searchPlugin == nil {
                                controls.searchPlugin = SearchPluginControls()
                            }
                            controls.searchPlugin?.provider = provider
                            persistControlsToConversation()
                        } label: {
                            menuItemLabel(
                                provider.displayName,
                                isSelected: effectiveSearchPluginProvider == provider
                            )
                        }
                    }
                }

                Menu("Max Results") {
                    let current = controls.searchPlugin?.maxResults ?? WebSearchPluginSettingsStore.load().defaultMaxResults
                    ForEach([3, 5, 8, 10, 20, 30, 50], id: \.self) { value in
                        Button {
                            if controls.searchPlugin == nil {
                                controls.searchPlugin = SearchPluginControls()
                            }
                            controls.searchPlugin?.maxResults = value
                            persistControlsToConversation()
                        } label: {
                            menuItemLabel("\(value)", isSelected: current == value)
                        }
                    }
                }

                Menu("Recency") {
                    let current = controls.searchPlugin?.recencyDays
                    Button {
                        if controls.searchPlugin == nil {
                            controls.searchPlugin = SearchPluginControls()
                        }
                        controls.searchPlugin?.recencyDays = nil
                        persistControlsToConversation()
                    } label: {
                        menuItemLabel("Any time", isSelected: current == nil)
                    }

                    ForEach([1, 7, 30, 90], id: \.self) { value in
                        Button {
                            if controls.searchPlugin == nil {
                                controls.searchPlugin = SearchPluginControls()
                            }
                            controls.searchPlugin?.recencyDays = value
                            persistControlsToConversation()
                        } label: {
                            menuItemLabel("Past \(value)d", isSelected: current == value)
                        }
                    }
                }

                Divider()
                Toggle("Include raw snippets", isOn: builtinSearchIncludeRawBinding)

                if effectiveSearchPluginProvider == .jina {
                    Toggle("Fetch pages via Reader", isOn: builtinSearchFetchPageBinding)
                } else if effectiveSearchPluginProvider == .firecrawl {
                    Toggle("Extract markdown", isOn: builtinSearchFirecrawlExtractBinding)
                }
            } else {
                switch providerType {
                case .openai, .openaiWebSocket:
                    Divider()
                    ForEach(WebSearchContextSize.allCases, id: \.self) { size in
                        Button {
                            controls.webSearch?.contextSize = size
                            persistControlsToConversation()
                        } label: {
                            menuItemLabel(size.displayName, isSelected: (controls.webSearch?.contextSize ?? .medium) == size)
                        }
                    }
                case .perplexity:
                    Divider()
                    ForEach(WebSearchContextSize.allCases, id: \.self) { size in
                        Button {
                            if controls.webSearch == nil {
                                controls.webSearch = defaultWebSearchControls(enabled: true)
                            }
                            controls.webSearch?.contextSize = size
                            persistControlsToConversation()
                        } label: {
                            menuItemLabel(size.displayName, isSelected: (controls.webSearch?.contextSize ?? .low) == size)
                        }
                    }
                case .xai:
                    Divider()
                    Toggle("Web", isOn: webSearchSourceBinding(.web))
                    Toggle("X", isOn: webSearchSourceBinding(.x))

                    if Set(controls.webSearch?.sources ?? []).isEmpty {
                        Divider()
                        Text("Select at least one source.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .anthropic:
                    Divider()
                    Menu("Max Uses") {
                        let current = controls.webSearch?.maxUses
                        Button {
                            controls.webSearch?.maxUses = nil
                            persistControlsToConversation()
                        } label: {
                            menuItemLabel("Default (10)", isSelected: current == nil)
                        }
                        ForEach([1, 3, 5, 10, 20], id: \.self) { value in
                            Button {
                                controls.webSearch?.maxUses = value
                                persistControlsToConversation()
                            } label: {
                                menuItemLabel("\(value)", isSelected: current == value)
                            }
                        }
                    }
                    if supportsAnthropicDynamicFiltering {
                        Toggle("Dynamic Filtering", isOn: Binding(
                            get: { controls.webSearch?.dynamicFiltering ?? false },
                            set: { newValue in
                                controls.webSearch?.dynamicFiltering = newValue ? true : nil
                                persistControlsToConversation()
                            }
                        ))
                    }
                    Divider()
                    Button("Configure\u{2026}") {
                        openAnthropicWebSearchEditor()
                    }
                case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq,
                     .cohere, .mistral, .deepinfra, .together, .gemini, .vertexai, .deepseek,
                     .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .none:
                    EmptyView()
                }
            }
        }
    }

    private func setSearchEnginePreference(useJinSearch: Bool) {
        if controls.searchPlugin == nil {
            controls.searchPlugin = SearchPluginControls()
        }
        controls.searchPlugin?.preferJinSearch = useJinSearch
        persistControlsToConversation()
    }

    @ViewBuilder
    private var contextCacheMenuContent: some View {
        Button {
            controls.contextCache = ContextCacheControls(mode: .off)
            persistControlsToConversation()
        } label: {
            menuItemLabel("Off", isSelected: effectiveContextCacheMode == .off)
        }

        Button {
            var cache = controls.contextCache ?? ContextCacheControls(mode: .implicit)
            cache.mode = .implicit
            if providerType != .anthropic {
                cache.strategy = nil
            }
            if providerType != .openai && providerType != .openaiWebSocket && providerType != .xai {
                cache.cacheKey = nil
            }
            if providerType != .xai {
                cache.minTokensThreshold = nil
            }
            if providerType != .xai {
                cache.conversationID = nil
            }
            if providerType != .gemini && providerType != .vertexai {
                cache.cachedContentName = nil
            }
            controls.contextCache = cache
            persistControlsToConversation()
        } label: {
            menuItemLabel("Implicit", isSelected: effectiveContextCacheMode == .implicit)
        }

        if supportsExplicitContextCacheMode {
            Button {
                var cache = controls.contextCache ?? ContextCacheControls(mode: .explicit)
                cache.mode = .explicit
                controls.contextCache = cache
                persistControlsToConversation()
            } label: {
                menuItemLabel("Explicit", isSelected: effectiveContextCacheMode == .explicit)
            }
        }

        Divider()

        Button("Configure…") {
            openContextCacheEditor()
        }

        if controls.contextCache != nil {
            Divider()
            Button("Reset", role: .destructive) {
                controls.contextCache = nil
                persistControlsToConversation()
            }
        }
    }

    private var mcpToolsEnabledBinding: Binding<Bool> {
        Binding(
            get: { controls.mcpTools?.enabled == true },
            set: { enabled in
                if controls.mcpTools == nil {
                    controls.mcpTools = MCPToolsControls(enabled: enabled)
                } else {
                    controls.mcpTools?.enabled = enabled
                }
                persistControlsToConversation()
            }
        )
    }

    @ViewBuilder
    private var mcpToolsMenuContent: some View {
        Toggle("MCP Tools", isOn: mcpToolsEnabledBinding)

        if isMCPToolsEnabled {
            if eligibleMCPServers.isEmpty {
                Divider()
                Text("No MCP servers enabled for automatic tool use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Divider()
                Text("Servers")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(eligibleMCPServers, id: \.id) { server in
                    Toggle(server.name, isOn: mcpServerSelectionBinding(serverID: server.id))
                }

                if selectedMCPServerIDs.isEmpty {
                    Divider()
                    Text("Select at least one server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if controls.mcpTools?.enabledServerIDs != nil {
                    Divider()
                    Button("Use all servers") {
                        resetMCPServerSelection()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var imageGenerationMenuContent: some View {
        if providerType == .xai {
            Text("xAI Image")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Menu("Count") {
                Button { updateXAIImageGeneration { $0.count = nil } } label: {
                    menuItemLabel("Default", isSelected: controls.xaiImageGeneration?.count == nil)
                }
                ForEach([1, 2, 4], id: \.self) { count in
                    Button { updateXAIImageGeneration { $0.count = count } } label: {
                        menuItemLabel("\(count)", isSelected: (controls.xaiImageGeneration?.count ?? 1) == count)
                    }
                }
            }

            Menu("Aspect ratio") {
                Button { updateXAIImageGeneration { $0.aspectRatio = nil } } label: {
                    let selected = controls.xaiImageGeneration?.aspectRatio == nil
                        && controls.xaiImageGeneration?.size == nil
                    menuItemLabel("Default", isSelected: selected)
                }
                ForEach(XAIAspectRatio.allCases, id: \.self) { ratio in
                    Button {
                        updateXAIImageGeneration {
                            $0.aspectRatio = ratio
                            $0.size = nil // legacy fallback only
                        }
                    } label: {
                        menuItemLabel(
                            ratio.displayName,
                            isSelected: (controls.xaiImageGeneration?.aspectRatio ?? controls.xaiImageGeneration?.size?.mappedAspectRatio) == ratio
                        )
                    }
                }
            }

            if isImageGenerationConfigured {
                Divider()
                Button("Reset", role: .destructive) {
                    controls.xaiImageGeneration = nil
                    persistControlsToConversation()
                }
            }
        } else if providerType == .openai || providerType == .openaiWebSocket {
            openAIImageGenerationMenuContent
        } else {
            Button("Edit…") {
                openImageGenerationEditor()
            }

            if isImageGenerationConfigured {
                Divider()
                Button("Reset", role: .destructive) {
                    controls.imageGeneration = nil
                    persistControlsToConversation()
                }
            }
        }
    }

    // MARK: - OpenAI Image Generation Menu

    @ViewBuilder
    private var openAIImageGenerationMenuContent: some View {
        let isGPTImageModel = lowerModelID.hasPrefix("gpt-image")
        let isDallE3 = lowerModelID.hasPrefix("dall-e-3")
        let isDallE2 = lowerModelID.hasPrefix("dall-e-2")

        Text("OpenAI Image")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Menu("Count") {
            Button { updateOpenAIImageGeneration { $0.count = nil } } label: {
                menuItemLabel("Default (1)", isSelected: controls.openaiImageGeneration?.count == nil)
            }
            ForEach([1, 2, 4], id: \.self) { count in
                Button { updateOpenAIImageGeneration { $0.count = count } } label: {
                    menuItemLabel("\(count)", isSelected: controls.openaiImageGeneration?.count == count)
                }
            }
        }

        Menu("Size") {
            let sizes: [OpenAIImageSize] = isGPTImageModel
                ? OpenAIImageSize.gptImageSizes
                : isDallE3 ? OpenAIImageSize.dallE3Sizes
                : isDallE2 ? OpenAIImageSize.dallE2Sizes
                : OpenAIImageSize.gptImageSizes

            Button { updateOpenAIImageGeneration { $0.size = nil } } label: {
                menuItemLabel("Default", isSelected: controls.openaiImageGeneration?.size == nil)
            }
            ForEach(sizes, id: \.self) { size in
                Button { updateOpenAIImageGeneration { $0.size = size } } label: {
                    menuItemLabel(size.displayName, isSelected: controls.openaiImageGeneration?.size == size)
                }
            }
        }

        let qualities: [OpenAIImageQuality] = isGPTImageModel
            ? OpenAIImageQuality.gptImageQualities
            : isDallE3 ? OpenAIImageQuality.dallE3Qualities
            : []

        if !qualities.isEmpty {
            Menu("Quality") {
                Button { updateOpenAIImageGeneration { $0.quality = nil } } label: {
                    menuItemLabel("Default", isSelected: controls.openaiImageGeneration?.quality == nil)
                }
                ForEach(qualities, id: \.self) { quality in
                    Button { updateOpenAIImageGeneration { $0.quality = quality } } label: {
                        menuItemLabel(quality.displayName, isSelected: controls.openaiImageGeneration?.quality == quality)
                    }
                }
            }
        }

        if isDallE3 {
            Menu("Style") {
                Button { updateOpenAIImageGeneration { $0.style = nil } } label: {
                    menuItemLabel("Default (Vivid)", isSelected: controls.openaiImageGeneration?.style == nil)
                }
                ForEach(OpenAIImageStyle.allCases, id: \.self) { style in
                    Button { updateOpenAIImageGeneration { $0.style = style } } label: {
                        menuItemLabel(style.displayName, isSelected: controls.openaiImageGeneration?.style == style)
                    }
                }
            }
        }

        if isGPTImageModel {
            Menu("Background") {
                Button { updateOpenAIImageGeneration { $0.background = nil } } label: {
                    menuItemLabel("Default (Auto)", isSelected: controls.openaiImageGeneration?.background == nil)
                }
                ForEach(OpenAIImageBackground.allCases, id: \.self) { bg in
                    Button { updateOpenAIImageGeneration { $0.background = bg } } label: {
                        menuItemLabel(bg.displayName, isSelected: controls.openaiImageGeneration?.background == bg)
                    }
                }
            }

            Menu("Output Format") {
                Button { updateOpenAIImageGeneration { $0.outputFormat = nil } } label: {
                    menuItemLabel("Default (PNG)", isSelected: controls.openaiImageGeneration?.outputFormat == nil)
                }
                ForEach(OpenAIImageOutputFormat.allCases, id: \.self) { format in
                    Button { updateOpenAIImageGeneration { $0.outputFormat = format } } label: {
                        menuItemLabel(format.displayName, isSelected: controls.openaiImageGeneration?.outputFormat == format)
                    }
                }
            }

            if controls.openaiImageGeneration?.outputFormat == .jpeg || controls.openaiImageGeneration?.outputFormat == .webp {
                Menu("Compression") {
                    Button { updateOpenAIImageGeneration { $0.outputCompression = nil } } label: {
                        menuItemLabel("Default (100)", isSelected: controls.openaiImageGeneration?.outputCompression == nil)
                    }
                    ForEach([25, 50, 75, 100], id: \.self) { level in
                        Button { updateOpenAIImageGeneration { $0.outputCompression = level } } label: {
                            menuItemLabel("\(level)%", isSelected: controls.openaiImageGeneration?.outputCompression == level)
                        }
                    }
                }
            }

            Menu("Moderation") {
                Button { updateOpenAIImageGeneration { $0.moderation = nil } } label: {
                    menuItemLabel("Default (Auto)", isSelected: controls.openaiImageGeneration?.moderation == nil)
                }
                ForEach(OpenAIImageModeration.allCases, id: \.self) { mod in
                    Button { updateOpenAIImageGeneration { $0.moderation = mod } } label: {
                        menuItemLabel(mod.displayName, isSelected: controls.openaiImageGeneration?.moderation == mod)
                    }
                }
            }

            // Input fidelity (gpt-image-1 only) — controls style/feature matching for edits
            if lowerModelID == "gpt-image-1" {
                Menu("Input Fidelity") {
                    Button { updateOpenAIImageGeneration { $0.inputFidelity = nil } } label: {
                        menuItemLabel("Default (Low)", isSelected: controls.openaiImageGeneration?.inputFidelity == nil)
                    }
                    ForEach(OpenAIImageInputFidelity.allCases, id: \.self) { fidelity in
                        Button { updateOpenAIImageGeneration { $0.inputFidelity = fidelity } } label: {
                            menuItemLabel(fidelity.displayName, isSelected: controls.openaiImageGeneration?.inputFidelity == fidelity)
                        }
                    }
                }
            }
        }

        if isImageGenerationConfigured {
            Divider()
            Button("Reset", role: .destructive) {
                controls.openaiImageGeneration = nil
                persistControlsToConversation()
            }
        }
    }

    private func updateOpenAIImageGeneration(_ mutate: (inout OpenAIImageGenerationControls) -> Void) {
        var draft = controls.openaiImageGeneration ?? OpenAIImageGenerationControls()
        mutate(&draft)

        // If background is transparent, ensure output format supports transparency
        if draft.background == .transparent {
            if let format = draft.outputFormat, format == .jpeg {
                draft.outputFormat = .png
            }
        }

        // Clear compression if format doesn't support it
        if let format = draft.outputFormat, format == .png {
            draft.outputCompression = nil
        }
        if draft.outputFormat == nil {
            draft.outputCompression = nil
        }

        controls.openaiImageGeneration = draft.isEmpty ? nil : draft
        persistControlsToConversation()
    }

    private func updateXAIImageGeneration(_ mutate: (inout XAIImageGenerationControls) -> Void) {
        var draft = controls.xaiImageGeneration ?? XAIImageGenerationControls()
        mutate(&draft)

        // These legacy fields are not supported by current xAI image APIs.
        draft.quality = nil
        draft.style = nil
        if draft.aspectRatio != nil {
            draft.size = nil
        }

        controls.xaiImageGeneration = draft.isEmpty ? nil : draft
        persistControlsToConversation()
    }

    @ViewBuilder
    private var videoGenerationMenuContent: some View {
        switch providerType {
        case .gemini, .vertexai:
            googleVideoGenerationMenuContent
        case .xai:
            xaiVideoGenerationMenuContent
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var googleVideoGenerationMenuContent: some View {
        let isVeo3 = GoogleVideoGenerationCore.isVeo3OrLater(conversationEntity.modelID)
        let isVertexProvider = providerType == .vertexai

        Text("Google Veo")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Menu("Duration") {
            Button { updateGoogleVideoGeneration { $0.durationSeconds = nil } } label: {
                menuItemLabel("Default", isSelected: controls.googleVideoGeneration?.durationSeconds == nil)
            }
            ForEach([4, 6, 8], id: \.self) { seconds in
                Button { updateGoogleVideoGeneration { $0.durationSeconds = seconds } } label: {
                    menuItemLabel("\(seconds)s", isSelected: controls.googleVideoGeneration?.durationSeconds == seconds)
                }
            }
        }

        Menu("Aspect ratio") {
            Button { updateGoogleVideoGeneration { $0.aspectRatio = nil } } label: {
                menuItemLabel("Default (16:9)", isSelected: controls.googleVideoGeneration?.aspectRatio == nil)
            }
            ForEach(GoogleVideoAspectRatio.allCases, id: \.self) { ratio in
                Button { updateGoogleVideoGeneration { $0.aspectRatio = ratio } } label: {
                    menuItemLabel(ratio.displayName, isSelected: controls.googleVideoGeneration?.aspectRatio == ratio)
                }
            }
        }

        if isVeo3 {
            Menu("Resolution") {
                Button { updateGoogleVideoGeneration { $0.resolution = nil } } label: {
                    menuItemLabel("Default (720p)", isSelected: controls.googleVideoGeneration?.resolution == nil)
                }
                ForEach(GoogleVideoResolution.allCases, id: \.self) { res in
                    Button { updateGoogleVideoGeneration { $0.resolution = res } } label: {
                        menuItemLabel(res.displayName, isSelected: controls.googleVideoGeneration?.resolution == res)
                    }
                }
            }
        }

        Menu("Person generation") {
            Button { updateGoogleVideoGeneration { $0.personGeneration = nil } } label: {
                menuItemLabel("Default", isSelected: controls.googleVideoGeneration?.personGeneration == nil)
            }
            ForEach(GoogleVideoPersonGeneration.allCases, id: \.self) { person in
                Button { updateGoogleVideoGeneration { $0.personGeneration = person } } label: {
                    menuItemLabel(person.displayName, isSelected: controls.googleVideoGeneration?.personGeneration == person)
                }
            }
        }

        // generateAudio is only a valid parameter for Vertex AI Veo 3 models.
        // Gemini API Veo 3+ models generate audio natively by default.
        if isVertexProvider, isVeo3 {
            Toggle(
                "Generate audio",
                isOn: Binding(
                    get: { controls.googleVideoGeneration?.generateAudio ?? false },
                    set: { newValue in
                        updateGoogleVideoGeneration { $0.generateAudio = newValue ? true : nil }
                    }
                )
            )
        }

        if isVideoGenerationConfigured {
            Divider()
            Button("Reset", role: .destructive) {
                controls.googleVideoGeneration = nil
                persistControlsToConversation()
            }
        }
    }

    @ViewBuilder
    private var xaiVideoGenerationMenuContent: some View {
        Text("xAI Video")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Menu("Duration") {
            Button { updateXAIVideoGeneration { $0.duration = nil } } label: {
                menuItemLabel("Default (8s)", isSelected: controls.xaiVideoGeneration?.duration == nil)
            }
            ForEach([3, 5, 8, 10, 15], id: \.self) { seconds in
                Button { updateXAIVideoGeneration { $0.duration = seconds } } label: {
                    menuItemLabel("\(seconds)s", isSelected: controls.xaiVideoGeneration?.duration == seconds)
                }
            }
        }

        Menu("Aspect ratio") {
            Button { updateXAIVideoGeneration { $0.aspectRatio = nil } } label: {
                menuItemLabel("Default (16:9)", isSelected: controls.xaiVideoGeneration?.aspectRatio == nil)
            }
            ForEach(
                [XAIAspectRatio.ratio1x1, .ratio16x9, .ratio9x16, .ratio4x3, .ratio3x4, .ratio3x2, .ratio2x3],
                id: \.self
            ) { ratio in
                Button { updateXAIVideoGeneration { $0.aspectRatio = ratio } } label: {
                    menuItemLabel(ratio.displayName, isSelected: controls.xaiVideoGeneration?.aspectRatio == ratio)
                }
            }
        }

        Menu("Resolution") {
            Button { updateXAIVideoGeneration { $0.resolution = nil } } label: {
                menuItemLabel("Default (480p)", isSelected: controls.xaiVideoGeneration?.resolution == nil)
            }
            ForEach(XAIVideoResolution.allCases, id: \.self) { res in
                Button { updateXAIVideoGeneration { $0.resolution = res } } label: {
                    menuItemLabel(res.displayName, isSelected: controls.xaiVideoGeneration?.resolution == res)
                }
            }
        }

        if isVideoGenerationConfigured {
            Divider()
            Button("Reset", role: .destructive) {
                controls.xaiVideoGeneration = nil
                persistControlsToConversation()
            }
        }
    }

    private func updateXAIVideoGeneration(_ mutate: (inout XAIVideoGenerationControls) -> Void) {
        var draft = controls.xaiVideoGeneration ?? XAIVideoGenerationControls()
        mutate(&draft)
        controls.xaiVideoGeneration = draft.isEmpty ? nil : draft
        persistControlsToConversation()
    }

    private func updateGoogleVideoGeneration(_ mutate: (inout GoogleVideoGenerationControls) -> Void) {
        var draft = controls.googleVideoGeneration ?? GoogleVideoGenerationControls()
        mutate(&draft)
        controls.googleVideoGeneration = draft.isEmpty ? nil : draft
        persistControlsToConversation()
    }

    private func openImageGenerationEditor() {
        var current = controls.imageGeneration ?? ImageGenerationControls()
        if let ratio = current.aspectRatio, !supportedCurrentModelImageAspectRatios.contains(ratio) {
            current.aspectRatio = nil
        }
        if let size = current.imageSize, !supportedCurrentModelImageSizes.contains(size) {
            current.imageSize = nil
        }
        imageGenerationDraft = current
        imageGenerationSeedDraft = current.seed.map(String.init) ?? ""
        imageGenerationCompressionQualityDraft = current.vertexCompressionQuality.map(String.init) ?? ""
        imageGenerationDraftError = nil
        showingImageGenerationSheet = true
    }

    private func openCodexSessionSettingsEditor() {
        codexWorkingDirectoryDraft = codexWorkingDirectory ?? ""
        codexWorkingDirectoryDraftError = nil
        codexSandboxModeDraft = controls.codexSandboxMode
        codexPersonalityDraft = controls.codexPersonality
        showingCodexSessionSettingsSheet = true
    }

    private func pickCodexWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Select"
        panel.message = "Choose a working directory to send as Codex `cwd`."

        if let existing = normalizedCodexWorkingDirectoryPath(from: codexWorkingDirectoryDraft) {
            panel.directoryURL = URL(fileURLWithPath: existing, isDirectory: true)
        }

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        codexWorkingDirectoryDraft = selectedURL.path
        codexWorkingDirectoryDraftError = nil
    }

    private func applyCodexSessionSettingsDraft() {
        let trimmed = codexWorkingDirectoryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            controls.codexWorkingDirectory = nil
            controls.codexSandboxMode = codexSandboxModeDraft
            controls.codexPersonality = codexPersonalityDraft
            persistControlsToConversation()
            codexWorkingDirectoryDraftError = nil
            showingCodexSessionSettingsSheet = false
            return
        }

        guard let normalized = normalizedCodexWorkingDirectoryPath(from: trimmed) else {
            codexWorkingDirectoryDraftError = "Choose an existing local folder (absolute path or ~/path)."
            return
        }

        controls.codexWorkingDirectory = normalized
        controls.codexSandboxMode = codexSandboxModeDraft
        controls.codexPersonality = codexPersonalityDraft
        persistControlsToConversation()
        codexWorkingDirectoryDraft = normalized
        codexWorkingDirectoryDraftError = nil
        showingCodexSessionSettingsSheet = false
    }

    private func resolveCodexInteraction(_ item: PendingCodexInteraction, response: CodexInteractionResponse) {
        Task {
            await item.request.resolve(response)
        }
        pendingCodexInteractions.removeAll { $0.id == item.id }
    }

    private func normalizedCodexWorkingDirectoryPath(from raw: String) -> String? {
        CodexWorkingDirectoryPresetsStore.normalizedDirectoryPath(from: raw, requireExistingDirectory: true)
    }

    private var isImageGenerationDraftValid: Bool {
        let seedText = imageGenerationSeedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !seedText.isEmpty, Int(seedText) == nil {
            return false
        }

        let qualityText = imageGenerationCompressionQualityDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !qualityText.isEmpty {
            guard let quality = Int(qualityText), (0...100).contains(quality) else {
                return false
            }
        }

        return true
    }

    @discardableResult
    private func applyImageGenerationDraft() -> Bool {
        var draft = imageGenerationDraft

        let seedText = imageGenerationSeedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if seedText.isEmpty {
            draft.seed = nil
        } else if let seed = Int(seedText) {
            draft.seed = seed
        } else {
            imageGenerationDraftError = "Seed must be an integer."
            return false
        }

        let qualityText = imageGenerationCompressionQualityDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if qualityText.isEmpty {
            draft.vertexCompressionQuality = nil
        } else if let quality = Int(qualityText), (0...100).contains(quality) {
            draft.vertexCompressionQuality = quality
        } else {
            imageGenerationDraftError = "JPEG quality must be an integer between 0 and 100."
            return false
        }

        if !supportsCurrentModelImageSizeControl {
            draft.imageSize = nil
        } else if let size = draft.imageSize, !supportedCurrentModelImageSizes.contains(size) {
            draft.imageSize = nil
        }

        if let ratio = draft.aspectRatio, !supportedCurrentModelImageAspectRatios.contains(ratio) {
            draft.aspectRatio = nil
        }

        if providerType != .vertexai {
            draft.vertexPersonGeneration = nil
            draft.vertexOutputMIMEType = nil
            draft.vertexCompressionQuality = nil
        }

        if draft.isEmpty {
            controls.imageGeneration = nil
        } else {
            controls.imageGeneration = draft
        }

        persistControlsToConversation()
        imageGenerationDraftError = nil
        return true
    }

    private func openContextCacheEditor() {
        let defaultMode: ContextCacheMode = (providerType == .anthropic) ? .implicit : .off
        contextCacheDraft = controls.contextCache ?? ContextCacheControls(mode: defaultMode)
        contextCacheTTLPreset = ContextCacheTTLPreset.from(ttl: contextCacheDraft.ttl)
        if case .customSeconds(let seconds) = contextCacheDraft.ttl {
            contextCacheCustomTTLDraft = "\(seconds)"
        } else {
            contextCacheCustomTTLDraft = ""
        }
        contextCacheMinTokensDraft = contextCacheDraft.minTokensThreshold.map(String.init) ?? ""
        contextCacheAdvancedExpanded = shouldExpandContextCacheAdvancedOptions(for: contextCacheDraft)
        contextCacheDraftError = nil
        showingContextCacheSheet = true
    }

    // MARK: - Anthropic Web Search Helpers

    private var supportsAnthropicDynamicFiltering: Bool {
        ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(
            for: providerType,
            modelID: conversationEntity.modelID
        )
    }

    private func normalizeAnthropicDomainFilters() {
        let allowed = AnthropicWebSearchDomainUtils.normalizedDomains(controls.webSearch?.allowedDomains)
        let blocked = AnthropicWebSearchDomainUtils.normalizedDomains(controls.webSearch?.blockedDomains)

        if !allowed.isEmpty {
            controls.webSearch?.allowedDomains = allowed
            controls.webSearch?.blockedDomains = nil
        } else if !blocked.isEmpty {
            controls.webSearch?.allowedDomains = nil
            controls.webSearch?.blockedDomains = blocked
        } else {
            controls.webSearch?.allowedDomains = nil
            controls.webSearch?.blockedDomains = nil
        }
    }

    private func openAnthropicWebSearchEditor() {
        let ws = controls.webSearch
        let allowed = AnthropicWebSearchDomainUtils.normalizedDomains(ws?.allowedDomains)
        let blocked = AnthropicWebSearchDomainUtils.normalizedDomains(ws?.blockedDomains)

        anthropicWebSearchAllowedDomainsDraft = allowed.joined(separator: "\n")
        anthropicWebSearchBlockedDomainsDraft = blocked.joined(separator: "\n")

        if anthropicWebSearchDomainMode == .blocked, !blocked.isEmpty {
            anthropicWebSearchDomainMode = .blocked
        } else if !allowed.isEmpty {
            anthropicWebSearchDomainMode = .allowed
        } else if !blocked.isEmpty {
            anthropicWebSearchDomainMode = .blocked
        } else {
            anthropicWebSearchDomainMode = .none
        }
        anthropicWebSearchLocationDraft = ws?.userLocation ?? WebSearchUserLocation()
        anthropicWebSearchDraftError = nil
        showingAnthropicWebSearchSheet = true
    }

    private func applyAnthropicWebSearchDraft() {
        let allowedDomains = AnthropicWebSearchDomainUtils.normalizedDomains(
            AnthropicWebSearchDomainUtils.splitInput(anthropicWebSearchAllowedDomainsDraft)
        )
        let blockedDomains = AnthropicWebSearchDomainUtils.normalizedDomains(
            AnthropicWebSearchDomainUtils.splitInput(anthropicWebSearchBlockedDomainsDraft)
        )

        switch anthropicWebSearchDomainMode {
        case .none:
            anthropicWebSearchDraftError = nil
            controls.webSearch?.allowedDomains = nil
            controls.webSearch?.blockedDomains = nil
        case .allowed:
            if allowedDomains.isEmpty {
                anthropicWebSearchDraftError = nil
                controls.webSearch?.allowedDomains = nil
                controls.webSearch?.blockedDomains = nil
            } else {
                if let validationError = AnthropicWebSearchDomainUtils.firstValidationError(in: allowedDomains) {
                    anthropicWebSearchDraftError = validationError
                    return
                }
                anthropicWebSearchDraftError = nil
                controls.webSearch?.allowedDomains = allowedDomains
                controls.webSearch?.blockedDomains = nil
            }
        case .blocked:
            if blockedDomains.isEmpty {
                anthropicWebSearchDraftError = nil
                controls.webSearch?.allowedDomains = nil
                controls.webSearch?.blockedDomains = nil
            } else {
                if let validationError = AnthropicWebSearchDomainUtils.firstValidationError(in: blockedDomains) {
                    anthropicWebSearchDraftError = validationError
                    return
                }
                anthropicWebSearchDraftError = nil
                controls.webSearch?.allowedDomains = nil
                controls.webSearch?.blockedDomains = blockedDomains
            }
        }
        normalizeAnthropicDomainFilters()

        let loc = anthropicWebSearchLocationDraft
        controls.webSearch?.userLocation = loc.isEmpty ? nil : loc

        persistControlsToConversation()
        showingAnthropicWebSearchSheet = false
    }

    private func shouldExpandContextCacheAdvancedOptions(for draft: ContextCacheControls) -> Bool {
        guard draft.mode != .off else { return false }

        if supportsContextCacheTTL,
           let ttl = draft.ttl,
           ttl != .providerDefault {
            return true
        }

        if providerType == .xai {
            if let cacheKey = draft.cacheKey?.trimmingCharacters(in: .whitespacesAndNewlines),
               !cacheKey.isEmpty {
                return true
            }
        }

        if providerType == .xai,
           let conversationID = draft.conversationID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !conversationID.isEmpty {
            return true
        }

        return false
    }

    private var isContextCacheDraftValid: Bool {
        if contextCacheTTLPreset == .custom {
            let trimmed = contextCacheCustomTTLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Int(trimmed), value > 0 else { return false }
        }

        let minTokensTrimmed = contextCacheMinTokensDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !minTokensTrimmed.isEmpty {
            guard let value = Int(minTokensTrimmed), value > 0 else { return false }
        }

        if supportsExplicitContextCacheMode, contextCacheDraft.mode == .explicit {
            let name = (contextCacheDraft.cachedContentName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty
        }

        return true
    }

    @discardableResult
    private func applyContextCacheDraft() -> Bool {
        var draft = contextCacheDraft

        if supportsContextCacheTTL {
            switch contextCacheTTLPreset {
            case .providerDefault:
                draft.ttl = .providerDefault
            case .minutes5:
                draft.ttl = .minutes5
            case .hour1:
                draft.ttl = .hour1
            case .custom:
                let trimmed = contextCacheCustomTTLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let value = Int(trimmed), value > 0 else {
                    contextCacheDraftError = "Custom TTL must be a positive integer (seconds)."
                    return false
                }
                draft.ttl = .customSeconds(value)
            }
        } else {
            draft.ttl = nil
        }

        let minTokensTrimmed = contextCacheMinTokensDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if minTokensTrimmed.isEmpty {
            draft.minTokensThreshold = nil
        } else if let value = Int(minTokensTrimmed), value > 0 {
            draft.minTokensThreshold = value
        } else {
            contextCacheDraftError = "Min tokens threshold must be a positive integer."
            return false
        }

        draft.cacheKey = draft.cacheKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.cacheKey?.isEmpty == true {
            draft.cacheKey = nil
        }

        draft.conversationID = draft.conversationID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.conversationID?.isEmpty == true {
            draft.conversationID = nil
        }

        draft.cachedContentName = draft.cachedContentName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.cachedContentName?.isEmpty == true {
            draft.cachedContentName = nil
        }

        if !supportsContextCacheStrategy {
            draft.strategy = nil
        } else if draft.strategy == nil {
            draft.strategy = .systemOnly
        }

        if !supportsExplicitContextCacheMode, draft.mode == .explicit {
            draft.mode = .implicit
        }

        if providerType != .openai && providerType != .openaiWebSocket && providerType != .xai {
            draft.cacheKey = nil
        }
        if providerType != .xai {
            draft.minTokensThreshold = nil
        }
        if providerType != .xai {
            draft.conversationID = nil
        }
        if providerType != .gemini && providerType != .vertexai {
            draft.cachedContentName = nil
        }

        if draft.mode == .off {
            if providerType == .anthropic {
                controls.contextCache = ContextCacheControls(mode: .off)
            } else {
                controls.contextCache = nil
            }
        } else {
            controls.contextCache = draft
        }

        normalizeControlsForCurrentSelection()
        persistControlsToConversation()
        contextCacheDraftError = nil
        return true
    }

    private func mcpServerSelectionBinding(serverID: String) -> Binding<Bool> {
        Binding(
            get: {
                selectedMCPServerIDs.contains(serverID)
            },
            set: { isOn in
                if controls.mcpTools == nil {
                    controls.mcpTools = MCPToolsControls(enabled: true, enabledServerIDs: nil)
                }

                let eligibleIDs = Set(eligibleMCPServers.map(\.id))
                var selected = Set(controls.mcpTools?.enabledServerIDs ?? Array(eligibleIDs))
                if isOn {
                    selected.insert(serverID)
                } else {
                    selected.remove(serverID)
                }

                let normalized = selected.intersection(eligibleIDs)
                if normalized == eligibleIDs {
                    controls.mcpTools?.enabledServerIDs = nil
                } else {
                    controls.mcpTools?.enabledServerIDs = Array(normalized).sorted()
                }

                persistControlsToConversation()
            }
        )
    }

    private func resetMCPServerSelection() {
        if controls.mcpTools == nil {
            controls.mcpTools = MCPToolsControls(enabled: true, enabledServerIDs: nil)
        } else {
            controls.mcpTools?.enabled = true
            controls.mcpTools?.enabledServerIDs = nil
        }
        persistControlsToConversation()
    }

    private func resolvedMCPServerConfigs(for controlsToUse: GenerationControls) throws -> [MCPServerConfig] {
        guard supportsMCPToolsControl else { return [] }
        guard controlsToUse.mcpTools?.enabled == true else { return [] }

        let eligibleServers = mcpServers
            .filter { $0.isEnabled && $0.runToolsAutomatically }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let eligibleIDs = Set(eligibleServers.map(\.id))
        let allowlist = controlsToUse.mcpTools?.enabledServerIDs
        let selectedIDs = allowlist.map(Set.init) ?? eligibleIDs
        let resolvedIDs = selectedIDs.intersection(eligibleIDs)

        return try eligibleServers
            .filter { resolvedIDs.contains($0.id) }
            .map { try $0.toConfig() }
    }

    private func ensureModelThreadsInitializedIfNeeded() {
        var didMutate = false

        if conversationEntity.modelThreads.isEmpty {
            let controlsData = conversationEntity.modelConfigData
            let thread = ConversationModelThreadEntity(
                providerID: conversationEntity.providerID,
                modelID: conversationEntity.modelID,
                modelConfigData: controlsData,
                displayOrder: 0,
                isSelected: true,
                isPrimary: true
            )
            thread.conversation = conversationEntity
            conversationEntity.modelThreads.append(thread)
            conversationEntity.activeThreadID = thread.id
            activeThreadID = thread.id
            didMutate = true
        }

        guard let fallbackThread = activeModelThread ?? sortedModelThreads.first else { return }
        for message in conversationEntity.messages where message.contextThreadID == nil {
            message.contextThreadID = fallbackThread.id
            didMutate = true
        }

        if let currentActive = conversationEntity.activeThreadID,
           !sortedModelThreads.contains(where: { $0.id == currentActive }) {
            conversationEntity.activeThreadID = fallbackThread.id
            didMutate = true
        }

        if sortedModelThreads.filter(\.isSelected).isEmpty,
           let first = sortedModelThreads.first {
            first.isSelected = true
            didMutate = true
        }

        if didMutate {
            try? modelContext.save()
        }
    }

    private func syncActiveThreadSelection() {
        if let current = activeModelThread {
            synchronizeLegacyConversationModelFields(with: current)
            return
        }

        if let first = sortedModelThreads.first {
            synchronizeLegacyConversationModelFields(with: first)
        }
    }

    private func loadControlsFromConversation() {
        ensureModelThreadsInitializedIfNeeded()
        syncActiveThreadSelection()

        if let activeThread = activeModelThread {
            canonicalizeThreadModelIDIfNeeded(activeThread)
        }

        let controlsData = activeModelThread?.modelConfigData ?? conversationEntity.modelConfigData
        if let decoded = try? JSONDecoder().decode(GenerationControls.self, from: controlsData) {
            controls = decoded
        } else {
            controls = GenerationControls()
        }

        normalizeControlsForCurrentSelection()
    }

    private func refreshExtensionCredentialsStatus() async {
        let defaults = UserDefaults.standard

        func hasStoredKey(_ key: String) -> Bool {
            let trimmed = (defaults.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty
        }

        let mistralConfigured = hasStoredKey(AppPreferenceKeys.pluginMistralOCRAPIKey)
        let deepSeekConfigured = hasStoredKey(AppPreferenceKeys.pluginDeepSeekOCRAPIKey)

        let ttsProvider = try? SpeechPluginConfigFactory.currentTTSProvider(defaults: defaults)
        let sttProvider = try? SpeechPluginConfigFactory.currentSTTProvider(defaults: defaults)

        let ttsKeyConfigured = {
            guard let ttsProvider else { return false }
            let key: String
            switch ttsProvider {
            case .elevenlabs:
                key = AppPreferenceKeys.ttsElevenLabsAPIKey
            case .openai:
                key = AppPreferenceKeys.ttsOpenAIAPIKey
            case .groq:
                key = AppPreferenceKeys.ttsGroqAPIKey
            }
            return hasStoredKey(key)
        }()

        let sttKeyConfigured = {
            guard let sttProvider else { return false }
            let key: String
            switch sttProvider {
            case .openai:
                key = AppPreferenceKeys.sttOpenAIAPIKey
            case .groq:
                key = AppPreferenceKeys.sttGroqAPIKey
            case .mistral:
                key = AppPreferenceKeys.sttMistralAPIKey
            }
            return hasStoredKey(key)
        }()

        let ttsConfigured: Bool
        if ttsProvider == .elevenlabs {
            let voiceID = (defaults.string(forKey: AppPreferenceKeys.ttsElevenLabsVoiceID) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ttsConfigured = ttsKeyConfigured && !voiceID.isEmpty
        } else {
            ttsConfigured = ttsKeyConfigured
        }

        let mistralEnabled = AppPreferences.isPluginEnabled("mistral_ocr", defaults: defaults)
        let deepSeekEnabled = AppPreferences.isPluginEnabled("deepseek_ocr", defaults: defaults)
        let ttsEnabled = AppPreferences.isPluginEnabled("text_to_speech", defaults: defaults)
        let sttEnabled = AppPreferences.isPluginEnabled("speech_to_text", defaults: defaults)
        let webSearchSettings = WebSearchPluginSettingsStore.load(defaults: defaults)
        let webSearchEnabled = webSearchSettings.isEnabled
        let webSearchConfigured = SearchPluginProvider.allCases.contains {
            webSearchSettings.hasConfiguredCredential(for: $0)
        }

        await MainActor.run {
            mistralOCRConfigured = mistralConfigured
            deepSeekOCRConfigured = deepSeekConfigured
            textToSpeechConfigured = ttsConfigured
            speechToTextConfigured = sttKeyConfigured
            webSearchPluginConfigured = webSearchConfigured

            mistralOCRPluginEnabled = mistralEnabled
            deepSeekOCRPluginEnabled = deepSeekEnabled
            textToSpeechPluginEnabled = ttsEnabled
            speechToTextPluginEnabled = sttEnabled
            webSearchPluginEnabled = webSearchEnabled

            if !ttsEnabled {
                ttsPlaybackManager.stop()
            }
            if !sttEnabled {
                speechToTextManager.cancelAndCleanup()
            }
        }
    }

    private func currentSpeechToTextTranscriptionConfig() async throws -> SpeechToTextManager.TranscriptionConfig {
        try SpeechPluginConfigFactory.speechToTextConfig()
    }

    private func toggleSpeakAssistantMessage(_ messageEntity: MessageEntity, text: String) {
        Task { @MainActor in
            guard textToSpeechPluginEnabled else { return }

            let provider = try? SpeechPluginConfigFactory.currentTTSProvider()

            do {
                let config = try SpeechPluginConfigFactory.textToSpeechConfig()
                let context = TextToSpeechPlaybackManager.PlaybackContext(
                    conversationID: conversationEntity.id,
                    conversationTitle: conversationEntity.title,
                    textPreview: String(text.prefix(80))
                )
                ttsPlaybackManager.toggleSpeak(
                    messageID: messageEntity.id,
                    text: text,
                    config: config,
                    context: context,
                    onError: { error in
                        errorMessage = SpeechPluginConfigFactory.textToSpeechErrorMessage(error, provider: provider)
                        showingError = true
                    }
                )
            } catch {
                errorMessage = SpeechPluginConfigFactory.textToSpeechErrorMessage(error, provider: provider)
                showingError = true
            }
        }
    }

    private func stopSpeakAssistantMessage(_ messageEntity: MessageEntity) {
        ttsPlaybackManager.stop(messageID: messageEntity.id)
    }

    private func persistControlsToConversation() {
        do {
            var persistedControls = controls
            if let activeThread = activeModelThread,
               let storedControls = storedGenerationControls(for: activeThread) {
                persistedControls.codexResumeThreadID = storedControls.codexResumeThreadID
                persistedControls.codexPendingRollbackTurns = storedControls.codexPendingRollbackTurns
            }

            let data = try JSONEncoder().encode(persistedControls)
            if let activeThread = activeModelThread {
                activeThread.modelConfigData = data
                activeThread.updatedAt = Date()
                conversationEntity.modelConfigData = data
            } else {
                conversationEntity.modelConfigData = data
            }
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func setReasoningOff() {
        if reasoningMustRemainEnabled {
            updateReasoning { reasoning in
                reasoning.enabled = true
                if selectedReasoningConfig?.type == .effort,
                   (reasoning.effort == nil || reasoning.effort == ReasoningEffort.none) {
                    reasoning.effort = selectedReasoningConfig?.defaultEffort ?? .medium
                }
            }
            persistControlsToConversation()
            return
        }

        updateReasoning { reasoning in
            reasoning.enabled = false
        }
        if providerType == .anthropic {
            normalizeAnthropicReasoningAndMaxTokens()
        }
        persistControlsToConversation()
    }

    private func setReasoningOn() {
        updateReasoning { reasoning in
            reasoning.enabled = true
        }
        if providerType == .anthropic {
            normalizeAnthropicReasoningAndMaxTokens()
        }
        persistControlsToConversation()
    }

    private func setReasoningEffort(_ effort: ReasoningEffort) {
        guard providerType != .anthropic else {
            openThinkingBudgetEditor()
            return
        }

        updateReasoning { reasoning in
            reasoning.enabled = true
            reasoning.effort = effort
            reasoning.budgetTokens = nil
            if supportsReasoningSummaryControl, reasoning.summary == nil {
                reasoning.summary = .auto
            }
        }
        persistControlsToConversation()
    }

    private func setAnthropicThinkingBudget(_ budgetTokens: Int) {
        updateReasoning { reasoning in
            reasoning.enabled = true
            reasoning.effort = nil
            reasoning.budgetTokens = budgetTokens
            reasoning.summary = nil
        }
        normalizeAnthropicReasoningAndMaxTokens()
        persistControlsToConversation()
    }

    private var thinkingBudgetDraftInt: Int? {
        Int(thinkingBudgetDraft.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var anthropicUsesAdaptiveThinking: Bool {
        guard providerType == .anthropic else { return false }
        return AnthropicModelLimits.supportsAdaptiveThinking(for: conversationEntity.modelID)
    }

    private var anthropicUsesEffortMode: Bool {
        guard providerType == .anthropic else { return false }
        return AnthropicModelLimits.supportsEffort(for: conversationEntity.modelID)
    }

    private var anthropicEffortBinding: Binding<ReasoningEffort> {
        Binding(
            get: {
                let value = controls.reasoning?.effort ?? selectedReasoningConfig?.defaultEffort ?? .high
                switch value {
                case .none, .minimal:
                    return .low
                case .low, .medium, .high, .xhigh:
                    return value
                }
            },
            set: { newValue in
                updateReasoning { reasoning in
                    reasoning.enabled = true
                    reasoning.effort = newValue
                    reasoning.summary = nil
                    // Only clear budgetTokens for adaptive-only (4.6) models.
                    // Opus 4.5/4.1 use effort + budget_tokens together.
                    if anthropicUsesAdaptiveThinking {
                        reasoning.budgetTokens = nil
                    }
                }
                normalizeAnthropicReasoningAndMaxTokens()
                persistControlsToConversation()
            }
        )
    }

    private var anthropicDefaultBudgetTokens: Int {
        selectedReasoningConfig?.defaultBudget ?? 1024
    }

    private var maxTokensDraftInt: Int? {
        let trimmed = maxTokensDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    private var isThinkingBudgetDraftValid: Bool {
        if !anthropicUsesAdaptiveThinking {
            guard let budget = thinkingBudgetDraftInt, budget > 0 else { return false }
        }
        guard providerType == .anthropic else { return true }
        guard let maxTokens = maxTokensDraftInt else { return false }
        if let modelMax = AnthropicModelLimits.maxOutputTokens(for: conversationEntity.modelID), maxTokens > modelMax {
            return false
        }
        return true
    }

    private var thinkingBudgetValidationWarning: String? {
        guard providerType == .anthropic else { return nil }
        if !anthropicUsesAdaptiveThinking {
            guard let budget = thinkingBudgetDraftInt else { return "Enter an integer token budget (e.g., 4096)." }

            if budget <= 0 {
                return "Thinking budget must be a positive integer."
            }

            if let maxTokens = maxTokensDraftInt, maxTokens > 0, budget >= maxTokens {
                return "Recommended: keep budget tokens below max output tokens."
            }
        }

        if maxTokensDraftInt == nil {
            return "Enter a valid positive max output token value."
        }

        if let modelMax = AnthropicModelLimits.maxOutputTokens(for: conversationEntity.modelID),
           let maxTokens = maxTokensDraftInt,
           maxTokens > modelMax {
            return "This model allows at most \(modelMax) max output tokens."
        }

        return nil
    }

    private func openThinkingBudgetEditor() {
        if anthropicUsesAdaptiveThinking {
            thinkingBudgetDraft = ""
        } else {
            let budget = controls.reasoning?.budgetTokens
                ?? selectedReasoningConfig?.defaultBudget
                ?? anthropicDefaultBudgetTokens
            thinkingBudgetDraft = "\(budget)"
        }

        if providerType == .anthropic {
            let resolvedMax = AnthropicModelLimits.resolvedMaxTokens(
                requested: controls.maxTokens,
                for: conversationEntity.modelID,
                fallback: 4096
            )
            maxTokensDraft = "\(resolvedMax)"
        } else {
            maxTokensDraft = controls.maxTokens.map(String.init) ?? ""
        }

        showingThinkingBudgetSheet = true
    }

    private func applyThinkingBudgetDraft() {
        guard providerType != .anthropic || maxTokensDraftInt != nil else { return }

        controls.maxTokens = maxTokensDraftInt

        if anthropicUsesAdaptiveThinking {
            normalizeAnthropicReasoningAndMaxTokens()
        } else if anthropicUsesEffortMode {
            // Opus 4.5/4.1: apply budget_tokens while preserving the user's effort selection.
            // Do NOT call setAnthropicThinkingBudget here — it clears effort.
            guard let budgetTokens = thinkingBudgetDraftInt else { return }
            updateReasoning { reasoning in
                reasoning.enabled = true
                reasoning.budgetTokens = budgetTokens
            }
            normalizeAnthropicReasoningAndMaxTokens()
        } else {
            guard let budgetTokens = thinkingBudgetDraftInt else { return }
            setAnthropicThinkingBudget(budgetTokens)
        }

        if providerType == .anthropic {
            let resolvedMax = AnthropicModelLimits.resolvedMaxTokens(
                requested: controls.maxTokens,
                for: conversationEntity.modelID,
                fallback: 4096
            )
            maxTokensDraft = "\(resolvedMax)"
        }

        persistControlsToConversation()
    }

    private func normalizeAnthropicReasoningAndMaxTokens() {
        guard providerType == .anthropic else { return }
        guard var reasoning = controls.reasoning else { return }

        var maxTokens = controls.maxTokens
        AnthropicReasoningNormalizer.normalize(
            reasoning: &reasoning,
            maxTokens: &maxTokens,
            modelID: conversationEntity.modelID,
            defaults: .init(
                effort: selectedReasoningConfig?.defaultEffort ?? .high,
                budgetTokens: anthropicDefaultBudgetTokens
            )
        )
        controls.reasoning = reasoning
        controls.maxTokens = maxTokens
    }

    private func setReasoningSummary(_ summary: ReasoningSummary) {
        updateReasoning { reasoning in
            reasoning.enabled = true
            reasoning.summary = summary
            if supportsReasoningSummaryControl,
               (reasoning.effort ?? ReasoningEffort.none) == ReasoningEffort.none {
                reasoning.effort = selectedReasoningConfig?.defaultEffort ?? .medium
            }
        }
        persistControlsToConversation()
    }

    private func updateReasoning(_ mutate: (inout ReasoningControls) -> Void) {
        var reasoning = controls.reasoning ?? ReasoningControls(enabled: false)
        mutate(&reasoning)
        controls.reasoning = reasoning
    }

    private func defaultWebSearchControls(enabled: Bool) -> WebSearchControls {
        ChatControlNormalizationSupport.defaultWebSearchControls(
            enabled: enabled,
            providerType: providerType
        )
    }

    private func ensureValidWebSearchDefaultsIfEnabled() {
        ChatControlNormalizationSupport.ensureValidWebSearchDefaultsIfEnabled(
            controls: &controls,
            providerType: providerType
        )
    }

    private func normalizeControlsForCurrentSelection() {

        let originalData = (try? JSONEncoder().encode(controls)) ?? Data()

        normalizeMaxTokensForModel()
        normalizeMediaGenerationOverrides()
        normalizeReasoningControls()
        normalizeReasoningEffortLimits()
        normalizeVertexAIGenerationConfig()
        normalizeFireworksProviderSpecific()
        normalizeCodexProviderSpecific()
        normalizeOpenAIServiceTierControls()
        normalizeWebSearchControls()
        normalizeSearchPluginControls()
        normalizeContextCacheControls()
        normalizeMCPToolsControls()
        normalizeAnthropicMaxTokens()
        normalizeImageGenerationControls()
        normalizeVideoGenerationControls()

        let newData = (try? JSONEncoder().encode(controls)) ?? Data()
        if newData != originalData {
            persistControlsToConversation()
        }
    }

    private func normalizeMaxTokensForModel() {
        ChatControlNormalizationSupport.normalizeMaxTokensForModel(
            controls: &controls,
            modelMaxOutputTokens: resolvedModelSettings?.maxOutputTokens
        )
    }

    private func normalizeMediaGenerationOverrides() {
        ChatControlNormalizationSupport.normalizeMediaGenerationOverrides(
            controls: &controls,
            supportsMediaGenerationControl: supportsMediaGenerationControl,
            supportsReasoningControl: supportsReasoningControl,
            supportsWebSearchControl: supportsWebSearchControl
        )
    }

    private func normalizeReasoningControls() {

        if supportsReasoningControl, let reasoningConfig = selectedReasoningConfig {
            switch reasoningConfig.type {
            case .effort:
                normalizeEffortBasedReasoning(config: reasoningConfig)
            case .budget:
                normalizeBudgetBasedReasoning(config: reasoningConfig)
            case .toggle:
                normalizeToggleBasedReasoning()
            case .none:
                controls.reasoning = nil
            }
        } else if !supportsReasoningControl {
            controls.reasoning = nil
        }

        enforceReasoningAlwaysOnIfRequired()
    }

    private func normalizeEffortBasedReasoning(config: ModelReasoningConfig) {
        if providerType != .anthropic,
           controls.reasoning?.enabled == true,
           controls.reasoning?.effort == nil {
            updateReasoning { $0.effort = config.defaultEffort ?? .medium }
        }

        if providerType != .anthropic {
            controls.reasoning?.budgetTokens = nil
        }
        if supportsReasoningSummaryControl,
           controls.reasoning?.enabled == true,
           (controls.reasoning?.effort ?? ReasoningEffort.none) != ReasoningEffort.none,
           controls.reasoning?.summary == nil {
            controls.reasoning?.summary = .auto
        }
        if providerType == .anthropic {
            normalizeAnthropicReasoningAndMaxTokens()
        }
    }

    private func normalizeBudgetBasedReasoning(config: ModelReasoningConfig) {
        if controls.reasoning?.enabled == true, controls.reasoning?.budgetTokens == nil {
            updateReasoning { $0.budgetTokens = config.defaultBudget ?? 2048 }
        }
        controls.reasoning?.effort = nil
        controls.reasoning?.summary = nil
    }

    private func normalizeToggleBasedReasoning() {
        if controls.reasoning == nil {
            controls.reasoning = ReasoningControls(enabled: true)
        }
        controls.reasoning?.effort = nil
        controls.reasoning?.budgetTokens = nil
        controls.reasoning?.summary = nil
    }

    private func enforceReasoningAlwaysOnIfRequired() {
        guard reasoningMustRemainEnabled else { return }
        if controls.reasoning == nil {
            controls.reasoning = ReasoningControls(enabled: true)
        } else {
            controls.reasoning?.enabled = true
        }

        if selectedReasoningConfig?.type == .effort,
           controls.reasoning?.effort == nil || controls.reasoning?.effort == ReasoningEffort.none {
            controls.reasoning?.effort = selectedReasoningConfig?.defaultEffort ?? .medium
        }
    }

    private func normalizeReasoningEffortLimits() {
        guard supportsReasoningControl else { return }

        if let effort = controls.reasoning?.effort {
            controls.reasoning?.effort = ModelCapabilityRegistry.normalizedReasoningEffort(
                effort,
                for: providerType,
                modelID: conversationEntity.modelID
            )
        }

        if providerType == .anthropic {
            normalizeAnthropicReasoningAndMaxTokens()
        }
    }

    private func normalizeVertexAIGenerationConfig() {
        ChatControlNormalizationSupport.normalizeVertexAIGenerationConfig(
            controls: &controls,
            providerType: providerType,
            lowerModelID: lowerModelID,
            vertexGemini25TextModelIDs: Self.vertexGemini25TextModelIDs
        )
    }

    private func normalizeFireworksProviderSpecific() {
        ChatControlNormalizationSupport.normalizeFireworksProviderSpecific(
            controls: &controls,
            providerType: providerType,
            conversationModelID: conversationEntity.modelID,
            fireworksReasoningHistoryOptions: fireworksReasoningHistoryOptions
        )
    }

    private func normalizeCodexProviderSpecific() {
        ChatControlNormalizationSupport.normalizeCodexProviderSpecific(
            controls: &controls,
            providerType: providerType
        )
    }

    private func normalizeOpenAIServiceTierControls() {
        ChatControlNormalizationSupport.normalizeOpenAIServiceTierControls(
            controls: &controls
        )
    }

    nonisolated private static func sanitizeProviderSpecificForProvider(_ providerType: ProviderType?, controls: inout GenerationControls) {
        ChatControlNormalizationSupport.sanitizeProviderSpecificForProvider(
            providerType,
            controls: &controls
        )
    }

    private func normalizeWebSearchControls() {
        if modelSupportsWebSearchControl {
            if controls.webSearch?.enabled == true {
                ensureValidWebSearchDefaultsIfEnabled()
            }
        } else {
            controls.webSearch = nil
        }
    }

    private func normalizeSearchPluginControls() {
        ChatControlNormalizationSupport.normalizeSearchPluginControls(
            controls: &controls,
            modelSupportsBuiltinSearchPluginControl: modelSupportsBuiltinSearchPluginControl
        )
    }

    private func normalizeContextCacheControls() {
        ChatControlNormalizationSupport.normalizeContextCacheControls(
            controls: &controls,
            supportsContextCacheControl: supportsContextCacheControl,
            supportsExplicitContextCacheMode: supportsExplicitContextCacheMode,
            supportsContextCacheStrategy: supportsContextCacheStrategy,
            supportsContextCacheTTL: supportsContextCacheTTL,
            providerType: providerType
        )
    }

    private func normalizeMCPToolsControls() {
        ChatControlNormalizationSupport.normalizeMCPToolsControls(
            controls: &controls,
            supportsMCPToolsControl: supportsMCPToolsControl
        )
    }

    private func normalizeAnthropicMaxTokens() {
        ChatControlNormalizationSupport.normalizeAnthropicMaxTokens(
            controls: &controls,
            supportsReasoningControl: supportsReasoningControl,
            providerType: providerType
        )
    }

    private func normalizeImageGenerationControls() {
        ChatControlNormalizationSupport.normalizeImageGenerationControls(
            controls: &controls,
            supportsImageGenerationControl: supportsImageGenerationControl,
            providerType: providerType,
            supportsCurrentModelImageSizeControl: supportsCurrentModelImageSizeControl,
            supportedCurrentModelImageSizes: supportedCurrentModelImageSizes,
            supportedCurrentModelImageAspectRatios: supportedCurrentModelImageAspectRatios,
            lowerModelID: lowerModelID
        )
    }

    private func normalizeOpenAIImageControls(_ controls: inout OpenAIImageGenerationControls) {
        ChatControlNormalizationSupport.normalizeOpenAIImageControls(
            &controls,
            lowerModelID: lowerModelID
        )
    }

    private func normalizeVideoGenerationControls() {
        ChatControlNormalizationSupport.normalizeVideoGenerationControls(
            controls: &controls,
            supportsVideoGenerationControl: supportsVideoGenerationControl
        )
    }

    private var builtinSearchIncludeRawBinding: Binding<Bool> {

        Binding(
            get: {
                controls.searchPlugin?.includeRawContent ?? false
            },
            set: { newValue in
                if controls.searchPlugin == nil {
                    controls.searchPlugin = SearchPluginControls()
                }
                controls.searchPlugin?.includeRawContent = newValue ? true : nil
                persistControlsToConversation()
            }
        )
    }

    private var builtinSearchFetchPageBinding: Binding<Bool> {
        Binding(
            get: {
                let settings = WebSearchPluginSettingsStore.load()
                return controls.searchPlugin?.fetchPageContent ?? settings.jinaReadPages
            },
            set: { newValue in
                if controls.searchPlugin == nil {
                    controls.searchPlugin = SearchPluginControls()
                }
                controls.searchPlugin?.fetchPageContent = newValue
                persistControlsToConversation()
            }
        )
    }

    private var builtinSearchFirecrawlExtractBinding: Binding<Bool> {
        Binding(
            get: {
                let settings = WebSearchPluginSettingsStore.load()
                return controls.searchPlugin?.firecrawlExtractContent ?? settings.firecrawlExtractContent
            },
            set: { newValue in
                if controls.searchPlugin == nil {
                    controls.searchPlugin = SearchPluginControls()
                }
                controls.searchPlugin?.firecrawlExtractContent = newValue
                persistControlsToConversation()
            }
        )
    }


    private func webSearchSourceBinding(_ source: WebSearchSource) -> Binding<Bool> {
        Binding(
            get: {
                Set(controls.webSearch?.sources ?? []).contains(source)
            },
            set: { isOn in
                var set = Set(controls.webSearch?.sources ?? [])
                if isOn {
                    set.insert(source)
                } else {
                    set.remove(source)
                }
                controls.webSearch?.sources = Array(set).sorted { $0.rawValue < $1.rawValue }
                persistControlsToConversation()
            }
        )
    }
}
