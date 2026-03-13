import Collections
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
    static let asyncCacheBuildMessageThreshold = 80

    private enum PrepareToSendCancellationReason {
        case userCancelled
        case conversationSwitch
    }

    struct PendingCodexInteraction: Identifiable {
        let localThreadID: UUID
        let request: CodexInteractionRequest

        var id: UUID { request.id }
    }

    struct PendingAgentApproval: Identifiable {
        let localThreadID: UUID
        let request: AgentApprovalRequest

        var id: UUID { request.id }
    }

    private var activeAgentApprovalBinding: Binding<PendingAgentApproval?> {
        Binding(
            get: { pendingAgentApprovals.first },
            set: { newValue in
                guard newValue == nil, !pendingAgentApprovals.isEmpty else { return }
                _ = pendingAgentApprovals.popFirst()
            }
        )
    }

    private var activeCodexInteractionBinding: Binding<PendingCodexInteraction?> {
        Binding(
            get: { pendingCodexInteractions.first },
            set: { newValue in
                guard newValue == nil, !pendingCodexInteractions.isEmpty else { return }
                _ = pendingCodexInteractions.popFirst()
            }
        )
    }

    @Environment(\.modelContext) var modelContext
    @EnvironmentObject private var streamingStore: ConversationStreamingStore
    @EnvironmentObject private var responseCompletionNotifier: ResponseCompletionNotifier
    @EnvironmentObject private var shortcutsStore: AppShortcutsStore
    @Bindable var conversationEntity: ConversationEntity
    let onRequestDeleteConversation: () -> Void
    @Binding var isAssistantInspectorPresented: Bool
    var onPersistConversationIfNeeded: () -> Void = {}
    var isSidebarHidden: Bool = false
    var onToggleSidebar: (() -> Void)? = nil
    var onNewChat: (() -> Void)? = nil
    @Query var providers: [ProviderConfigEntity]
    @Query var mcpServers: [MCPServerConfigEntity]

    @AppStorage(AppPreferenceKeys.sendWithCommandEnter) private var sendWithCommandEnter = false
    @AppStorage(AppPreferenceKeys.sttAddRecordingAsFile) private var sttAddRecordingAsFile = false

    @State var controls: GenerationControls = GenerationControls()
    @State private var messageText = ""
    @State private var remoteVideoInputURLText = ""
    @State private var draftAttachments: [DraftAttachment] = []
    @State private var isFileImporterPresented = false
    @State private var isComposerDropTargeted = false
    @State private var isFullPageDropTargeted = false
    @State private var dropAttachmentImportInFlightCount = 0
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
    @State var activeThreadID: UUID?

    // Cache expensive derived data so typing/streaming doesn't repeatedly sort/decode the entire history.
    @State private var cachedVisibleMessages: [MessageRenderItem] = []
    @State private var cachedMessagesVersion: Int = 0
    @State private var cachedMessageEntitiesByID: [UUID: MessageEntity] = [:]
    @State private var cachedToolResultsByCallID: [String: ToolResult] = [:]
    @State private var cachedArtifactCatalog: ArtifactCatalog = .empty
    @State private var lastCacheRebuildMessageCount: Int = 0
    @State private var lastCacheRebuildUpdatedAt: Date = .distantPast
    @State private var updatedAtDebounceTask: Task<Void, Never>?
    @State private var renderContextBuildTask: Task<Void, Never>?
    @State private var renderContextDecodeTask: Task<ChatDecodedRenderContext, Never>?
    @State private var activeRenderContextBuildToken = UUID()
    @State private var isArtifactPaneVisible = false
    @State private var selectedArtifactIDByThreadID: [UUID: String] = [:]
    @State private var selectedArtifactVersionByThreadID: [UUID: Int] = [:]
    @ObservedObject var favoriteModelsStore = FavoriteModelsStore.shared

    @State var errorMessage: String?
    @State var showingError = false
    @State var showingThinkingBudgetSheet = false
    @State var thinkingBudgetDraft = ""
    @State var maxTokensDraft = ""
    @State var showingCodeExecutionSheet = false
    @State var codeExecutionDraft = CodeExecutionControls()
    @State var codeExecutionDraftError: String?
    @State var codeExecutionOpenAIUseExistingContainer = false
    @State var codeExecutionOpenAIFileIDsDraft = ""
    @State var showingCodexSessionSettingsSheet = false
    @State var codexWorkingDirectoryDraft = ""
    @State var codexWorkingDirectoryDraftError: String?
    @State var codexSandboxModeDraft: CodexSandboxMode = .default
    @State var codexPersonalityDraft: CodexPersonality?
    @State var pendingCodexInteractions: Deque<PendingCodexInteraction> = []
    @State var pendingAgentApprovals: Deque<PendingAgentApproval> = []

    private enum SlashCommandTarget { case composer, editMessage }
    @State private var isSlashMCPPopoverVisible = false
    @State private var slashMCPFilterText = ""
    @State private var slashMCPHighlightedIndex = 0
    @State private var slashCommandTarget: SlashCommandTarget = .composer
    @State private var perMessageMCPServerIDs: Set<String> = []

    @State var showingContextCacheSheet = false
    @State var showingAnthropicWebSearchSheet = false
    @State var anthropicWebSearchDomainMode: AnthropicDomainFilterMode = .none
    @State var anthropicWebSearchAllowedDomainsDraft = ""
    @State var anthropicWebSearchBlockedDomainsDraft = ""
    @State var anthropicWebSearchLocationDraft = WebSearchUserLocation()
    @State var anthropicWebSearchDraftError: String?
    @State var contextCacheDraft = ContextCacheControls(mode: .implicit)
    @State var contextCacheTTLPreset = ContextCacheTTLPreset.providerDefault
    @State var contextCacheCustomTTLDraft = ""
    @State var contextCacheMinTokensDraft = ""
    @State var contextCacheDraftError: String?
    @State var contextCacheAdvancedExpanded = false

    @State var showingGoogleMapsSheet = false
    @State var googleMapsDraft = GoogleMapsControls()
    @State var googleMapsLatitudeDraft = ""
    @State var googleMapsLongitudeDraft = ""
    @State var googleMapsLanguageCodeDraft = ""
    @State var googleMapsDraftError: String?

    @State var showingImageGenerationSheet = false
    @State var imageGenerationDraft = ImageGenerationControls()
    @State var imageGenerationSeedDraft = ""
    @State var imageGenerationCompressionQualityDraft = ""
    @State var imageGenerationDraftError: String?
    @State var mistralOCRConfigured = false
    @State var deepSeekOCRConfigured = false
    @State var textToSpeechConfigured = false
    @State var speechToTextConfigured = false
    @State var mistralOCRPluginEnabled = true
    @State var deepSeekOCRPluginEnabled = true
    @State var textToSpeechPluginEnabled = true
    @State var speechToTextPluginEnabled = true
    @State var webSearchPluginEnabled = true
    @State var webSearchPluginConfigured = false
    @State var isAgentModeActive = false
    @State private var isAgentModePopoverPresented = false
    @State private var isPreparingToSend = false
    @State private var prepareToSendStatus: String?
    @State private var prepareToSendTask: Task<Void, Never>?
    @State private var prepareToSendCancellationReason: PrepareToSendCancellationReason?
    @EnvironmentObject var ttsPlaybackManager: TextToSpeechPlaybackManager
    @StateObject var speechToTextManager = SpeechToTextManager()

    private let conversationTitleGenerator = ConversationTitleGenerator()

    private var isStreaming: Bool {
        streamingStore.isStreaming(conversationID: conversationEntity.id)
    }

    private var isBusy: Bool {
        isStreaming || isPreparingToSend
    }

    private var isImportingDropAttachments: Bool {
        dropAttachmentImportInFlightCount > 0
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

    var sortedModelThreads: [ConversationModelThreadEntity] {
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

    var activeModelThread: ConversationModelThreadEntity? {
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
            onSend: sendMessage,
            slashCommandServers: slashCommandMCPItems,
            isSlashCommandActive: isSlashMCPPopoverVisible,
            slashCommandFilterText: slashMCPFilterText,
            slashCommandHighlightedIndex: slashMCPHighlightedIndex,
            perMessageMCPChips: perMessageMCPChips,
            onSlashCommandSelectServer: handleSlashCommandSelectServer,
            onSlashCommandDismiss: dismissSlashCommandPopover,
            onRemovePerMessageMCPServer: removePerMessageMCPServer,
            onInterceptKeyDown: isSlashMCPPopoverVisible ? handleSlashCommandKeyDown : nil
        ) {
            composerControlsRow
        }
        .onChange(of: messageText) { _, newValue in
            updateSlashCommandState(for: newValue, target: .composer)
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

            composerButtonControl(
                systemName: conversationEntity.artifactsEnabled == true ? "square.stack.3d.up.fill" : "square.stack.3d.up",
                isActive: conversationEntity.artifactsEnabled == true,
                badgeText: nil,
                help: artifactsHelpText,
                activeColor: .accentColor,
                disabled: isBusy,
                action: toggleArtifactsEnabled
            )

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

            if supportsCodeExecutionControl {
                if hasCodeExecutionConfiguration {
                    composerButtonControl(
                        systemName: "chevron.left.forwardslash.chevron.right",
                        isActive: isCodeExecutionEnabled,
                        badgeText: codeExecutionBadgeText,
                        help: codeExecutionHelpText
                    ) {
                        codeExecutionEnabledBinding.wrappedValue.toggle()
                    }
                    .contextMenu {
                        Toggle("Code Execution", isOn: codeExecutionEnabledBinding)
                        Divider()
                        Button("Configure…") {
                            openCodeExecutionSheet()
                        }
                    }
                } else {
                    composerButtonControl(
                        systemName: "chevron.left.forwardslash.chevron.right",
                        isActive: isCodeExecutionEnabled,
                        badgeText: codeExecutionBadgeText,
                        help: codeExecutionHelpText
                    ) {
                        codeExecutionEnabledBinding.wrappedValue.toggle()
                    }
                }
            }

            if supportsGoogleMapsControl {
                composerMenuControl(
                    systemName: "map",
                    isActive: isGoogleMapsEnabled,
                    badgeText: googleMapsBadgeText,
                    help: googleMapsHelpText
                ) {
                    googleMapsMenuContent
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

            if isAgentModeConfigured {
                composerButtonControl(
                    systemName: "terminal.fill",
                    isActive: isAgentModeActive,
                    badgeText: isAgentModeActive ? "On" : nil,
                    help: isAgentModeActive ? "Agent Mode: On" : "Agent Mode: Off"
                ) {
                    isAgentModePopoverPresented.toggle()
                }
                .popover(isPresented: $isAgentModePopoverPresented, arrowEdge: .bottom) {
                    AgentModePopoverView(isActive: $isAgentModeActive)
                }
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
        // Keep historical row actions independent from global streaming state.
        // The action handlers themselves guard mutating operations, which avoids
        // send-time invalidation of every row footer/menu in large transcripts.
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
            editSlashCommand: editSlashCommandContext
        )
    }

    private var editSlashCommandContext: EditSlashCommandContext {
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

    private var assistantDisplayName: String {
        conversationEntity.assistant?.displayName ?? "Assistant"
    }

    private var singleThreadRenderContext: ChatThreadRenderContext {
        ChatThreadRenderContext(
            visibleMessages: cachedVisibleMessages,
            messageEntitiesByID: cachedMessageEntitiesByID,
            toolResultsByCallID: cachedToolResultsByCallID,
            artifactCatalog: cachedArtifactCatalog
        )
    }

    private var selectedThreadRenderContexts: [UUID: ChatThreadRenderContext] {
        Dictionary(uniqueKeysWithValues: selectedModelThreads.map { thread in
            (thread.id, threadRenderContext(threadID: thread.id))
        })
    }

    private var activeArtifactCatalog: ArtifactCatalog {
        if let activeThreadID, activeModelThread != nil {
            return threadRenderContext(threadID: activeThreadID).artifactCatalog
        }
        return cachedArtifactCatalog
    }

    private var selectedArtifactIDBinding: Binding<String?> {
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

    private var selectedArtifactVersionBinding: Binding<Int?> {
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
            onOpenArtifact: openArtifact,
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
            onOpenArtifact: openArtifact
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
        .onDisappear {
            updatedAtDebounceTask?.cancel()
            updatedAtDebounceTask = nil
            cancelRenderContextBuild()
        }
        .onChange(of: conversationEntity.id) { _, _ in
            handleConversationSwitch()
        }
        .onChange(of: editingUserMessageText) { _, newValue in
            updateSlashCommandState(for: newValue, target: .editMessage)
        }
        .onChange(of: conversationEntity.messages.count) { _, _ in
            rebuildMessageCachesIfNeeded()
        }
        .onChange(of: conversationEntity.updatedAt) { _, _ in
            // Debounce updatedAt-driven cache rebuilds so that rapid
            // successive updates (e.g. tool-call loops persisting
            // messages back-to-back) are coalesced into a single rebuild.
            updatedAtDebounceTask?.cancel()
            updatedAtDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                rebuildMessageCachesIfNeeded()
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: supportedAttachmentImportTypes,
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
        .sheet(isPresented: $showingCodeExecutionSheet) {
            CodeExecutionSheetView(
                draft: $codeExecutionDraft,
                openAIUseExistingContainer: $codeExecutionOpenAIUseExistingContainer,
                openAIFileIDsDraft: $codeExecutionOpenAIFileIDsDraft,
                draftError: $codeExecutionDraftError,
                providerType: providerType,
                isValid: isCodeExecutionDraftValid,
                onCancel: { showingCodeExecutionSheet = false },
                onSave: { applyCodeExecutionDraft() }
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
        .sheet(isPresented: $showingGoogleMapsSheet) {
            GoogleMapsSheetView(
                draft: $googleMapsDraft,
                latitudeDraft: $googleMapsLatitudeDraft,
                longitudeDraft: $googleMapsLongitudeDraft,
                languageCodeDraft: $googleMapsLanguageCodeDraft,
                draftError: $googleMapsDraftError,
                providerType: providerType,
                isValid: isGoogleMapsDraftValid,
                onCancel: { showingGoogleMapsSheet = false },
                onSave: { applyGoogleMapsDraft() }
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
        .sheet(item: activeAgentApprovalBinding) { item in
            AgentApprovalView(request: item.request) { choice in
                resolveAgentApproval(item, choice: choice)
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
        .overlay {
            expandedComposerOverlay
        }
        .animation(.easeInOut(duration: 0.2), value: isExpandedComposerPresented)
        .animation(.easeInOut(duration: 0.18), value: isArtifactPaneVisible)
    }

    private var messageStageContainer: some View {
        ZStack(alignment: .bottom) {
            messageStage
            floatingComposer
        }
    }

    private var artifactPane: some View {
        ArtifactWorkspaceView(
            catalog: activeArtifactCatalog,
            selectedArtifactID: selectedArtifactIDBinding,
            selectedArtifactVersion: selectedArtifactVersionBinding,
            onClose: {
                isArtifactPaneVisible = false
            }
        )
    }

    private var messageStage: some View {
        GeometryReader { geometry in
            if selectedModelThreads.count > 1 {
                multiThreadMessageStage(geometry: geometry)
            } else {
                singleThreadMessageStage(geometry: geometry)
            }
        }
        .environment(\.googleMapsLocationBias, googleMapsLocationBiasValue)
    }

    private var googleMapsLocationBiasValue: GoogleMapsLocationBias? {
        guard let lat = controls.googleMaps?.latitude,
              let lng = controls.googleMaps?.longitude else {
            return nil
        }
        return GoogleMapsLocationBias(latitude: lat, longitude: lng)
    }

    private var floatingComposer: some View {
        VStack(spacing: JinSpacing.small) {
            if isSlashMCPPopoverVisible, slashCommandTarget == .composer {
                SlashCommandMCPPopover(
                    servers: slashCommandMCPItems,
                    filterText: slashMCPFilterText,
                    highlightedIndex: slashMCPHighlightedIndex,
                    onSelectServer: handleSlashCommandSelectServer,
                    onDismiss: dismissSlashCommandPopover
                )
                .padding(.horizontal, JinSpacing.medium)
                .frame(maxWidth: 800)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            composerOverlay
        }
        .animation(.easeOut(duration: 0.15), value: isSlashMCPPopoverVisible)
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
            let isComposerTarget = slashCommandTarget == .composer
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
                onRemoveAttachment: removeDraftAttachment,
                slashCommandServers: slashCommandMCPItems,
                isSlashCommandActive: isSlashMCPPopoverVisible && isComposerTarget,
                slashCommandFilterText: isComposerTarget ? slashMCPFilterText : "",
                slashCommandHighlightedIndex: isComposerTarget ? slashMCPHighlightedIndex : 0,
                perMessageMCPChips: perMessageMCPChips,
                onSlashCommandSelectServer: handleSlashCommandSelectServer,
                onSlashCommandDismiss: dismissSlashCommandPopover,
                onRemovePerMessageMCPServer: removePerMessageMCPServer,
                onInterceptKeyDown: (isSlashMCPPopoverVisible && isComposerTarget) ? handleSlashCommandKeyDown : nil
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
            openAddModelPicker: { isAddModelPickerPresented.toggle() },
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
        syncArtifactSelectionForActiveThread()
    }

    private func handleConversationSwitch() {
        // Switching chats: reset ALL transient per-chat state, clear the
        // displayed messages immediately so the switch feels instant, then
        // rebuild caches on the next run-loop tick.

        // Editing / composer
        cancelEditingUserMessage()
        speechToTextManager.cancelAndCleanup()
        messageText = ""
        draftAttachments = []
        dropAttachmentImportInFlightCount = 0
        composerTextContentHeight = 36
        remoteVideoInputURLText = ""
        isExpandedComposerPresented = false
        isSlashMCPPopoverVisible = false
        slashMCPFilterText = ""
        slashMCPHighlightedIndex = 0
        perMessageMCPServerIDs = []

        // Prepare-to-send
        prepareToSendCancellationReason = .conversationSwitch
        prepareToSendTask?.cancel()
        isPreparingToSend = false
        prepareToSendStatus = nil
        prepareToSendTask = nil

        // Popovers / sheets / alerts
        isModelPickerPresented = false
        isAddModelPickerPresented = false
        showingThinkingBudgetSheet = false
        showingCodeExecutionSheet = false
        showingContextCacheSheet = false
        showingAnthropicWebSearchSheet = false
        showingImageGenerationSheet = false
        showingCodexSessionSettingsSheet = false
        showingGoogleMapsSheet = false
        googleMapsDraft = GoogleMapsControls()
        googleMapsLatitudeDraft = ""
        googleMapsLongitudeDraft = ""
        googleMapsLanguageCodeDraft = ""
        googleMapsDraftError = nil
        showingError = false
        errorMessage = nil

        // Codex
        pendingCodexInteractions = []

        // Agent
        pendingAgentApprovals = []

        // Scroll / pagination
        messageRenderLimit = Self.initialMessageRenderLimit
        pendingRestoreScrollMessageID = nil
        isPinnedToBottom = true

        // Artifacts
        isArtifactPaneVisible = false
        selectedArtifactIDByThreadID = [:]
        selectedArtifactVersionByThreadID = [:]

        // Cancel any pending debounced rebuild from the previous conversation.
        updatedAtDebounceTask?.cancel()
        updatedAtDebounceTask = nil
        cancelRenderContextBuild()

        // Clear caches synchronously so stale content is never shown, then
        // load controls (lightweight) so the header reflects the new chat.
        cachedVisibleMessages = []
        cachedMessageEntitiesByID = [:]
        cachedToolResultsByCallID = [:]
        cachedArtifactCatalog = .empty
        cachedMessagesVersion &+= 1
        lastCacheRebuildMessageCount = 0
        lastCacheRebuildUpdatedAt = .distantPast

        // loadControlsFromConversation internally calls ensureModelThreadsInitializedIfNeeded
        // and syncActiveThreadSelection, so calling them separately is redundant.
        loadControlsFromConversation()

        // Defer the heavy rebuild so SwiftUI can commit the state reset above
        // (clears the view) before we block the main actor with JSON decoding.
        let targetConversationID = conversationEntity.id
        Task { @MainActor in
            guard conversationEntity.id == targetConversationID else { return }
            rebuildMessageCaches()
            syncArtifactSelectionForActiveThread()
        }
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
        (!trimmedMessageText.isEmpty || !draftAttachments.isEmpty) && !isImportingDropAttachments
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
            ? "Attach images / videos / audio / documents"
            : "Attach images / videos / documents"
        return supportsNativePDF ? "\(base) (native PDF available)" : "\(base) (PDFs may use extraction/OCR)"
    }

    private static let supportedAttachmentDocumentExtensions = [
        "docx", "doc", "odt", "rtf",
        "xlsx", "xls", "csv", "tsv",
        "pptx", "ppt",
        "txt", "md", "markdown",
        "json", "html", "htm", "xml"
    ]

    private var supportedAttachmentImportTypes: [UTType] {
        var types: [UTType] = []
        var seen: Set<String> = []

        func append(_ type: UTType?) {
            guard let type, seen.insert(type.identifier).inserted else { return }
            types.append(type)
        }

        append(.image)
        append(.movie)
        append(.audio)
        append(.pdf)

        for ext in Self.supportedAttachmentDocumentExtensions {
            append(UTType(filenameExtension: ext))
        }

        return types
    }

    private var artifactsHelpText: String {
        if conversationEntity.artifactsEnabled == true {
            return "Artifacts enabled for new replies"
        }
        return "Enable artifact generation for new replies"
    }

    private func toggleArtifactsEnabled() {
        conversationEntity.artifactsEnabled = !(conversationEntity.artifactsEnabled == true)
        conversationEntity.updatedAt = Date()
        try? modelContext.save()
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
        var uniqueURLs = OrderedSet<URL>()
        for url in urls {
            uniqueURLs.append(url)
        }
        guard !uniqueURLs.isEmpty else { return false }

        if isBusy {
            errorMessage = "Stop generating (or wait for PDF processing) to attach files."
            showingError = true
            return true
        }

        Task { await importAttachments(from: Array(uniqueURLs)) }
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
        guard canSendDraft, !isBusy else { return }
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
        guard let result = ChatDropHandlingSupport.appendTextChunksToComposer(textChunks, currentText: messageText) else {
            return false
        }
        messageText = result
        return true
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        isFullPageDropTargeted = false

        if isBusy {
            errorMessage = "Stop generating (or wait for PDF processing) to attach files."
            showingError = true
            return true
        }

        let dropConversationID = conversationEntity.id

        let didSchedule = ChatDropHandlingSupport.processDropProviders(providers) { [self] result in
            Task { @MainActor in
                guard conversationEntity.id == dropConversationID else { return }
                guard !isBusy else { return }

                if !result.textChunks.isEmpty {
                    appendTextChunksToComposer(result.textChunks)
                }

                var allErrors = result.errors

                if !result.fileURLs.isEmpty {
                    let maxAttachments = AttachmentConstants.maxDraftAttachments
                    let attachmentCountAtDrop = draftAttachments.count
                    dropAttachmentImportInFlightCount += 1
                    defer {
                        if conversationEntity.id == dropConversationID {
                            dropAttachmentImportInFlightCount = max(0, dropAttachmentImportInFlightCount - 1)
                        }
                    }
                    let (newAttachments, importErrors) = await ChatDropHandlingSupport.importAttachments(
                        from: result.fileURLs,
                        currentAttachmentCount: attachmentCountAtDrop,
                        maxAttachments: maxAttachments
                    )

                    guard conversationEntity.id == dropConversationID else { return }
                    guard !isBusy else { return }

                    allErrors.append(contentsOf: importErrors)

                    if !newAttachments.isEmpty {
                        let remainingSlots = max(0, maxAttachments - draftAttachments.count)
                        let limitMessage = "You can attach up to \(maxAttachments) files per message."

                        if remainingSlots <= 0 {
                            if !allErrors.contains(limitMessage) {
                                allErrors.append(limitMessage)
                            }
                        } else {
                            let attachmentsToAppend = newAttachments.prefix(remainingSlots)
                            if attachmentsToAppend.count < newAttachments.count, !allErrors.contains(limitMessage) {
                                allErrors.append(limitMessage)
                            }
                            draftAttachments.append(contentsOf: attachmentsToAppend)
                        }
                    }
                }

                guard conversationEntity.id == dropConversationID else { return }
                guard !isBusy else { return }

                if !allErrors.isEmpty {
                    errorMessage = allErrors.joined(separator: "\n")
                    showingError = true
                }
            }
        }

        return didSchedule
    }

    private func importAttachments(from urls: [URL]) async {
        guard !urls.isEmpty, !isStreaming else { return }

        let (newAttachments, errors) = await ChatDropHandlingSupport.importAttachments(
            from: urls,
            currentAttachmentCount: draftAttachments.count,
            maxAttachments: AttachmentConstants.maxDraftAttachments
        )

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

    var resolvedModelSettings: ResolvedModelSettings? {
        guard let model = selectedModelInfo else { return nil }
        return ModelSettingsResolver.resolve(model: model, providerType: providerType)
    }

    var lowerModelID: String {
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

    func canonicalizeThreadModelIDIfNeeded(_ thread: ConversationModelThreadEntity) {
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

    var supportsNativePDF: Bool {
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

    var supportsImageGenerationControl: Bool {
        resolvedModelSettings?.capabilities.contains(.imageGeneration) == true || isImageGenerationModelID
    }

    var supportsVideoGenerationControl: Bool {
        resolvedModelSettings?.capabilities.contains(.videoGeneration) == true || isVideoGenerationModelID
    }

    var supportsMediaGenerationControl: Bool {
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

    var supportsPDFProcessingControl: Bool {
        guard providerType != .codexAppServer else { return false }
        return true
    }

    var supportsCurrentModelImageSizeControl: Bool {
        ChatModelCapabilitySupport.supportsCurrentModelImageSizeControl(lowerModelID: lowerModelID)
    }

    var supportedCurrentModelImageAspectRatios: [ImageAspectRatio] {
        ChatModelCapabilitySupport.supportedCurrentModelImageAspectRatios(lowerModelID: lowerModelID)
    }

    var supportedCurrentModelImageSizes: [ImageOutputSize] {
        ChatModelCapabilitySupport.supportedCurrentModelImageSizes(lowerModelID: lowerModelID)
    }

    var isImageGenerationConfigured: Bool {
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

    var isVideoGenerationConfigured: Bool {
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

    var resolvedPDFProcessingMode: PDFProcessingMode {
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
            return "PDF handling: Native"
        case .mistralOCR:
            return mistralOCRConfigured ? "PDF handling: Mistral OCR" : "PDF handling: Mistral OCR (API key required)"
        case .deepSeekOCR:
            return deepSeekOCRConfigured ? "PDF handling: DeepSeek OCR (DeepInfra)" : "PDF handling: DeepSeek OCR (API key required)"
        case .macOSExtract:
            return "PDF handling: macOS Extract"
        }
    }

    var selectedReasoningConfig: ModelReasoningConfig? {
        if providerType == .vertexai,
           (lowerModelID == "gemini-3-pro-image-preview"
               || lowerModelID == "gemini-3.1-flash-image-preview") {
            return nil
        }
        return resolvedModelSettings?.reasoningConfig
    }

    var isReasoningEnabled: Bool {
        if reasoningMustRemainEnabled {
            return true
        }
        if providerType == .fireworks, isFireworksMiniMaxM2FamilyModel(conversationEntity.modelID) {
            return true
        }
        return controls.reasoning?.enabled == true
    }

    var isWebSearchEnabled: Bool {
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

    var isMCPToolsEnabled: Bool {
        controls.mcpTools?.enabled == true
    }

    var effectiveContextCacheMode: ContextCacheMode {
        if let mode = controls.contextCache?.mode {
            return mode
        }
        if providerType == .anthropic {
            return .implicit
        }
        return .off
    }

    var isContextCacheEnabled: Bool {
        effectiveContextCacheMode != .off
    }

    var supportsReasoningControl: Bool {
        guard let config = selectedReasoningConfig else { return false }
        return config.type != .none
    }

    var supportsReasoningDisableToggle: Bool {
        guard supportsReasoningControl else { return false }
        return !reasoningMustRemainEnabled
    }

    var reasoningMustRemainEnabled: Bool {
        resolvedModelSettings?.reasoningCanDisable == false
    }

    var supportsNativeWebSearchControl: Bool {
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

    var modelSupportsBuiltinSearchPluginControl: Bool {
        guard providerType != .codexAppServer else { return false }
        guard !supportsMediaGenerationControl else { return false }
        guard resolvedModelSettings?.capabilities.contains(.toolCalling) == true else { return false }
        return true
    }

    var supportsBuiltinSearchPluginControl: Bool {
        guard modelSupportsBuiltinSearchPluginControl else { return false }
        guard webSearchPluginEnabled, webSearchPluginConfigured else { return false }
        return true
    }

    var supportsSearchEngineModeSwitch: Bool {
        supportsNativeWebSearchControl && supportsBuiltinSearchPluginControl
    }

    var prefersJinSearchEngine: Bool {
        controls.searchPlugin?.preferJinSearch == true
    }

    var usesBuiltinSearchPlugin: Bool {
        guard supportsBuiltinSearchPluginControl else { return false }
        if supportsNativeWebSearchControl {
            return prefersJinSearchEngine
        }
        return true
    }

    var modelSupportsWebSearchControl: Bool {
        supportsNativeWebSearchControl || modelSupportsBuiltinSearchPluginControl
    }

    var supportsWebSearchControl: Bool {
        supportsNativeWebSearchControl || supportsBuiltinSearchPluginControl
    }

    var supportsCodeExecutionControl: Bool {
        guard let modelID = selectedModelInfo?.id else { return false }
        return ModelCapabilityRegistry.supportsCodeExecution(for: providerType, modelID: modelID)
    }

    var isCodeExecutionEnabled: Bool {
        controls.codeExecution?.enabled == true
    }

    var hasCodeExecutionConfiguration: Bool {
        providerType == .openai || providerType == .anthropic
    }

    var supportsGoogleMapsControl: Bool {
        guard let modelID = selectedModelInfo?.id else { return false }
        return ModelCapabilityRegistry.supportsGoogleMaps(for: providerType, modelID: modelID)
    }

    var isGoogleMapsEnabled: Bool {
        controls.googleMaps?.enabled == true
    }

    var googleMapsBadgeText: String? {
        guard isGoogleMapsEnabled else { return nil }
        if controls.googleMaps?.hasLocation == true {
            return "Loc"
        }
        return nil
    }

    var googleMapsHelpText: String {
        guard isGoogleMapsEnabled else { return "Google Maps: Off" }
        if controls.googleMaps?.hasLocation == true {
            return "Google Maps: On (with location)"
        }
        return "Google Maps: On"
    }

    var googleMapsEnabledBinding: Binding<Bool> {
        Binding(
            get: { controls.googleMaps?.enabled == true },
            set: { enabled in
                var updated = controls.googleMaps ?? GoogleMapsControls(enabled: enabled)
                updated.enabled = enabled
                controls.googleMaps = updated.isEmpty ? nil : updated
                persistControlsToConversation()
            }
        )
    }

    var parsedCodeExecutionOpenAIFileIDsDraft: [String] {
        codeExecutionOpenAIFileIDsDraft
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var isAgentModeConfigured: Bool {
        AppPreferences.isPluginEnabled("agent_mode")
    }

    var codeExecutionBadgeText: String? {
        guard isCodeExecutionEnabled else { return nil }

        switch providerType {
        case .openai:
            if controls.codeExecution?.openAI?.normalizedExistingContainerID != nil {
                return "reuse"
            }
            return controls.codeExecution?.openAI?.container?.normalizedMemoryLimit
        case .anthropic:
            return controls.codeExecution?.anthropic?.normalizedContainerID == nil ? nil : "reuse"
        default:
            return nil
        }
    }

    var codeExecutionHelpText: String {
        guard isCodeExecutionEnabled else { return "Code Execution: Off" }

        switch providerType {
        case .openai:
            if let containerID = controls.codeExecution?.openAI?.normalizedExistingContainerID {
                return "Code Execution: Reuse \(containerID)"
            }
            if let memoryLimit = controls.codeExecution?.openAI?.container?.normalizedMemoryLimit {
                return "Code Execution: Auto container (\(memoryLimit))"
            }
            return "Code Execution: Auto container"
        case .anthropic:
            if controls.codeExecution?.anthropic?.normalizedContainerID != nil {
                return "Code Execution: Reuse container"
            }
            return "Code Execution: On"
        case .vertexai:
            return "Code Execution: On (no file I/O in sandbox)"
        default:
            return "Code Execution: On"
        }
    }

    var codeExecutionEnabledBinding: Binding<Bool> {
        Binding(
            get: { controls.codeExecution?.enabled ?? false },
            set: { enabled in
                var updated = controls.codeExecution ?? CodeExecutionControls()
                updated.enabled = enabled
                controls.codeExecution = updated
                persistControlsToConversation()
            }
        )
    }

    var isCodeExecutionDraftValid: Bool {
        guard providerType == .openai, codeExecutionOpenAIUseExistingContainer else {
            return true
        }
        return codeExecutionDraft.openAI?.normalizedExistingContainerID != nil
    }

    var supportsContextCacheControl: Bool {
        // Context cache is now fully automatic and intentionally hidden from the composer UI.
        false
    }

    var supportsExplicitContextCacheMode: Bool {
        switch providerType {
        case .gemini, .vertexai:
            return true
        case .openai, .openaiWebSocket, .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together,
             .xai, .deepseek, .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .none:
            return false
        }
    }

    var supportsContextCacheStrategy: Bool {
        providerType == .anthropic
    }

    var supportsContextCacheTTL: Bool {
        switch providerType {
        case .openai, .openaiWebSocket, .anthropic, .xai:
            return true
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .perplexity,
             .groq, .cohere, .mistral, .deepinfra, .together, .gemini, .vertexai, .deepseek,
             .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .none:
            return false
        }
    }

    var contextCacheSupportsAdvancedOptions: Bool {
        supportsContextCacheTTL || providerType == .openai || providerType == .xai
    }

    var contextCacheSummaryText: String {
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

    var contextCacheGuidanceText: String {
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
        ChatAuxiliaryControlSupport.automaticContextCacheControls(
            providerType: providerType,
            modelID: modelID,
            modelCapabilities: modelCapabilities,
            supportsMediaGenerationControl: supportsMediaGenerationControl,
            conversationID: conversationEntity.id
        )
    }

    var supportsMCPToolsControl: Bool {
        guard providerType != .codexAppServer else { return false }
        guard !supportsMediaGenerationControl else { return false }
        return resolvedModelSettings?.capabilities.contains(.toolCalling) == true
    }

    var supportsCodexSessionControl: Bool {
        providerType == .codexAppServer
    }

    var supportsOpenAIServiceTierControl: Bool {
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

    var effectiveSearchPluginProvider: SearchPluginProvider {
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

    var codexWorkingDirectory: String? {
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

    var eligibleMCPServers: [MCPServerConfigEntity] {
        mcpServers
            .filter { $0.isEnabled && $0.runToolsAutomatically }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var selectedMCPServerIDs: Set<String> {
        ChatAuxiliaryControlSupport.selectedMCPServerIDs(
            controls: controls,
            eligibleServers: eligibleMCPServers
        )
    }

    var mcpServerMenuItems: [MCPServerMenuItem] {
        eligibleMCPServers.map { server in
            MCPServerMenuItem(
                id: server.id,
                name: server.name,
                isOn: mcpServerSelectionBinding(serverID: server.id)
            )
        }
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

    func synchronizeLegacyConversationModelFields(with thread: ConversationModelThreadEntity) {
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
        let threadID = activeModelThread?.id
        let ordered = orderedConversationMessages(threadID: threadID)
        let targetUpdatedAt = conversationEntity.updatedAt
        let fallbackModelLabel = currentModelName

        cancelRenderContextBuild()

        let messageEntitiesByID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        if ordered.count < Self.asyncCacheBuildMessageThreshold {
            let context = ChatMessageRenderPipeline.makeRenderContext(
                from: ordered,
                fallbackModelLabel: fallbackModelLabel,
                assistantProviderIconID: { providerID in
                    providerIconID(for: providerID)
                }
            )
            applyDecodedRenderContext(
                ChatDecodedRenderContext(
                    visibleMessages: context.visibleMessages,
                    toolResultsByCallID: context.toolResultsByCallID,
                    artifactCatalog: context.artifactCatalog
                ),
                messageEntitiesByID: context.messageEntitiesByID,
                messageCount: ordered.count,
                updatedAt: targetUpdatedAt
            )
            return
        }

        let providerIconsByID = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0.resolvedProviderIconID) })
        let snapshots = ordered.map(PersistedMessageSnapshot.init)
        let targetConversationID = conversationEntity.id
        let targetThreadID = threadID
        let messageCount = ordered.count
        let buildToken = UUID()
        activeRenderContextBuildToken = buildToken

        let decodeTask = Task.detached(priority: .userInitiated) {
            ChatMessageRenderPipeline.makeDecodedRenderContext(
                from: snapshots,
                fallbackModelLabel: fallbackModelLabel,
                assistantProviderIconsByID: providerIconsByID
            )
        }
        renderContextDecodeTask = decodeTask

        renderContextBuildTask = Task { @MainActor in
            defer {
                if activeRenderContextBuildToken == buildToken {
                    renderContextBuildTask = nil
                    renderContextDecodeTask = nil
                }
            }

            let decoded = await decodeTask.value
            guard !Task.isCancelled else { return }
            guard activeRenderContextBuildToken == buildToken else { return }
            guard conversationEntity.id == targetConversationID else { return }
            guard activeModelThread?.id == targetThreadID else { return }
            guard conversationEntity.updatedAt == targetUpdatedAt else { return }

            applyDecodedRenderContext(
                decoded,
                messageEntitiesByID: messageEntitiesByID,
                messageCount: messageCount,
                updatedAt: targetUpdatedAt
            )
        }
    }

    private func cancelRenderContextBuild() {
        activeRenderContextBuildToken = UUID()
        renderContextBuildTask?.cancel()
        renderContextBuildTask = nil
        renderContextDecodeTask?.cancel()
        renderContextDecodeTask = nil
    }

    private func applyDecodedRenderContext(
        _ context: ChatDecodedRenderContext,
        messageEntitiesByID: [UUID: MessageEntity],
        messageCount: Int,
        updatedAt: Date
    ) {
        cachedVisibleMessages = context.visibleMessages
        cachedMessageEntitiesByID = messageEntitiesByID
        cachedToolResultsByCallID = context.toolResultsByCallID
        cachedArtifactCatalog = context.artifactCatalog
        cachedMessagesVersion &+= 1
        lastCacheRebuildMessageCount = messageCount
        lastCacheRebuildUpdatedAt = updatedAt
        syncArtifactSelectionForActiveThread()
    }

    private func syncArtifactSelectionForActiveThread() {
        guard let threadID = activeModelThread?.id else { return }

        let catalog = activeModelThread?.id == activeThreadID ? cachedArtifactCatalog : threadRenderContext(threadID: threadID).artifactCatalog
        guard !catalog.isEmpty else {
            selectedArtifactIDByThreadID[threadID] = nil
            selectedArtifactVersionByThreadID[threadID] = nil
            return
        }

        let selectedArtifactID = selectedArtifactIDByThreadID[threadID]
        let selectedVersion = selectedArtifactVersionByThreadID[threadID]

        if let selectedArtifactID,
           catalog.version(artifactID: selectedArtifactID, version: selectedVersion) != nil {
            return
        }

        if let latest = catalog.latestVersion {
            selectedArtifactIDByThreadID[threadID] = latest.artifactID
            selectedArtifactVersionByThreadID[threadID] = latest.version
        }
    }

    private func openArtifact(_ artifact: RenderedArtifactVersion, threadID: UUID?) {
        let resolvedThreadID = threadID ?? activeModelThread?.id
        if let resolvedThreadID, activeModelThread?.id != resolvedThreadID {
            activateThread(by: resolvedThreadID)
        }

        if let resolvedThreadID {
            selectedArtifactIDByThreadID[resolvedThreadID] = artifact.artifactID
            selectedArtifactVersionByThreadID[resolvedThreadID] = artifact.version
        }

        isArtifactPaneVisible = true
    }

    private func autoOpenLatestArtifactIfNeeded(from message: Message, threadID: UUID) {
        guard activeModelThread?.id == threadID else { return }

        let artifacts = message.content.compactMap { part -> [ParsedArtifact]? in
            guard case .text(let text) = part else { return nil }
            return ArtifactMarkupParser.parse(text).artifacts
        }.flatMap { $0 }

        guard let latest = artifacts.last else { return }

        let catalog = cachedArtifactCatalog
        let resolvedVersion = catalog.latestVersion(for: latest.artifactID)
        if let resolvedVersion {
            selectedArtifactIDByThreadID[threadID] = resolvedVersion.artifactID
            selectedArtifactVersionByThreadID[threadID] = resolvedVersion.version
        } else {
            selectedArtifactIDByThreadID[threadID] = latest.artifactID
        }

        isArtifactPaneVisible = true
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
        if let idsData = messageEntity.perMessageMCPServerIDsData,
           let savedIDs = try? JSONDecoder().decode([String].self, from: idsData) {
            perMessageMCPServerIDs = Set(savedIDs)
        } else {
            perMessageMCPServerIDs = []
        }

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

        let selectedServers = eligibleMCPServers.filter { perMessageMCPServerIDs.contains($0.id) }
        if !selectedServers.isEmpty {
            messageEntity.perMessageMCPServerNamesData = try? JSONEncoder().encode(selectedServers.map(\.name).sorted())
            messageEntity.perMessageMCPServerIDsData = try? JSONEncoder().encode(selectedServers.map(\.id).sorted())
        } else {
            messageEntity.perMessageMCPServerNamesData = nil
            messageEntity.perMessageMCPServerIDsData = nil
        }

        endEditingUI()
        regenerateFromUserMessage(messageEntity)
    }

    /// Clears editing UI state without resetting the composer-level per-message MCP selection.
    private func endEditingUI() {
        editingUserMessageID = nil
        editingUserMessageText = ""
        isEditingUserMessageFocused = false
        if slashCommandTarget == .editMessage {
            isSlashMCPPopoverVisible = false
            slashMCPFilterText = ""
            slashMCPHighlightedIndex = 0
        }
    }

    private func cancelEditingUserMessage() {
        endEditingUI()
        perMessageMCPServerIDs = []
    }

    private func regenerateFromUserMessage(_ messageEntity: MessageEntity) {
        guard let threadID = messageEntity.contextThreadID ?? activeModelThread?.id else { return }
        guard let keepCount = keepCountForRegeneratingUserMessage(messageEntity, threadID: threadID) else { return }
        var perMessageMCPSnapshot = perMessageMCPServerIDs
        if perMessageMCPSnapshot.isEmpty,
           let idsData = messageEntity.perMessageMCPServerIDsData,
           let savedIDs = try? JSONDecoder().decode([String].self, from: idsData) {
            perMessageMCPSnapshot = Set(savedIDs)
        }
        perMessageMCPServerIDs = []
        let askedAt = Date()
        truncateConversation(keepingMessages: keepCount, in: threadID)
        messageEntity.timestamp = askedAt
        conversationEntity.updatedAt = askedAt
        activateThread(by: threadID)
        startStreamingResponse(
            for: threadID,
            triggeredByUserSend: false,
            perMessageMCPServerIDs: perMessageMCPSnapshot
        )
    }

    private func regenerateFromAssistantMessage(_ messageEntity: MessageEntity) {
        guard let threadID = messageEntity.contextThreadID ?? activeModelThread?.id else { return }
        guard let keepCount = keepCountForRegeneratingAssistantMessage(messageEntity, threadID: threadID) else { return }
        truncateConversation(keepingMessages: keepCount, in: threadID)
        activateThread(by: threadID)
        startStreamingResponse(for: threadID, triggeredByUserSend: false)
    }

    private func deleteMessage(_ messageEntity: MessageEntity) {
        guard !isStreaming else { return }
        cancelEditingUserMessage()

        let threadID = messageEntity.contextThreadID ?? activeModelThread?.id
        guard let threadID else { return }
        let ordered = orderedConversationMessages(threadID: threadID)

        let messagesToDelete: [MessageEntity]?
        switch messageEntity.role {
        case "user":
            messagesToDelete = ChatMessageEditingSupport.messagesToDeleteForUserMessage(messageEntity, orderedMessages: ordered)
        case "assistant":
            messagesToDelete = ChatMessageEditingSupport.messagesToDeleteForAssistantMessage(messageEntity, orderedMessages: ordered)
        default:
            messagesToDelete = nil
        }

        guard let messagesToDelete, !messagesToDelete.isEmpty else { return }
        deleteMessages(messagesToDelete, in: threadID)
    }

    private func deleteResponse(_ messageEntity: MessageEntity) {
        guard !isStreaming else { return }
        guard messageEntity.role == "user" else { return }
        cancelEditingUserMessage()

        let threadID = messageEntity.contextThreadID ?? activeModelThread?.id
        guard let threadID else { return }
        let ordered = orderedConversationMessages(threadID: threadID)

        guard let messagesToDelete = ChatMessageEditingSupport.messagesToDeleteForResponse(
            afterUserMessage: messageEntity,
            orderedMessages: ordered
        ) else { return }

        deleteMessages(messagesToDelete, in: threadID)
    }

    private func deleteMessages(_ messages: [MessageEntity], in threadID: UUID) {
        let idsToDelete = Set(messages.map(\.id))
        recordCodexThreadHistoryMutation(forThreadID: threadID, removedMessages: messages)
        for message in messages {
            modelContext.delete(message)
        }
        conversationEntity.messages.removeAll { idsToDelete.contains($0.id) }
        refreshConversationActivityTimestampFromLatestUserMessage()
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        rebuildMessageCaches()
    }

    private func keepCountForRegeneratingUserMessage(_ messageEntity: MessageEntity, threadID: UUID) -> Int? {
        ChatMessageEditingSupport.keepCountForRegeneratingUserMessage(messageEntity, orderedMessages: orderedConversationMessages(threadID: threadID))
    }

    private func keepCountForRegeneratingAssistantMessage(_ messageEntity: MessageEntity, threadID: UUID) -> Int? {
        ChatMessageEditingSupport.keepCountForRegeneratingAssistantMessage(messageEntity, orderedMessages: orderedConversationMessages(threadID: threadID))
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

    func storedGenerationControls(for thread: ConversationModelThreadEntity) -> GenerationControls? {
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
        ChatMessageEditingSupport.refreshConversationActivityTimestamp(conversation: conversationEntity)
    }

    private func editableUserText(from message: Message) -> String? {
        ChatMessageRenderPipeline.editableUserText(from: message)
    }

    private func updateUserMessageContent(_ entity: MessageEntity, newText: String) throws {
        try ChatMessageEditingSupport.updateUserMessageContent(entity, newText: newText)
    }

    private func resolvedSystemPrompt(conversationSystemPrompt: String?, assistant: AssistantEntity?) -> String? {
        let basePrompt = ChatMessagePreparationSupport.resolvedSystemPrompt(
            conversationSystemPrompt: conversationSystemPrompt,
            assistant: assistant
        )

        return ArtifactMarkupParser.appendingInstructions(
            to: basePrompt,
            enabled: conversationEntity.artifactsEnabled == true
        )
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
            prepareToSendCancellationReason = .userCancelled
            prepareToSendTask?.cancel()
            return
        }

        guard !isImportingDropAttachments else { return }
        guard canSendDraft else { return }
        endEditingUI()
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
        let selectedPerMessageMCPServers = eligibleMCPServers.filter { perMessageMCPServerIDs.contains($0.id) }
        let perMessageMCPIDsSnapshot = selectedPerMessageMCPServers.map(\.id).sorted()
        let perMessageMCPNamesSnapshot = selectedPerMessageMCPServers.map(\.name).sorted()
        let perMessageMCPIDsData: Data? = perMessageMCPIDsSnapshot.isEmpty ? nil : try? JSONEncoder().encode(perMessageMCPIDsSnapshot)
        let perMessageMCPSnapshot = Set(perMessageMCPIDsSnapshot)
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
        prepareToSendCancellationReason = nil

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

                    let toolCapableThreadIDs = Set(targetThreads.compactMap { threadSupportsMCPTools(for: $0) ? $0.id : nil })
                    for prepared in preparedMessages {
                        let message = Message(
                            role: .user,
                            content: prepared.parts,
                            timestamp: askedAt,
                            perMessageMCPServerNames: toolCapableThreadIDs.contains(prepared.threadID) ? perMessageMCPNamesSnapshot : nil
                        )
                        guard let messageEntity = try? MessageEntity.fromDomain(message) else { continue }
                        if toolCapableThreadIDs.contains(prepared.threadID) {
                            messageEntity.perMessageMCPServerIDsData = perMessageMCPIDsData
                        }
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
                    prepareToSendCancellationReason = nil
                    perMessageMCPServerIDs = []
                    for threadID in targetThreadIDs {
                        startStreamingResponse(
                            for: threadID,
                            triggeredByUserSend: threadID == namingThreadID,
                            turnID: turnID,
                            perMessageMCPServerIDs: perMessageMCPSnapshot
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    let cancellationReason = prepareToSendCancellationReason
                    isPreparingToSend = false
                    prepareToSendStatus = nil
                    prepareToSendTask = nil
                    prepareToSendCancellationReason = nil
                    if !(error is CancellationError) || cancellationReason == .userCancelled {
                        messageText = messageTextSnapshot
                        remoteVideoInputURLText = remoteVideoURLTextSnapshot
                        draftAttachments = attachmentsSnapshot
                    }
                    if !(error is CancellationError) {
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                }
            }
        }

        prepareToSendTask = task
    }

    private func buildUserMessagePartsForThreads(
        threads: [ConversationModelThreadEntity],
        messageText: String,
        attachments: [DraftAttachment],
        remoteVideoURL: URL?
    ) async throws -> [ChatMessagePreparationSupport.ThreadPreparedUserMessage] {
        var preparedMessages: [ChatMessagePreparationSupport.ThreadPreparedUserMessage] = []
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
            preparedMessages.append(ChatMessagePreparationSupport.ThreadPreparedUserMessage(threadID: profile.threadID, parts: parts))
        }

        return preparedMessages
    }

    private func messagePreparationProfile(for thread: ConversationModelThreadEntity) throws -> ChatMessagePreparationSupport.MessagePreparationProfile {
        try ChatMessagePreparationSupport.messagePreparationProfile(
            for: thread,
            providers: providers,
            controls: controls,
            mistralOCRPluginEnabled: mistralOCRPluginEnabled,
            deepSeekOCRPluginEnabled: deepSeekOCRPluginEnabled,
            defaultPDFProcessingFallbackMode: defaultPDFProcessingFallbackMode
        )
    }

    private func providerType(forProviderID providerID: String) -> ProviderType? {
        ChatMessagePreparationSupport.providerType(forProviderID: providerID, providers: providers)
    }

    private func normalizedModelInfo(_ model: ModelInfo, for providerType: ProviderType?) -> ModelInfo {
        ChatModelCapabilitySupport.normalizedSelectedModelInfo(model, providerType: providerType)
    }

    private func buildUserMessageParts(
        messageText: String,
        attachments: [DraftAttachment],
        remoteVideoURL: URL?,
        profile: ChatMessagePreparationSupport.MessagePreparationProfile
    ) async throws -> [ContentPart] {
        try await ChatMessagePreparationSupport.buildUserMessageParts(
            messageText: messageText,
            attachments: attachments,
            remoteVideoURL: remoteVideoURL,
            profile: profile,
            preparedContentForPDF: { attachment, profile, mode, total, ordinal, mistral, deepseek in
                try await ChatMessagePreparationSupport.preparedContentForPDF(
                    attachment,
                    profile: profile,
                    requestedMode: mode,
                    totalPDFCount: total,
                    pdfOrdinal: ordinal,
                    mistralClient: mistral,
                    deepSeekClient: deepseek,
                    onStatusUpdate: { [self] status in
                        prepareToSendStatus = status
                    }
                )
            }
        )
    }

    private func resolvedRemoteVideoInputURL(from raw: String) throws -> URL? {
        try ChatMessagePreparationSupport.resolvedRemoteVideoInputURL(
            from: raw,
            supportsExplicitRemoteVideoURLInput: supportsExplicitRemoteVideoURLInput
        )
    }

    private func makeConversationTitle(from userText: String) -> String {
        ChatMessagePreparationSupport.makeConversationTitle(from: userText)
    }

    private func threadSupportsMCPTools(
        providerType: ProviderType?,
        resolvedModelSettings: ResolvedModelSettings?
    ) -> Bool {
        guard providerType != .codexAppServer else { return false }
        guard !(resolvedModelSettings?.capabilities.contains(.imageGeneration) == true
                || resolvedModelSettings?.capabilities.contains(.videoGeneration) == true) else {
            return false
        }
        return resolvedModelSettings?.capabilities.contains(.toolCalling) == true
    }

    private func threadSupportsMCPTools(for thread: ConversationModelThreadEntity) -> Bool {
        let providerEntity = providers.first(where: { $0.id == thread.providerID })
        let providerTypeSnapshot = providerEntity.flatMap { ProviderType(rawValue: $0.typeRaw) } ?? ProviderType(rawValue: thread.providerID)
        let modelID = effectiveModelID(
            for: thread.modelID,
            providerEntity: providerEntity,
            providerType: providerTypeSnapshot
        )
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

        return threadSupportsMCPTools(
            providerType: providerTypeSnapshot,
            resolvedModelSettings: resolvedModelSettingsSnapshot
        )
    }

    @MainActor
    private func startStreamingResponse(
        for threadID: UUID,
        triggeredByUserSend: Bool = false,
        turnID: UUID? = nil,
        perMessageMCPServerIDs: Set<String> = []
    ) {
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
        controlsToUse.agentMode = Self.resolvedAgentModeControls(active: isAgentModeActive)

        let shouldTruncateMessages = assistant?.truncateMessages ?? false
        let maxHistoryMessages = assistant?.maxHistoryMessages
        let modelContextWindow = resolvedModelSettingsSnapshot?.contextWindow ?? 128000
        let reservedOutputTokens = max(0, controlsToUse.maxTokens ?? 2048)
        let threadSupportsPerMessageMCP = threadSupportsMCPTools(
            providerType: providerTypeSnapshot,
            resolvedModelSettings: resolvedModelSettingsSnapshot
        )
        let mcpServerConfigs: [MCPServerConfig]
        do {
            mcpServerConfigs = try ChatAuxiliaryControlSupport.resolvedMCPServerConfigs(
                controls: controlsToUse,
                supportsMCPToolsControl: threadSupportsPerMessageMCP,
                servers: mcpServers,
                perMessageOverrideServerIDs: perMessageMCPServerIDs
            )
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

        let sessionContext = ChatStreamingOrchestrator.SessionContext(
            conversationID: conversationID,
            threadID: threadID,
            turnID: turnID,
            providerID: providerID,
            providerConfig: providerConfig,
            providerType: providerTypeSnapshot,
            modelID: modelID,
            modelNameSnapshot: modelNameSnapshot,
            resolvedModelSettings: resolvedModelSettingsSnapshot,
            messageSnapshots: messageSnapshots,
            systemPrompt: systemPrompt,
            controlsToUse: controlsToUse,
            shouldTruncateMessages: shouldTruncateMessages,
            maxHistoryMessages: maxHistoryMessages,
            modelContextWindow: modelContextWindow,
            reservedOutputTokens: reservedOutputTokens,
            mcpServerConfigs: mcpServerConfigs,
            chatNamingTarget: chatNamingTarget,
            shouldOfferBuiltinSearch: shouldOfferBuiltinSearch,
            triggeredByUserSend: triggeredByUserSend,
            networkLogContext: networkLogContext
        )

        let sessionCallbacks = ChatStreamingOrchestrator.SessionCallbacks(
            persistAssistantMessage: { [self] message, providerID, modelID, modelName, threadID, turnID, metrics in
                do {
                    let entity = try MessageEntity.fromDomain(message)
                    entity.generatedProviderID = providerID
                    entity.generatedModelID = modelID
                    entity.generatedModelName = modelName
                    entity.contextThreadID = threadID
                    entity.turnID = turnID
                    entity.responseMetrics = metrics
                    entity.conversation = conversationEntity
                    conversationEntity.messages.append(entity)
                    conversationEntity.updatedAt = Date()
                    rebuildMessageCaches()
                    autoOpenLatestArtifactIfNeeded(from: message, threadID: threadID)
                    try? modelContext.save()
                    return entity.id
                } catch {
                    errorMessage = error.localizedDescription
                    showingError = true
                    return nil
                }
            },
            persistToolMessage: { [self] message, threadID, turnID in
                do {
                    let entity = try MessageEntity.fromDomain(message)
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
            },
            persistCodexThreadState: { [self] state, localThreadID in
                persistCodexThreadState(state, forLocalThreadID: localThreadID)
            },
            appendCodexInteraction: { [self] request, localThreadID in
                pendingCodexInteractions.append(PendingCodexInteraction(localThreadID: localThreadID, request: request))
            },
            mergeSearchActivities: { [self] messageID, activities in
                mergeSearchActivitiesIntoAssistantMessage(messageID: messageID, newActivities: activities)
            },
            mergeAgentToolActivities: { [self] messageID, activities in
                mergeAgentToolActivitiesIntoAssistantMessage(messageID: messageID, newActivities: activities)
            },
            maybeAutoRename: { [self] provider, targetModelID, history, assistantMessage in
                await maybeAutoRenameConversation(
                    targetProvider: provider,
                    targetModelID: targetModelID,
                    history: history,
                    finalAssistantMessage: assistantMessage
                )
            },
            appendAgentApproval: { [self] request, localThreadID in
                pendingAgentApprovals.append(PendingAgentApproval(localThreadID: localThreadID, request: request))
            },
            showError: { [self] message in
                errorMessage = message
                showingError = true
            },
            endStreamingSession: { [self] in
                streamingStore.endSession(conversationID: conversationID, threadID: threadID)
            },
            onSessionEnd: { [self] shouldNotify, preview, sessionThreadID in
                if shouldNotify {
                    responseCompletionNotifier.notifyCompletionIfNeeded(
                        conversationID: conversationID,
                        conversationTitle: conversationEntity.title,
                        replyPreview: preview
                    )
                }
                streamingStore.endSession(conversationID: conversationID, threadID: threadID)
                pendingCodexInteractions.removeAll { $0.localThreadID == sessionThreadID }
                pendingAgentApprovals.removeAll { $0.localThreadID == sessionThreadID }
            }
        )

        let task = Task.detached(priority: .userInitiated) {
            await ChatStreamingOrchestrator.run(
                context: sessionContext,
                streamingState: streamingState,
                callbacks: sessionCallbacks
            )
        }
        streamingStore.attachTask(task, conversationID: conversationID, threadID: threadID)
    }

    private static func resolvedAgentModeControls(active: Bool) -> AgentModeControls? {
        guard active, AppPreferences.isPluginEnabled("agent_mode") else { return nil }
        let defaults = UserDefaults.standard
        let workingDir = defaults.string(forKey: AppPreferenceKeys.agentModeWorkingDirectory) ?? ""
        let customPrefixesJSON = defaults.string(forKey: AppPreferenceKeys.agentModeAllowedCommandPrefixesJSON) ?? "[]"
        let customPrefixes = (try? JSONDecoder().decode([String].self, from: Data(customPrefixesJSON.utf8))) ?? []
        let safePrefixes = AgentCommandAllowlist.resolvedSafePrefixes(defaults: defaults)
        let prefixes = safePrefixes + customPrefixes
        let timeout = defaults.object(forKey: AppPreferenceKeys.agentModeCommandTimeoutSeconds) as? Int ?? 120
        let autoApproveReads = defaults.object(forKey: AppPreferenceKeys.agentModeAutoApproveFileReads) as? Bool ?? true
        let bypassPermissions = defaults.object(forKey: AppPreferenceKeys.agentModeBypassPermissions) as? Bool ?? false
        let tools = AgentEnabledTools(
            shellExecute: defaults.object(forKey: AppPreferenceKeys.agentModeToolShell) as? Bool ?? true,
            fileRead: defaults.object(forKey: AppPreferenceKeys.agentModeToolFileRead) as? Bool ?? true,
            fileWrite: defaults.object(forKey: AppPreferenceKeys.agentModeToolFileWrite) as? Bool ?? true,
            fileEdit: defaults.object(forKey: AppPreferenceKeys.agentModeToolFileEdit) as? Bool ?? true,
            globSearch: defaults.object(forKey: AppPreferenceKeys.agentModeToolGlob) as? Bool ?? true,
            grepSearch: defaults.object(forKey: AppPreferenceKeys.agentModeToolGrep) as? Bool ?? true
        )
        return AgentModeControls(
            enabled: true,
            workingDirectory: workingDir.isEmpty ? nil : workingDir,
            allowedCommandPrefixes: prefixes,
            autoApproveFileReads: autoApproveReads,
            bypassPermissions: bypassPermissions,
            enabledTools: tools,
            commandTimeoutSeconds: timeout,
            maxOutputBytes: 102_400
        )
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
        ChatMessagePreparationSupport.fallbackTitleFromMessage(message)
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

        var byID: OrderedDictionary<String, SearchActivity> = [:]

        for activity in existingActivities {
            byID[activity.id] = activity
        }

        for activity in newActivities {
            if let existing = byID[activity.id] {
                byID[activity.id] = existing.merged(with: activity)
            } else {
                byID[activity.id] = activity
            }
        }

        let mergedActivities = Array(byID.values)
        entity.searchActivitiesData = mergedActivities.isEmpty ? nil : (try? encoder.encode(mergedActivities))
        conversationEntity.updatedAt = Date()
        rebuildMessageCaches()
        try? modelContext.save()
    }

    private func mergeAgentToolActivitiesIntoAssistantMessage(
        messageID: UUID,
        newActivities: [CodexToolActivity]
    ) {
        guard !newActivities.isEmpty else { return }
        guard let entity = conversationEntity.messages.first(where: { $0.id == messageID && $0.role == "assistant" }) else {
            return
        }

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        let existingActivities: [CodexToolActivity]
        if let data = entity.agentToolActivitiesData,
           let decoded = try? decoder.decode([CodexToolActivity].self, from: data) {
            existingActivities = decoded
        } else {
            existingActivities = []
        }

        var byID: OrderedDictionary<String, CodexToolActivity> = [:]
        for activity in existingActivities {
            byID[activity.id] = activity
        }
        for activity in newActivities {
            if let existing = byID[activity.id] {
                byID[activity.id] = existing.merged(with: activity)
            } else {
                byID[activity.id] = activity
            }
        }

        let mergedActivities = Array(byID.values)
        entity.agentToolActivitiesData = mergedActivities.isEmpty ? nil : (try? encoder.encode(mergedActivities))
        conversationEntity.updatedAt = Date()
        rebuildMessageCaches()
        try? modelContext.save()
    }

    // MARK: - Slash Command MCP

    private var slashCommandMCPItems: [SlashCommandMCPServerItem] {
        eligibleMCPServers.map { server in
            SlashCommandMCPServerItem(
                id: server.id,
                name: server.name,
                isSelected: perMessageMCPServerIDs.contains(server.id)
            )
        }
    }

    private var perMessageMCPChips: [SlashCommandMCPServerItem] {
        let eligible = Set(eligibleMCPServers.map(\.id))
        return perMessageMCPServerIDs
            .filter { eligible.contains($0) }
            .compactMap { id in
                eligibleMCPServers.first { $0.id == id }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { SlashCommandMCPServerItem(id: $0.id, name: $0.name, isSelected: true) }
    }

    private func updateSlashCommandState(for text: String, target: SlashCommandTarget) {
        guard supportsMCPToolsControl, !eligibleMCPServers.isEmpty else {
            if isSlashMCPPopoverVisible {
                isSlashMCPPopoverVisible = false
            }
            return
        }

        if let filter = SlashCommandDetection.detectFilter(in: text) {
            slashMCPFilterText = filter
            slashCommandTarget = target
            if !isSlashMCPPopoverVisible {
                slashMCPHighlightedIndex = 0
                isSlashMCPPopoverVisible = true
            }
            let count = SlashCommandDetection.filteredCount(
                servers: slashCommandMCPItems,
                filterText: filter
            )
            if count > 0, slashMCPHighlightedIndex >= count {
                slashMCPHighlightedIndex = count - 1
            }
        } else if isSlashMCPPopoverVisible, slashCommandTarget == target {
            isSlashMCPPopoverVisible = false
            slashMCPFilterText = ""
            slashMCPHighlightedIndex = 0
        }
    }

    private func handleSlashCommandSelectServer(_ serverID: String) {
        if perMessageMCPServerIDs.contains(serverID) {
            perMessageMCPServerIDs.remove(serverID)
        } else {
            perMessageMCPServerIDs.insert(serverID)
        }

        switch slashCommandTarget {
        case .composer:
            messageText = SlashCommandDetection.removeSlashToken(from: messageText)
        case .editMessage:
            editingUserMessageText = SlashCommandDetection.removeSlashToken(from: editingUserMessageText)
        }
        isSlashMCPPopoverVisible = false
        slashMCPFilterText = ""
        slashMCPHighlightedIndex = 0
    }

    private func removePerMessageMCPServer(_ serverID: String) {
        perMessageMCPServerIDs.remove(serverID)
    }

    private func dismissSlashCommandPopover() {
        switch slashCommandTarget {
        case .composer:
            messageText = SlashCommandDetection.removeSlashToken(from: messageText)
        case .editMessage:
            editingUserMessageText = SlashCommandDetection.removeSlashToken(from: editingUserMessageText)
        }
        isSlashMCPPopoverVisible = false
        slashMCPFilterText = ""
        slashMCPHighlightedIndex = 0
    }

    private func handleSlashCommandKeyDown(_ keyCode: UInt16) -> Bool {
        let items = slashCommandMCPItems
        let count = SlashCommandDetection.filteredCount(
            servers: items,
            filterText: slashMCPFilterText
        )
        guard count > 0 else {
            if keyCode == 53 {
                dismissSlashCommandPopover()
                return true
            }
            return false
        }

        switch keyCode {
        case 126:
            slashMCPHighlightedIndex = max(0, slashMCPHighlightedIndex - 1)
            return true
        case 125:
            slashMCPHighlightedIndex = min(count - 1, slashMCPHighlightedIndex + 1)
            return true
        case 36, 76, 48:
            if let serverID = SlashCommandDetection.highlightedServerID(
                servers: items,
                filterText: slashMCPFilterText,
                highlightedIndex: slashMCPHighlightedIndex
            ) {
                handleSlashCommandSelectServer(serverID)
            }
            return true
        case 53:
            dismissSlashCommandPopover()
            return true
        default:
            return false
        }
    }
}
