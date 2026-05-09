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
    static let smartLongChatCollapseThreshold = 48
    static let smartLongChatExpandedTailCount = 8
    static let contextUsageRefreshDelay = Duration.milliseconds(180)

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
    @Environment(\.accessibilityReduceMotion) var accessibilityReduceMotion
    @EnvironmentObject var streamingStore: ConversationStreamingStore
    @EnvironmentObject var responseCompletionNotifier: ResponseCompletionNotifier
    @EnvironmentObject var shortcutsStore: AppShortcutsStore
    @Bindable var conversationEntity: ConversationEntity
    let onRequestDeleteConversation: () -> Void
    @Binding var isAssistantInspectorPresented: Bool
    var onPersistConversationIfNeeded: () -> Void = {}
    var isSidebarHidden: Bool = false
    var mainSidebarWidth: CGFloat = SidebarWidthPersistence.defaultWidth
    var onToggleSidebar: (() -> Void)? = nil
    var onNewChat: (() -> Void)? = nil
    var titlebarLeadingInset: CGFloat = 0
    var mainWindowIsFullScreen = false
    @Query var providers: [ProviderConfigEntity]
    @Query var mcpServers: [MCPServerConfigEntity]

    @AppStorage(AppPreferenceKeys.sendWithCommandEnter) var sendWithCommandEnter = false
    @AppStorage(AppPreferenceKeys.sttAddRecordingAsFile) var sttAddRecordingAsFile = false

    // MARK: - State Properties

    @State var controls: GenerationControls = GenerationControls()
    @State var messageText = ""
    @State var remoteVideoInputURLText = ""
    @State var draftAttachments: [DraftAttachment] = []
    // swiftlint:disable:next private_swiftui_state
    @State var draftQuotes: [DraftQuote] = []
    @State var currentContextUsageEstimate: ChatContextUsageEstimate?
    @State var contextUsageRefreshTask: Task<Void, Never>?
    @State var contextUsageRefreshGeneration: UInt = 0
    // swiftlint:disable:next private_swiftui_state
    @State var draftContextUsageRefreshTask: Task<Void, Never>?
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
    // swiftlint:disable:next private_swiftui_state
    @State var expandedCollapsedMessageIDs: Set<UUID> = []

    // Cache expensive derived data so typing/streaming doesn't repeatedly sort/decode the entire history.
    @StateObject var renderCache = ChatRenderCacheController()
    @State var isArtifactPaneVisible = false
    @State var selectedArtifactIDByThreadID: [UUID: String] = [:]
    @State var selectedArtifactVersionByThreadID: [UUID: Int] = [:]
    @ObservedObject var favoriteModelsStore = FavoriteModelsStore.shared

    @State var errorMessage: String?
    @State var showingError = false
    @State var showingThinkingBudgetSheet = false
    @State var thinkingBudgetDraft = ""
    @State var maxTokensDraft = ""
    // swiftlint:disable:next private_swiftui_state
    @State var anthropicThinkingDisplayDraft: AnthropicThinkingDisplay = .summarized
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
    @State var showingClaudeManagedAgentSessionSettingsSheet = false
    @State var claudeManagedAgentIDDraft = ""
    @State var claudeManagedEnvironmentIDDraft = ""
    @State var claudeManagedAgentDisplayNameDraft = ""
    @State var claudeManagedEnvironmentDisplayNameDraft = ""
    @State var claudeManagedAgentSettingsDraftError: String?
    @State var claudeManagedAvailableAgents: [ClaudeManagedAgentDescriptor] = []
    @State var claudeManagedAvailableEnvironments: [ClaudeManagedEnvironmentDescriptor] = []
    @State var isRefreshingClaudeManagedSessionResources = false
    @State var claudeManagedProviderDefaultAgentID = ""
    @State var claudeManagedProviderDefaultEnvironmentID = ""
    @State var claudeManagedProviderDefaultAgentDisplayName = ""
    @State var claudeManagedProviderDefaultEnvironmentDisplayName = ""
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
    // Accessed from ChatView extensions in separate files.
    // swiftlint:disable private_swiftui_state
    @State var showingOpenAIImageCustomSizeSheet = false
    @State var openAIImageCustomSizeTargetThreadID: UUID?
    @State var openAIImageCustomSizeTargetModelID = ""
    // swiftlint:enable private_swiftui_state
    @State var imageGenerationDraft = ImageGenerationControls()
    @State var imageGenerationSeedDraft = ""
    @State var imageGenerationCompressionQualityDraft = ""
    @State var imageGenerationDraftError: String?
    // Accessed from ChatView extensions in separate files.
    // swiftlint:disable private_swiftui_state
    @State var mistralOCRConfigured = false
    @State var mineruOCRConfigured = false
    @State var deepSeekOCRConfigured = false
    @State var openRouterOCRConfigured = false
    @State var firecrawlOCRConfigured = false
    @State var textToSpeechConfigured = false
    @State var speechToTextConfigured = false
    @State var mistralOCRPluginEnabled = true
    @State var mineruOCRPluginEnabled = true
    @State var deepSeekOCRPluginEnabled = true
    @State var openRouterOCRPluginEnabled = true
    @State var firecrawlOCRPluginEnabled = true
    @State var textToSpeechPluginEnabled = true
    @State var speechToTextPluginEnabled = true
    @State var webSearchPluginEnabled = true
    @State var webSearchPluginConfigured = false
    // swiftlint:enable private_swiftui_state
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
        guard let activeThreadID = activeModelThread?.id else { return nil }
        return streamingStore.streamingState(conversationID: conversationEntity.id, threadID: activeThreadID)
    }

    var streamingModelLabel: String? {
        guard let activeThreadID = activeModelThread?.id else { return nil }
        return streamingStore.streamingModelLabel(conversationID: conversationEntity.id, threadID: activeThreadID)
    }

    func streamingMessage(for threadID: UUID) -> StreamingMessageState? {
        streamingStore.streamingState(conversationID: conversationEntity.id, threadID: threadID)
    }

    func streamingModelLabel(for threadID: UUID) -> String? {
        streamingStore.streamingModelLabel(conversationID: conversationEntity.id, threadID: threadID)
    }

    func streamingModelID(for threadID: UUID) -> String? {
        streamingStore.streamingModelID(conversationID: conversationEntity.id, threadID: threadID)
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

    /// Threads that render as their own panel in the stage. A thread becomes
    /// a panel only after it has received messages — toggling a tab as a
    /// next-send recipient no longer summons an empty column. See
    /// `ChatThreadSupport.panelThreads(...)` for fallback semantics.
    var panelThreads: [ConversationModelThreadEntity] {
        ChatThreadSupport.panelThreads(
            from: sortedModelThreads,
            allMessages: conversationEntity.messages,
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
            preferredID: conversationEntity.activeThreadID
        )
    }

    /// Provider ID of the active thread, or "" if no thread is set up yet.
    /// Replaces the now-deprecated `conversationEntity.providerID` snapshot.
    var activeProviderID: String {
        activeModelThread?.providerID ?? ""
    }

    /// Model ID of the active thread, or "" if no thread is set up yet.
    /// Replaces the now-deprecated `conversationEntity.modelID` snapshot.
    var activeModelID: String {
        activeModelThread?.modelID ?? ""
    }

    /// Encoded `GenerationControls` of the active thread, or empty data if
    /// no thread exists. Replaces the now-deprecated
    /// `conversationEntity.modelConfigData` snapshot.
    var activeModelConfigData: Data {
        activeModelThread?.modelConfigData ?? Data()
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
        chatPresentations(chatLifecycle(chatRootContent))
    }

    var chatRootContent: some View {
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
    }
}
