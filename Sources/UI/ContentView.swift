import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var streamingStore: ConversationStreamingStore
    @EnvironmentObject var shortcutsStore: AppShortcutsStore
    @EnvironmentObject var updateManager: SparkleUpdateManager
    @Query(sort: \AssistantEntity.sortOrder, order: .forward) var assistants: [AssistantEntity]
    @Query var providers: [ProviderConfigEntity]

    @StateObject private var ttsPlaybackManager = TextToSpeechPlaybackManager()
    @AppStorage(AppPreferenceKeys.ttsMiniPlayerEnabled) private var miniPlayerEnabled = true

    @State var selectedAssistant: AssistantEntity?
    @State var selectedConversation: ConversationEntity?
    /// NavigationSplitView-driven sidebar visibility. On macOS 26 (Tahoe) the
    /// system handles the floating Liquid Glass sidebar + slide animation
    /// natively when this binding changes.
    @State private var columnVisibility: NavigationSplitViewVisibility =
        MainSidebarVisibility.defaultIsVisible ? .all : .detailOnly
    @State var didBootstrapDefaults = false
    @State var didBootstrapAssistants = false
    @State var searchText = ""
    @State var isAssistantInspectorPresented = false
    @State var assistantContextMenuTargetID: String?
    @State var assistantPendingDeletion: AssistantEntity?
    @State var showingDeleteAssistantConfirmation = false
    @State var conversationPendingDeletion: ConversationEntity?
    @State var showingDeleteConversationConfirmation = false
    @State var conversationPendingRename: ConversationEntity?
    @State var showingRenameConversationAlert = false
    @State var renameConversationDraftTitle = ""
    @State var titleRegenerationErrorMessage = ""
    @State var showingTitleRegenerationError = false
    @State var regeneratingConversationID: UUID?
    @State private var mainWindowChromeLayout = MainWindowChromeLayout.zero
    @AppStorage("assistantSidebarLayout") var assistantSidebarLayoutRaw = AssistantSidebarLayout.grid.rawValue
    @AppStorage("assistantSidebarSort") var assistantSidebarSortRaw = AssistantSidebarSort.custom.rawValue
    @AppStorage("assistantSidebarShowName") var assistantSidebarShowName = true
    @AppStorage("assistantSidebarShowIcon") var assistantSidebarShowIcon = true
    @AppStorage("assistantSidebarGridColumns") var assistantSidebarGridColumns = 3
    @AppStorage(AppPreferenceKeys.mainSidebarWidth) private var persistedSidebarWidth = Double(SidebarWidthPersistence.defaultWidth)
    @AppStorage(AppPreferenceKeys.newChatModelMode) var newChatModelMode: NewChatModelMode = .lastUsed
    @AppStorage(AppPreferenceKeys.newChatFixedProviderID) var newChatFixedProviderID = "openai"
    @AppStorage(AppPreferenceKeys.newChatFixedModelID) var newChatFixedModelID = "gpt-5.2"
    @AppStorage(AppPreferenceKeys.newChatMCPMode) var newChatMCPMode: NewChatMCPMode = .lastUsed
    @AppStorage(AppPreferenceKeys.newChatFixedMCPEnabled) var newChatFixedMCPEnabled = true
    @AppStorage(AppPreferenceKeys.newChatFixedMCPUseAllServers) var newChatFixedMCPUseAllServers = true
    @AppStorage(AppPreferenceKeys.newChatFixedMCPServerIDsJSON) var newChatFixedMCPServerIDsJSON = "[]"
    @AppStorage("legacyOpenAIMaxOutputMigrationV1") var didRunLegacyOpenAIMaxOutputMigration = false
    @FocusState var isSidebarSearchFieldFocused: Bool
    let conversationTitleGenerator = ConversationTitleGenerator()

    var body: some View {
        contentPresentations(rootSplitView)
    }

    /// macOS 26 (Tahoe) renders this as a floating Liquid Glass sidebar
    /// automatically. macOS 14/15 fall back to the system's standard sidebar
    /// material. We deliberately do NOT use `.toolbar { ... }` here — adding
    /// one creates a unified titlebar strip across the whole window that
    /// reserves space above the floating sidebar and looks orphaned. The
    /// chat action buttons (star / inspector / trash) live inside
    /// `ChatHeaderBarView` so they sit *inside* the detail pane, where they
    /// belong visually.
    private var rootSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationSplitViewColumnWidth(
                    min: CGFloat(SidebarWidthPersistence.minimumWidth),
                    ideal: SidebarWidthPersistence.resolvedWidth(from: persistedSidebarWidth),
                    max: CGFloat(SidebarWidthPersistence.maximumWidth)
                )
        } detail: {
            detailContent
                // Tahoe-only: lets the detail's bg colors mirror into the safe
                // area under the floating sidebar, so the sidebar glass has
                // colour to refract instead of sitting on grey nothing.
                .modifier(JinDetailBackgroundExtension())
        }
        // No .navigationSplitViewStyle — let the system pick. On Tahoe
        // .balanced explicitly biases toward inset-floating sidebar; omitting
        // it gives the OS the option to render whichever style fits the OS.
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            sidebarPinnedChrome

            assistantsArea

            ChatsSidebarSectionView(
                searchText: searchText,
                selectedAssistantID: selectedAssistant?.id,
                regeneratingConversationID: regeneratingConversationID,
                selection: $selectedConversation,
                onSelectConversation: selectConversation,
                onToggleStar: toggleConversationStar,
                onRename: requestRenameConversation,
                onRegenerateTitle: { conversation in
                    Task { await regenerateConversationTitle(conversation) }
                },
                onDelete: requestDeleteConversation,
                onDeleteAtOffsets: deleteConversations
            )
        }
        // No background — NavigationSplitView gives the sidebar its native
        // chrome (Liquid Glass on macOS 26, sidebar material on 14/15).
    }

    private var sidebarPinnedChrome: some View {
        ContentViewSidebarPinnedChromeView(
            assistantDisplayName: selectedAssistant?.displayName ?? "Default",
            extendsContentIntoTitlebar: mainWindowChromeLayout.extendsContentIntoTitlebar,
            titlebarLeadingInset: mainWindowChromeLayout.titlebarLeadingInset,
            titlebarTopInset: mainWindowChromeLayout.titlebarTopInset,
            shortcutsStore: shortcutsStore,
            onNewChat: createNewConversation,
            onHideSidebar: toggleSidebarVisibility,
            searchText: $searchText,
            searchFieldFocus: $isSidebarSearchFieldFocused
        )
    }

    // MARK: - Detail

    private var detailContent: some View {
        VStack(spacing: 0) {
            if let conversation = selectedConversation {
                ChatView(
                    conversationEntity: conversation,
                    onRequestDeleteConversation: { requestDeleteConversation(conversation) },
                    isAssistantInspectorPresented: $isAssistantInspectorPresented,
                    onPersistConversationIfNeeded: { persistConversationIfNeeded(conversation) },
                    isSidebarHidden: !isSidebarVisible,
                    mainSidebarWidth: 0,
                    onToggleSidebar: toggleSidebarVisibility,
                    onNewChat: createNewConversation,
                    titlebarLeadingInset: mainWindowChromeLayout.titlebarLeadingInset,
                    mainWindowIsFullScreen: mainWindowChromeLayout.isFullScreen
                )
                .id(conversation.id)
                .background(JinSemanticColor.detailSurface)
                .environmentObject(ttsPlaybackManager)
            } else {
                VStack(spacing: 0) {
                    ContentViewEmptyDetailHeaderView(
                        isSidebarVisible: isSidebarVisible,
                        leadingPadding: detailHeaderLeadingPadding,
                        assistantSettingsShortcut: shortcutsStore.keyboardShortcut(for: .openAssistantSettings),
                        onToggleSidebar: toggleSidebarVisibility,
                        onNewChat: createNewConversation,
                        onOpenAssistantSettings: openAssistantSettings
                    )
                    ContentViewEmptyDetailView(
                        sidebarWidth: 0,
                        isSidebarHidden: !isSidebarVisible,
                        compensationRatio: sidebarCompensationRatio,
                        onNewChat: createNewConversation
                    )
                }
                    .background(JinSemanticColor.detailSurface)
            }
        }
        .background { JinSemanticColor.detailSurface.ignoresSafeArea() }
        .overlay(alignment: .top) {
            ContentViewTTSMiniPlayerOverlay(
                manager: ttsPlaybackManager,
                isEnabled: miniPlayerEnabled,
                selectedConversationID: selectedConversation?.id,
                onNavigate: navigateToConversation
            )
        }
    }

    private var detailHeaderLeadingPadding: CGFloat {
        mainWindowChromeLayout.leadingPadding(
            baseline: JinSpacing.medium,
            avoidsTitlebarControls: !isSidebarVisible
        )
    }

    // MARK: - Navigation

    var isSidebarVisible: Bool {
        columnVisibility != .detailOnly
    }

    func toggleSidebarVisibility() {
        // No withAnimation — NavigationSplitView owns the animation curve and
        // duration. Overriding with our own causes a double-animation that
        // feels laggy. The system animation on macOS 26 is Liquid Glass-aware.
        columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
    }

    func focusChatSearch() {
        let shouldDelayFocus = !isSidebarVisible
        if shouldDelayFocus {
            columnVisibility = .all
        }
        Task { @MainActor in
            if shouldDelayFocus {
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
            isSidebarSearchFieldFocused = true
        }
    }

    func openAssistantSettings() {
        isAssistantInspectorPresented = true
    }

    func navigateToConversation(_ conversationID: UUID) {
        guard let conversation = fetchPersistedConversation(id: conversationID) else { return }
        selectConversation(conversation)
    }

    // MARK: - Empty State

    private var sidebarCompensationRatio: CGFloat {
        mainWindowChromeLayout.isFullScreen
            ? ChatConversationLayoutMetrics.fullScreenSidebarCompensationRatio
            : ChatConversationLayoutMetrics.standardSidebarCompensationRatio
    }
}
