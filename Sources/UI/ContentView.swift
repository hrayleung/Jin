import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var streamingStore: ConversationStreamingStore
    @EnvironmentObject var shortcutsStore: AppShortcutsStore
    @EnvironmentObject var shortcutHintController: ShortcutHintController
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
    /// Batch delete. Titles are snapshotted alongside the entities so the
    /// confirmation dialog never reads a property off a model the confirm
    /// action already deleted.
    @State var conversationsPendingBatchDeletion: [ConversationEntity] = []
    @State var conversationsPendingBatchDeletionTitles: [String] = []
    @State var showingDeleteConversationsConfirmation = false
    /// Explicit multi-select mode for the chats list. The selected set itself
    /// lives in `ChatsSidebarSectionView` so ⌘-clicking a row doesn't
    /// re-evaluate `ChatView`.
    @State var isChatSelectionModeActive = false
    @State var conversationPendingRename: ConversationEntity?
    @State var showingRenameConversationAlert = false
    @State var renameConversationDraftTitle = ""
    @State var titleRegenerationErrorMessage = ""
    @State var showingTitleRegenerationError = false
    @State var regeneratingConversationID: UUID?
    @State private var mainWindowChromeLayout = MainWindowChromeLayout.zero
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @AppStorage("assistantSidebarLayout") var assistantSidebarLayoutRaw = AssistantSidebarLayout.grid.rawValue
    @AppStorage("assistantSidebarSort") var assistantSidebarSortRaw = AssistantSidebarSort.custom.rawValue
    @AppStorage("assistantSidebarShowName") var assistantSidebarShowName = true
    @AppStorage("assistantSidebarShowIcon") var assistantSidebarShowIcon = true
    @AppStorage("assistantSidebarGridColumns") var assistantSidebarGridColumns = 3
    @AppStorage(AppPreferenceKeys.mainSidebarWidth) private var persistedSidebarWidth = Double(SidebarWidthPersistence.defaultWidth)
    @AppStorage(AppPreferenceKeys.showShortcutHints) private var showShortcutHints = true
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
            .background {
                ShortcutHintHostWindowReader { window in
                    shortcutHintController.registerHostWindow(window)
                }
            }
            .onAppear {
                shortcutHintController.isEnabled = showShortcutHints
            }
            .onChange(of: showShortcutHints) { _, enabled in
                shortcutHintController.isEnabled = enabled
            }
    }

    /// macOS 26 (Tahoe) renders this as a floating Liquid Glass sidebar
    /// automatically. macOS 14/15 fall back to the system's standard sidebar
    /// material. Chat actions (model picker / star / inspector / trash) live
    /// in `ChatView`'s `.toolbar`. The system `.sidebarToggle` is removed
    /// and replaced with one `MainSidebarToggleButton` on the sidebar column
    /// only. Do not also attach that item to the detail column: when the
    /// sidebar hides, SwiftUI migrates the sidebar toolbar into the remaining
    /// title bar, and a second copy would sit beside it in the same glass
    /// capsule.
    private var rootSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } detail: {
            detailContent
                .modifier(JinDetailBackgroundExtension())
                .toolbar {
                    preTahoeCollapsedSidebarToggle
                }
                .toolbar(removing: .sidebarToggle)
                .isolatedFromSidebarColumnAnimation(columnVisibility)
        }
        // No .navigationSplitViewStyle — let the system pick. On Tahoe
        // .balanced explicitly biases toward inset-floating sidebar; omitting
        // it gives the OS the option to render whichever style fits the OS.
    }

    private var sidebarColumn: some View {
        let width = MainSidebarVisibility.columnWidth(
            isVisible: isSidebarVisible,
            persistedWidth: persistedSidebarWidth
        )
        return sidebarContent
            .navigationSplitViewColumnWidth(
                min: width.min,
                ideal: width.ideal,
                max: width.max
            )
            // Must attach to the column, not the NavigationSplitView —
            // applied on the split view it silently no-ops.
            .toolbar {
                sidebarToggleToolbarItem
            }
            // `removing` must come after `.toolbar { }` or a later toolbar
            // pass can reinstall the stock `.sidebarToggle`.
            .toolbar(removing: .sidebarToggle)
            .isolatedFromSidebarColumnAnimation(columnVisibility)
    }

    @ToolbarContentBuilder
    private var sidebarToggleToolbarItem: some ToolbarContent {
        ToolbarItem(id: "jin.mainSidebarToggle", placement: .navigation) {
            MainSidebarToggleButton(
                isSidebarVisible: isSidebarVisible,
                action: toggleSidebarVisibility
            )
        }
    }

    /// macOS 14/15 tear down sidebar-column toolbar items with the column.
    /// Tahoe migrates that item into the remaining title bar, so a detail
    /// copy there becomes the second glass button.
    @ToolbarContentBuilder
    private var preTahoeCollapsedSidebarToggle: some ToolbarContent {
        if !isSidebarVisible, !MainSidebarVisibility.sidebarToolbarMigratesWhenCollapsed {
            sidebarToggleToolbarItem
        }
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
                isSelectionModeActive: $isChatSelectionModeActive,
                onSelectConversation: selectConversation,
                onToggleStar: toggleConversationStar,
                onRename: requestRenameConversation,
                onRegenerateTitle: { conversation in
                    Task { await regenerateConversationTitle(conversation) }
                },
                onDelete: requestDeleteConversation,
                onDeleteAtOffsets: deleteConversations,
                onDeleteConversations: requestDeleteConversations,
                onSetStarred: setConversationsStarred
            )
        }
        // No custom sidebar background. NavigationSplitView renders the
        // system sidebar material (Liquid Glass on macOS 26, `.sidebar`
        // material on 14/15) and `NSApp.appearance` (set in JinApp +
        // JinAppDelegate from `appAppearanceMode`) makes both the sidebar
        // and the title bar above it render with the user's chosen
        // appearance — eliminating both the focus-dim discontinuity and
        // the light-content / dark-title-bar mismatch. Adding any custom
        // NSVisualEffectView here re-introduces material mismatches with
        // Tahoe's separate Liquid Glass toolbar layer above the sidebar.
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
            isChatSelectionModeActive: $isChatSelectionModeActive,
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
                    onNewChat: createNewConversation,
                    titlebarLeadingInset: mainWindowChromeLayout.titlebarLeadingInset,
                    mainWindowIsFullScreen: mainWindowChromeLayout.isFullScreen
                )
                .id(conversation.id)
                .background(JinSemanticColor.detailSurface)
                .environmentObject(ttsPlaybackManager)
            } else {
                ContentViewEmptyDetailView(
                    onNewChat: createNewConversation
                )
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

    // MARK: - Navigation

    var isSidebarVisible: Bool {
        MainSidebarVisibility.isVisible(columnVisibility)
    }

    func toggleSidebarVisibility() {
        applySidebarVisibility(MainSidebarVisibility.toggled(columnVisibility))
    }

    func focusChatSearch() {
        let shouldDelayFocus = !isSidebarVisible
        let shouldSnap = MainSidebarSplitSupport.shouldSnapColumnChange(
            reduceMotion: accessibilityReduceMotion,
            hasOpenConversation: selectedConversation != nil
        )
        if shouldDelayFocus {
            applySidebarVisibility(MainSidebarVisibility.splitVisibility(isVisible: true))
        }
        Task { @MainActor in
            if shouldDelayFocus, !shouldSnap {
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
            isSidebarSearchFieldFocused = true
        }
    }

    /// Toggling selection mode while the sidebar is collapsed would do nothing
    /// visible, so reveal it first — same reasoning as `focusChatSearch`.
    func toggleChatSelectionMode() {
        let willActivate = !isChatSelectionModeActive
        if willActivate, !isSidebarVisible {
            applySidebarVisibility(MainSidebarVisibility.splitVisibility(isVisible: true))
        }
        isChatSelectionModeActive = willActivate
    }

    private func applySidebarVisibility(_ visibility: NavigationSplitViewVisibility) {
        guard columnVisibility != visibility else { return }

        // Drive the SwiftUI binding only. `NSSplitViewController.toggleSidebar`
        // can report success on macOS 26 without collapsing Tahoe's floating
        // sidebar or writing `columnVisibility`.
        let shouldSnap = MainSidebarSplitSupport.shouldSnapColumnChange(
            reduceMotion: accessibilityReduceMotion,
            hasOpenConversation: selectedConversation != nil
        )

        if shouldSnap {
            withTransaction(MainSidebarSplitSupport.suppressedAnimationTransaction) {
                columnVisibility = visibility
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            columnVisibility = visibility
        }
    }

    func openAssistantSettings() {
        isAssistantInspectorPresented = true
    }

    func navigateToConversation(_ conversationID: UUID) {
        guard let conversation = fetchPersistedConversation(id: conversationID) else { return }
        selectConversation(conversation)
    }

}
