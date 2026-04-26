import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

enum AssistantSidebarLayout: String {
    case list
    case grid
    case dropdown
}

enum AssistantSidebarSort: String, CaseIterable {
    case custom
    case name
    case recent

    var label: String {
        switch self {
        case .custom: return "Custom"
        case .name: return "Name"
        case .recent: return "Recent"
        }
    }
}

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

    private var sidebarSearchFieldIsActive: Bool {
        isSidebarSearchFieldFocused || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
        rootSplitView
            .mainWindowToolbarChromeCompat(chromeLayout: $mainWindowChromeLayout)
            .task {
                bootstrapDefaultProvidersIfNeeded()
                bootstrapDefaultAssistantsIfNeeded()
                await updateManager.checkForUpdatesOnLaunchIfNeeded()
            }
            .sheet(isPresented: $isAssistantInspectorPresented) {
                if let selectedAssistant {
                    AssistantInspectorView(assistant: selectedAssistant)
                }
            }
            .confirmationDialog(
                "Delete assistant?",
                isPresented: $showingDeleteAssistantConfirmation,
                presenting: assistantPendingDeletion
            ) { assistant in
                Button("Delete", role: .destructive) { deleteAssistant(assistant) }
            } message: { assistant in
                Text("This will permanently delete \u{201C}\(assistant.displayName)\u{201D} and all of its chats.")
            }
            .confirmationDialog(
                "Delete chat?",
                isPresented: $showingDeleteConversationConfirmation,
                presenting: conversationPendingDeletion
            ) { conversation in
                Button("Delete", role: .destructive) { deleteConversation(conversation) }
            } message: { conversation in
                Text("This will permanently delete \u{201C}\(conversation.title)\u{201D}.")
            }
            .alert("Rename Chat", isPresented: $showingRenameConversationAlert, presenting: conversationPendingRename) { _ in
                TextField("Chat title", text: $renameConversationDraftTitle)
                Button("Cancel", role: .cancel) { conversationPendingRename = nil }
                Button("Save") { applyManualConversationRename() }
                    .disabled(renameConversationDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: { _ in
                Text("Enter a new title for this chat.")
            }
            .alert("Title Regeneration Failed", isPresented: $showingTitleRegenerationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(titleRegenerationErrorMessage)
            }
            .focusedSceneValue(
                \.workspaceActions,
                WorkspaceFocusedActions(
                    isSidebarVisible: isSidebarVisible,
                    canRenameSelectedChat: selectedConversation != nil,
                    canToggleSelectedChatStar: selectedConversation != nil,
                    canDeleteSelectedChat: selectedConversation != nil,
                    selectedChatIsStarred: selectedConversation?.isStarred == true,
                    toggleSidebar: toggleSidebarVisibility,
                    focusChatSearch: focusChatSearch,
                    createNewChat: createNewConversation,
                    createAssistant: createAssistant,
                    openAssistantSettings: openAssistantSettings,
                    renameSelectedChat: requestRenameSelectedConversation,
                    toggleSelectedChatStar: toggleSelectedConversationStar,
                    deleteSelectedChat: requestDeleteSelectedConversation
                )
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
        ZStack(alignment: .trailing) {
            sidebarPane
                .frame(
                    minWidth: resolvedSidebarWidth,
                    idealWidth: resolvedSidebarWidth,
                    maxWidth: resolvedSidebarWidth,
                    maxHeight: .infinity
                )
                .clipped()
                .shadow(color: .black.opacity(isSidebarVisible ? 0.12 : 0), radius: 14, x: 4, y: 0)

            sidebarResizeHandle
                .offset(x: 4)
                .opacity(isSidebarVisible ? 1 : 0)
        }
        .frame(
            minWidth: resolvedSidebarWidth,
            idealWidth: resolvedSidebarWidth,
            maxWidth: resolvedSidebarWidth,
            maxHeight: .infinity
        )
        .offset(x: isSidebarVisible ? 0 : -resolvedSidebarWidth)
        .allowsHitTesting(isSidebarVisible)
        .zIndex(2)
    }

    private var sidebarResizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let startWidth = sidebarResizeStartWidth ?? resolvedSidebarWidth
                        sidebarResizeStartWidth = startWidth
                        let nextWidth = SidebarWidthPersistence.clamped(startWidth + value.translation.width)
                        guard abs(nextWidth - resolvedSidebarWidth) > 0.5 else { return }
                        sidebarLiveResizeWidth = nextWidth
                    }
                    .onEnded { _ in
                        if let sidebarLiveResizeWidth {
                            persistedSidebarWidth = Double(sidebarLiveResizeWidth)
                        }
                        sidebarResizeStartWidth = nil
                        sidebarLiveResizeWidth = nil
                    }
            )
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
        VStack(spacing: 0) {
            SidebarHeaderView(
                assistantDisplayName: selectedAssistant?.displayName ?? "Default",
                extendsContentIntoTitlebar: mainWindowChromeLayout.extendsContentIntoTitlebar,
                titlebarLeadingInset: mainWindowChromeLayout.titlebarLeadingInset,
                titlebarTopInset: mainWindowChromeLayout.titlebarTopInset,
                onNewChat: createNewConversation,
                onHideSidebar: toggleSidebarVisibility,
                shortcutsStore: shortcutsStore
            )

            sidebarSearchField
        }
        .padding(.bottom, JinSpacing.small)
        .background(JinSemanticColor.sidebarSurface)
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [
                    JinSemanticColor.separator.opacity(0.08),
                    .clear
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 10)
            .allowsHitTesting(false)
        }
    }

    private var sidebarSearchField: some View {
        HStack(spacing: JinSpacing.xSmall) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(text: $searchText, prompt: Text("Search chats")) {
                EmptyView()
            }
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .focused($isSidebarSearchFieldFocused)
            .accessibilityLabel("Search chats")
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small + 2)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(
                    sidebarSearchFieldIsActive
                        ? JinSemanticColor.surface
                        : JinSemanticColor.surface.opacity(0.9)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(
                    sidebarSearchFieldIsActive
                        ? JinSemanticColor.separator.opacity(0.28)
                        : JinSemanticColor.separator.opacity(0.16),
                    lineWidth: JinStrokeWidth.hairline
                )
        }
        .padding(.horizontal, JinSpacing.medium)
        .animation(.easeInOut(duration: 0.12), value: sidebarSearchFieldIsActive)
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
                    emptyDetailHeaderBar
                    noConversationSelectedView
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
            if miniPlayerEnabled,
               ttsPlaybackManager.state != .idle,
               let ctx = ttsPlaybackManager.playbackContext {
                TTSMiniPlayerView(
                    manager: ttsPlaybackManager,
                    onNavigate: ctx.conversationID == selectedConversation?.id
                        ? nil
                        : { conversationID in
                            if let conv = conversations.first(where: { $0.id == conversationID }) {
                                selectConversation(conv)
                            }
                        }
                )
                .frame(width: TTSMiniPlayerMetrics.width, height: TTSMiniPlayerMetrics.height)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, TTSMiniPlayerMetrics.topOffset)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.92, anchor: .top)
                            .combined(with: .opacity)
                            .combined(with: .offset(y: -8)),
                        removal: .scale(scale: 0.96, anchor: .top)
                            .combined(with: .opacity)
                    )
                )
                .zIndex(1)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: miniPlayerEnabled && ttsPlaybackManager.state != .idle)
    }

    private var emptyDetailHeaderBar: some View {
        HStack(spacing: JinSpacing.small) {
            if !isSidebarVisible {
                Button(action: toggleSidebarVisibility) {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
                }
                .buttonStyle(JinIconButtonStyle(showBackground: false))
                .help("Show Sidebar")

                Button(action: createNewConversation) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
                }
                .buttonStyle(JinIconButtonStyle(showBackground: false))
                .help("New Chat")
            }

            Spacer(minLength: 0)

            Button(action: openAssistantSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
            }
            .buttonStyle(JinIconButtonStyle())
            .help("Assistant Settings")
            .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .openAssistantSettings))
        }
        .padding(.leading, detailHeaderLeadingPadding)
        .padding(.trailing, JinSpacing.medium)
        .padding(.top, JinSpacing.small)
        .padding(.bottom, JinSpacing.small)
        .frame(minHeight: 38)
        .background(JinSemanticColor.detailSurface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(JinSemanticColor.separator.opacity(0.45))
                .frame(height: JinStrokeWidth.hairline)
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

    // MARK: - Empty State

    private var noConversationSelectedView: some View {
        GeometryReader { geometry in
            let visibleWidth = ChatConversationLayoutMetrics.visibleContainerWidth(
                containerWidth: geometry.size.width,
                sidebarWidth: sidebarWidthForDetailLayout,
                isSidebarHidden: !isSidebarVisible
            )
            let offset = ChatConversationLayoutMetrics.sidebarCompensationOffset(
                sidebarWidth: sidebarWidthForDetailLayout,
                isSidebarHidden: !isSidebarVisible,
                compensationRatio: sidebarCompensationRatio
            )

            VStack(spacing: JinSpacing.large) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.tertiary)

                VStack(spacing: JinSpacing.xSmall + 2) {
                    Text("No Conversation Selected")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Pick a conversation from the sidebar, or start a new one.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                Button("New Chat") {
                    createNewConversation()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, JinSpacing.xLarge)
            .frame(width: visibleWidth, height: geometry.size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: offset)
        }
    }

    private var sidebarCompensationRatio: CGFloat {
        mainWindowChromeLayout.isFullScreen
            ? ChatConversationLayoutMetrics.fullScreenSidebarCompensationRatio
            : ChatConversationLayoutMetrics.standardSidebarCompensationRatio
    }
}
