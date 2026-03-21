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
    @State var columnVisibility: NavigationSplitViewVisibility = .all
    @State var didBootstrapDefaults = false
    @State var didBootstrapAssistants = false
    @State var searchText = ""
    @State var searchCache = ConversationSearchCache()
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
    @AppStorage("assistantSidebarLayout") var assistantSidebarLayoutRaw = AssistantSidebarLayout.grid.rawValue
    @AppStorage("assistantSidebarSort") var assistantSidebarSortRaw = AssistantSidebarSort.custom.rawValue
    @AppStorage("assistantSidebarShowName") var assistantSidebarShowName = true
    @AppStorage("assistantSidebarShowIcon") var assistantSidebarShowIcon = true
    @AppStorage("assistantSidebarGridColumns") var assistantSidebarGridColumns = 3
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
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
        } detail: {
            detailContent
        }
        .toolbar(removing: .sidebarToggle)
        .hideWindowToolbarCompat()
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

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            SidebarHeaderView(
                assistantDisplayName: selectedAssistant?.displayName ?? "Default",
                onNewChat: createNewConversation,
                onHideSidebar: toggleSidebarVisibility,
                shortcutsStore: shortcutsStore
            )

            HStack(spacing: JinSpacing.xSmall) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField(text: $searchText, prompt: Text("Search chats")) {
                    EmptyView()
                }
                .textFieldStyle(.plain)
                .focused($isSidebarSearchFieldFocused)
                .accessibilityLabel("Search chats")
            }
            .padding(.horizontal, JinSpacing.medium)
            .padding(.vertical, JinSpacing.small)
            .background(
                RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)
                    .fill(JinSemanticColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)
                    .stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: JinStrokeWidth.hairline)
            )
            .padding(.horizontal, JinSpacing.medium)
            .padding(.top, JinSpacing.small)
            .padding(.bottom, JinSpacing.small)

            List(selection: conversationListSelectionBinding) {
                assistantsSection
                chatsSection
            }
            .listStyle(.sidebar)
            .contentMargins(.vertical, 0, for: .scrollContent)
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        .scrollContentBackground(.hidden)
        .background {
            JinSemanticColor.sidebarSurface.ignoresSafeArea()
        }
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
                    onToggleSidebar: toggleSidebarVisibility,
                    onNewChat: createNewConversation
                )
                .id(conversation.id)
                .background(JinSemanticColor.detailSurface)
                .environmentObject(ttsPlaybackManager)
            } else {
                noConversationSelectedView
                    .overlay(alignment: .topLeading) {
                        if !isSidebarVisible {
                            HStack(spacing: JinSpacing.small) {
                                Button(action: toggleSidebarVisibility) {
                                    Image(systemName: "sidebar.leading")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)
                                .help("Show Sidebar")

                                Button(action: createNewConversation) {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)
                                .help("New Chat")
                            }
                            .padding(JinSpacing.medium)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Button(action: openAssistantSettings) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Assistant Settings")
                        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .openAssistantSettings))
                        .padding(JinSpacing.medium)
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

    // MARK: - Navigation

    var isSidebarVisible: Bool {
        columnVisibility != .detailOnly
    }

    func toggleSidebarVisibility() {
        withAnimation(.easeInOut(duration: 0.16)) {
            columnVisibility = isSidebarVisible ? .detailOnly : .all
        }
    }

    func focusChatSearch() {
        if !isSidebarVisible {
            columnVisibility = .all
        }
        DispatchQueue.main.async {
            isSidebarSearchFieldFocused = true
        }
    }

    func openAssistantSettings() {
        isAssistantInspectorPresented = true
    }

    // MARK: - Empty State

    private var noConversationSelectedView: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
