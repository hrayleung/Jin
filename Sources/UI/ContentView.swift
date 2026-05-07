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
    @Query(sort: \ConversationEntity.updatedAt, order: .reverse) var conversations: [ConversationEntity]
    @Query var providers: [ProviderConfigEntity]

    @StateObject private var ttsPlaybackManager = TextToSpeechPlaybackManager()
    @AppStorage(AppPreferenceKeys.ttsMiniPlayerEnabled) private var miniPlayerEnabled = true

    @State var selectedAssistant: AssistantEntity?
    @State var selectedConversation: ConversationEntity?
    @State private var isSidebarPresented = MainSidebarVisibility.defaultIsVisible
    @State var didBootstrapDefaults = false
    @State var didBootstrapAssistants = false
    @State var searchText = ""
    @State var searchCache = ConversationSearchCache()
    @State var isAssistantInspectorPresented = false
    @State private var sidebarResizeStartWidth: CGFloat?
    @State private var sidebarLiveResizeWidth: CGFloat?
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

    private var resolvedSidebarWidth: CGFloat {
        if let sidebarLiveResizeWidth {
            return SidebarWidthPersistence.clamped(sidebarLiveResizeWidth)
        }

        return SidebarWidthPersistence.resolvedWidth(from: persistedSidebarWidth)
    }

    private var sidebarWidthForDetailLayout: CGFloat {
        isSidebarVisible ? resolvedSidebarWidth : 0
    }

    var body: some View {
        contentPresentations(
            rootSplitView
                .mainWindowToolbarChromeCompat(chromeLayout: $mainWindowChromeLayout)
        )
    }

    private var rootSplitView: some View {
        ZStack(alignment: .leading) {
            detailContent
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)

            sidebarOverlayPane
        }
        .clipped()
        .animation(.easeInOut(duration: 0.24), value: isSidebarVisible)
        .ignoresSafeArea(
            .container,
            edges: mainWindowChromeLayout.extendsContentIntoTitlebar ? .top : []
        )
    }

    // MARK: - Sidebar

    private var sidebarPane: some View {
        sidebarContent
    }

    private var sidebarOverlayPane: some View {
        ContentViewSidebarOverlayPane(
            width: resolvedSidebarWidth,
            isVisible: isSidebarVisible,
            onResizeChanged: updateSidebarResize,
            onResizeEnded: persistSidebarResize
        ) {
            sidebarPane
        }
    }

    private func updateSidebarResize(translationWidth: CGFloat) {
        let startWidth = sidebarResizeStartWidth ?? resolvedSidebarWidth
        sidebarResizeStartWidth = startWidth
        let nextWidth = SidebarWidthPersistence.clamped(startWidth + translationWidth)
        guard abs(nextWidth - resolvedSidebarWidth) > 0.5 else { return }
        sidebarLiveResizeWidth = nextWidth
    }

    private func persistSidebarResize() {
        if let sidebarLiveResizeWidth {
            persistedSidebarWidth = Double(sidebarLiveResizeWidth)
        }
        sidebarResizeStartWidth = nil
        sidebarLiveResizeWidth = nil
    }

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            sidebarPinnedChrome

            List(selection: conversationListSelectionBinding) {
                assistantsSection
                chatsSection
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .listStyle(.plain)
            .contentMargins(.vertical, 0, for: .scrollContent)
            .overlayScrollerStyle()
            .scrollContentBackground(.hidden)
        }
        .background {
            JinSemanticColor.sidebarSurface.ignoresSafeArea()
        }
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
                    mainSidebarWidth: sidebarWidthForDetailLayout,
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
                        sidebarWidth: sidebarWidthForDetailLayout,
                        isSidebarHidden: !isSidebarVisible,
                        compensationRatio: sidebarCompensationRatio,
                        onNewChat: createNewConversation
                    )
                }
                    .background(JinSemanticColor.detailSurface)
            }
        }
        .background { JinSemanticColor.detailSurface.ignoresSafeArea() }
        .overlay(alignment: .leading) {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.1), location: 0),
                    .init(color: .black.opacity(0.04), location: 0.35),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 20)
            .allowsHitTesting(false)
        }
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
        isSidebarPresented
    }

    func toggleSidebarVisibility() {
        isSidebarPresented = MainSidebarVisibility.toggled(isSidebarPresented)
    }

    func focusChatSearch() {
        let shouldDelayFocus = !isSidebarVisible
        if shouldDelayFocus {
            isSidebarPresented = true
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
        guard let conversation = conversations.first(where: { $0.id == conversationID }) else { return }
        selectConversation(conversation)
    }

    // MARK: - Empty State

    private var sidebarCompensationRatio: CGFloat {
        mainWindowChromeLayout.isFullScreen
            ? ChatConversationLayoutMetrics.fullScreenSidebarCompensationRatio
            : ChatConversationLayoutMetrics.standardSidebarCompensationRatio
    }
}
