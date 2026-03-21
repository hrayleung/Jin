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

    enum PrepareToSendCancellationReason {
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

    var activeAgentApprovalBinding: Binding<PendingAgentApproval?> {
        Binding(
            get: { pendingAgentApprovals.first },
            set: { newValue in
                guard newValue == nil, !pendingAgentApprovals.isEmpty else { return }
                _ = pendingAgentApprovals.popFirst()
            }
        )
    }

    var activeCodexInteractionBinding: Binding<PendingCodexInteraction?> {
        Binding(
            get: { pendingCodexInteractions.first },
            set: { newValue in
                guard newValue == nil, !pendingCodexInteractions.isEmpty else { return }
                _ = pendingCodexInteractions.popFirst()
            }
        )
    }

    // MARK: - Environment & Injected Dependencies

    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var streamingStore: ConversationStreamingStore
    @EnvironmentObject var responseCompletionNotifier: ResponseCompletionNotifier
    @EnvironmentObject var shortcutsStore: AppShortcutsStore
    @Bindable var conversationEntity: ConversationEntity
    let onRequestDeleteConversation: () -> Void
    @Binding var isAssistantInspectorPresented: Bool
    var onPersistConversationIfNeeded: () -> Void = {}
    var isSidebarHidden: Bool = false
    var onToggleSidebar: (() -> Void)? = nil
    var onNewChat: (() -> Void)? = nil
    @Query var providers: [ProviderConfigEntity]
    @Query var mcpServers: [MCPServerConfigEntity]

    @AppStorage(AppPreferenceKeys.sendWithCommandEnter) var sendWithCommandEnter = false
    @AppStorage(AppPreferenceKeys.sttAddRecordingAsFile) var sttAddRecordingAsFile = false

    // MARK: - State Properties

    @State var controls: GenerationControls = GenerationControls()
    @State var messageText = ""
    @State var remoteVideoInputURLText = ""
    @State var draftAttachments: [DraftAttachment] = []
    @State var isFileImporterPresented = false
    @State var isComposerDropTargeted = false
    @State var isFullPageDropTargeted = false
    @State var dropAttachmentImportInFlightCount = 0
    @State var dropForwarderRef = DropForwarderRef()
    @State var isComposerFocused = false
    @State var editingUserMessageID: UUID?
    @State var editingUserMessageText = ""
    @State var isEditingUserMessageFocused = false
    @State var composerHeight: CGFloat = 0
    @State var composerTextContentHeight: CGFloat = 36
    @State var isModelPickerPresented = false
    @State var isAddModelPickerPresented = false
    @State var messageRenderLimit: Int = Self.initialMessageRenderLimit
    @State var pendingRestoreScrollMessageID: UUID?
    @State var isPinnedToBottom = true
    @State var pinnedBottomRefreshGeneration = 0
    @State var isExpandedComposerPresented = false
    @State var isComposerHidden = false
    @State var activeThreadID: UUID?

    // Cache expensive derived data so typing/streaming doesn't repeatedly sort/decode the entire history.
    @State var cachedVisibleMessages: [MessageRenderItem] = []
    @State var cachedMessagesVersion: Int = 0
    @State var cachedMessageEntitiesByID: [UUID: MessageEntity] = [:]
    @State var cachedToolResultsByCallID: [String: ToolResult] = [:]
    @State var cachedArtifactCatalog: ArtifactCatalog = .empty
    @State var lastCacheRebuildMessageCount: Int = 0
    @State var lastCacheRebuildUpdatedAt: Date = .distantPast
    @State var updatedAtDebounceTask: Task<Void, Never>?
    @State var renderContextBuildTask: Task<Void, Never>?
    @State var renderContextDecodeTask: Task<ChatDecodedRenderContext, Never>?
    @State var activeRenderContextBuildToken = UUID()
    @State var isArtifactPaneVisible = false
    @State var selectedArtifactIDByThreadID: [UUID: String] = [:]
    @State var selectedArtifactVersionByThreadID: [UUID: Int] = [:]
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

    enum SlashCommandTarget { case composer, editMessage }
    @State var isSlashMCPPopoverVisible = false
    @State var slashMCPFilterText = ""
    @State var slashMCPHighlightedIndex = 0
    @State var slashCommandTarget: SlashCommandTarget = .composer
    @State var perMessageMCPServerIDs: Set<String> = []

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
    @State var isAgentModePopoverPresented = false
    @State var isPreparingToSend = false
    @State var prepareToSendStatus: String?
    @State var prepareToSendTask: Task<Void, Never>?
    @State var prepareToSendCancellationReason: PrepareToSendCancellationReason?
    @EnvironmentObject var ttsPlaybackManager: TextToSpeechPlaybackManager
    @StateObject var speechToTextManager = SpeechToTextManager()

    let conversationTitleGenerator = ConversationTitleGenerator()

    // MARK: - Bridging Computed Properties

    var isStreaming: Bool {
        streamingStore.isStreaming(conversationID: conversationEntity.id)
    }

    var isBusy: Bool {
        isStreaming || isPreparingToSend
    }

    var isImportingDropAttachments: Bool {
        dropAttachmentImportInFlightCount > 0
    }

    var streamingMessage: StreamingMessageState? {
        guard let activeThreadID else { return nil }
        return streamingStore.streamingState(conversationID: conversationEntity.id, threadID: activeThreadID)
    }

    var streamingModelLabel: String? {
        guard let activeThreadID else { return nil }
        return streamingStore.streamingModelLabel(conversationID: conversationEntity.id, threadID: activeThreadID)
    }

    func streamingMessage(for threadID: UUID) -> StreamingMessageState? {
        streamingStore.streamingState(conversationID: conversationEntity.id, threadID: threadID)
    }

    func streamingModelLabel(for threadID: UUID) -> String? {
        streamingStore.streamingModelLabel(conversationID: conversationEntity.id, threadID: threadID)
    }

    var sortedModelThreads: [ConversationModelThreadEntity] {
        ChatThreadSupport.sortedThreads(in: conversationEntity.modelThreads)
    }

    var selectedModelThreads: [ConversationModelThreadEntity] {
        ChatThreadSupport.selectedThreads(
            from: sortedModelThreads,
            activeThread: activeModelThread
        )
    }

    var secondaryToolbarThreads: [ConversationModelThreadEntity] {
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

    var googleMapsLocationBiasValue: GoogleMapsLocationBias? {
        guard let lat = controls.googleMaps?.latitude,
              let lng = controls.googleMaps?.longitude else {
            return nil
        }
        return GoogleMapsLocationBias(latitude: lat, longitude: lng)
    }

    // MARK: - Body

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
}
