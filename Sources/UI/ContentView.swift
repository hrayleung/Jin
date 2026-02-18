import SwiftUI
import SwiftData

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
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var streamingStore: ConversationStreamingStore
    @EnvironmentObject private var shortcutsStore: AppShortcutsStore
    @Query(sort: \AssistantEntity.sortOrder, order: .forward) private var assistants: [AssistantEntity]
    @Query(sort: \ConversationEntity.updatedAt, order: .reverse) private var conversations: [ConversationEntity]
    @Query private var providers: [ProviderConfigEntity]

    @StateObject private var ttsPlaybackManager = TextToSpeechPlaybackManager()

    @State private var selectedAssistant: AssistantEntity?
    @State private var selectedConversation: ConversationEntity?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var didBootstrapDefaults = false
    @State private var didBootstrapAssistants = false
    @State private var searchText = ""
    @State private var isSidebarSearchPresented = false
    @State private var isAssistantInspectorPresented = false
    @State private var assistantContextMenuTargetID: String?
    @State private var assistantPendingDeletion: AssistantEntity?
    @State private var showingDeleteAssistantConfirmation = false
    @State private var conversationPendingDeletion: ConversationEntity?
    @State private var showingDeleteConversationConfirmation = false
    @State private var conversationPendingRename: ConversationEntity?
    @State private var showingRenameConversationAlert = false
    @State private var renameConversationDraftTitle = ""
    @State private var titleRegenerationErrorMessage = ""
    @State private var showingTitleRegenerationError = false
    @State private var regeneratingConversationID: UUID?
    @AppStorage("assistantSidebarLayout") private var assistantSidebarLayoutRaw = AssistantSidebarLayout.grid.rawValue
    @AppStorage("assistantSidebarSort") private var assistantSidebarSortRaw = AssistantSidebarSort.custom.rawValue
    @AppStorage("assistantSidebarShowName") private var assistantSidebarShowName = true
    @AppStorage("assistantSidebarShowIcon") private var assistantSidebarShowIcon = true
    @AppStorage("assistantSidebarGridColumns") private var assistantSidebarGridColumns = 3
    @AppStorage(AppPreferenceKeys.newChatModelMode) private var newChatModelMode: NewChatModelMode = .lastUsed
    @AppStorage(AppPreferenceKeys.newChatFixedProviderID) private var newChatFixedProviderID = "openai"
    @AppStorage(AppPreferenceKeys.newChatFixedModelID) private var newChatFixedModelID = "gpt-5.2"
    @AppStorage(AppPreferenceKeys.newChatMCPMode) private var newChatMCPMode: NewChatMCPMode = .lastUsed
    @AppStorage(AppPreferenceKeys.newChatFixedMCPEnabled) private var newChatFixedMCPEnabled = true
    @AppStorage(AppPreferenceKeys.newChatFixedMCPUseAllServers) private var newChatFixedMCPUseAllServers = true
    @AppStorage(AppPreferenceKeys.newChatFixedMCPServerIDsJSON) private var newChatFixedMCPServerIDsJSON = "[]"

    private let conversationTitleGenerator = ConversationTitleGenerator()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedConversation) {
                assistantsSection
                chatsSection
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, isPresented: $isSidebarSearchPresented, placement: .sidebar, prompt: "Search chats")
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
            .navigationTitle("Chats")
            .navigationSubtitle(selectedAssistant?.displayName ?? "Default")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: createNewConversation) {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                    .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .newChat))

                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .keyboardShortcut(",", modifiers: [.command])
                }
            }
            .scrollContentBackground(.hidden)
            .background(JinSemanticColor.sidebarSurface)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(JinSemanticColor.separator.opacity(0.45))
                    .frame(width: JinStrokeWidth.hairline)
            }
        } detail: {
            VStack(spacing: 0) {
                if ttsPlaybackManager.state != .idle,
                   let ctx = ttsPlaybackManager.playbackContext,
                   ctx.conversationID != selectedConversation?.id {
                    TTSMiniPlayerView(
                        manager: ttsPlaybackManager,
                        onNavigate: { conversationID in
                            if let conv = conversations.first(where: { $0.id == conversationID }) {
                                selectedConversation = conv
                            }
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let conversation = selectedConversation {
                    ChatView(
                        conversationEntity: conversation,
                        onRequestDeleteConversation: {
                            requestDeleteConversation(conversation)
                        },
                        isAssistantInspectorPresented: $isAssistantInspectorPresented,
                        onPersistConversationIfNeeded: {
                            persistConversationIfNeeded(conversation)
                        }
                    )
                        .id(conversation.id)
                        .background(JinSemanticColor.detailSurface)
                        .environmentObject(ttsPlaybackManager)
                } else {
                    noConversationSelectedView
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                openAssistantSettings()
                            } label: {
                                Label("Assistant Settings", systemImage: "slider.horizontal.3")
                            }
                            .help("Assistant Settings")
                            .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .openAssistantSettings))
                        }
                    }
                    .background(JinSemanticColor.detailSurface)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: ttsPlaybackManager.state != .idle)
        }
        .task {
            bootstrapDefaultProvidersIfNeeded()
            bootstrapDefaultAssistantsIfNeeded()
        }
        .sheet(isPresented: $isAssistantInspectorPresented) {
            if let selectedAssistant {
                AssistantInspectorView(
                    assistant: selectedAssistant
                )
            }
        }
        .confirmationDialog(
            "Delete assistant?",
            isPresented: $showingDeleteAssistantConfirmation,
            presenting: assistantPendingDeletion
        ) { assistant in
            Button("Delete", role: .destructive) {
                deleteAssistant(assistant)
            }
        } message: { assistant in
            Text("This will permanently delete “\(assistant.displayName)” and all of its chats.")
        }
        .confirmationDialog(
            "Delete chat?",
            isPresented: $showingDeleteConversationConfirmation,
            presenting: conversationPendingDeletion
        ) { conversation in
            Button("Delete", role: .destructive) {
                deleteConversation(conversation)
            }
        } message: { conversation in
            Text("This will permanently delete “\(conversation.title)”.")
        }
        .alert("Rename Chat", isPresented: $showingRenameConversationAlert, presenting: conversationPendingRename) { _ in
            TextField("Chat title", text: $renameConversationDraftTitle)
            Button("Cancel", role: .cancel) {
                conversationPendingRename = nil
            }
            Button("Save") {
                applyManualConversationRename()
            }
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

    // MARK: - Helpers

    private var isSidebarVisible: Bool {
        columnVisibility != .detailOnly
    }

    private func toggleSidebarVisibility() {
        withAnimation(.easeInOut(duration: 0.16)) {
            columnVisibility = isSidebarVisible ? .detailOnly : .all
        }
    }

    private func focusChatSearch() {
        if !isSidebarVisible {
            columnVisibility = .all
        }
        isSidebarSearchPresented = true
    }

    private func openAssistantSettings() {
        isAssistantInspectorPresented = true
    }

    private func requestRenameSelectedConversation() {
        guard let selectedConversation else { return }
        requestRenameConversation(selectedConversation)
    }

    private func toggleSelectedConversationStar() {
        guard let selectedConversation else { return }
        toggleConversationStar(selectedConversation)
    }

    private func requestDeleteSelectedConversation() {
        guard let selectedConversation else { return }
        requestDeleteConversation(selectedConversation)
    }

    private var assistantSidebarLayout: AssistantSidebarLayout {
        AssistantSidebarLayout(rawValue: assistantSidebarLayoutRaw) ?? .grid
    }

    private var assistantSidebarSort: AssistantSidebarSort {
        AssistantSidebarSort(rawValue: assistantSidebarSortRaw) ?? .custom
    }

    private var assistantSidebarGridColumnCount: Int {
        max(1, min(assistantSidebarGridColumns, 4))
    }

    private var assistantSidebarEffectiveShowName: Bool {
        assistantSidebarShowName
    }

    private var assistantSidebarEffectiveShowIcon: Bool {
        assistantSidebarShowIcon || !assistantSidebarShowName
    }

    private var displayedAssistants: [AssistantEntity] {
        switch assistantSidebarSort {
        case .custom:
            return assistants
        case .name:
            return assistants.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .recent:
            let lastConversationByAssistantID = Dictionary(grouping: conversations.filter { !$0.messages.isEmpty }) { conversation in
                conversation.assistant?.id ?? "default"
            }
            .mapValues { conversations in
                conversations.map(\.updatedAt).max() ?? Date.distantPast
            }

            return assistants.sorted { lhs, rhs in
                let lhsDate = lastConversationByAssistantID[lhs.id] ?? Date.distantPast
                let rhsDate = lastConversationByAssistantID[rhs.id] ?? Date.distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.sortOrder < rhs.sortOrder
            }
        }
    }

    private var selectedAssistantIDBinding: Binding<String> {
        Binding(
            get: {
                selectedAssistant?.id
                    ?? assistants.first(where: { $0.id == "default" })?.id
                    ?? assistants.first?.id
                    ?? "default"
            },
            set: { newValue in
                guard let assistant = assistants.first(where: { $0.id == newValue }) else { return }
                selectAssistant(assistant)
            }
        )
    }

    private var assistantSidebarGridColumnsBinding: Binding<Int> {
        Binding(
            get: { assistantSidebarGridColumnCount },
            set: { newValue in
                assistantSidebarLayoutRaw = AssistantSidebarLayout.grid.rawValue
                assistantSidebarGridColumns = newValue
            }
        )
    }

    private var assistantSidebarUsesDropdownBinding: Binding<Bool> {
        Binding(
            get: { assistantSidebarLayout == .dropdown },
            set: { newValue in
                assistantSidebarLayoutRaw = newValue
                    ? AssistantSidebarLayout.dropdown.rawValue
                    : AssistantSidebarLayout.grid.rawValue
            }
        )
    }

    private var assistantSidebarSortBinding: Binding<AssistantSidebarSort> {
        Binding(
            get: { assistantSidebarSort },
            set: { newValue in
                assistantSidebarSortRaw = newValue.rawValue
            }
        )
    }

    private var groupedConversations: [(key: String, value: [ConversationEntity])] {
        ConversationGrouping.groupedConversations(filteredConversations)
    }

    private func deleteConversations(at offsets: IndexSet, in sourceList: [ConversationEntity]) {
        for index in offsets {
            let conversation = sourceList[index]
            streamingStore.cancel(conversationID: conversation.id)
            streamingStore.endSession(conversationID: conversation.id)
            modelContext.delete(conversation)
            if selectedConversation == conversation {
                selectedConversation = nil
            }
        }
    }

    private func isPersistedConversation(_ conversation: ConversationEntity) -> Bool {
        conversation.modelContext != nil
    }

    @discardableResult
    private func discardSelectedEmptyConversationIfNeeded() -> UUID? {
        guard let conversation = selectedConversation, conversation.messages.isEmpty else {
            return nil
        }

        let conversationID = conversation.id
        streamingStore.cancel(conversationID: conversationID)
        streamingStore.endSession(conversationID: conversationID)

        if isPersistedConversation(conversation) {
            modelContext.delete(conversation)
        }

        if conversationPendingDeletion == conversation {
            conversationPendingDeletion = nil
            showingDeleteConversationConfirmation = false
        }

        if conversationPendingRename == conversation {
            conversationPendingRename = nil
            showingRenameConversationAlert = false
            renameConversationDraftTitle = ""
        }

        if regeneratingConversationID == conversationID {
            regeneratingConversationID = nil
        }

        selectedConversation = nil
        return conversationID
    }

    private func persistConversationIfNeeded(_ conversation: ConversationEntity) {
        guard !isPersistedConversation(conversation) else { return }
        modelContext.insert(conversation)
    }

    private func createNewConversation() {
        bootstrapDefaultProvidersIfNeeded()
        bootstrapDefaultAssistantsIfNeeded()

        let discardedConversationID = discardSelectedEmptyConversationIfNeeded()

        guard let assistant = selectedAssistant ?? assistants.first(where: { $0.id == "default" }) ?? assistants.first else {
            return
        }

        let lastConversation: ConversationEntity?
        if let selectedConversation, selectedConversation.id != discardedConversationID {
            lastConversation = selectedConversation
        } else {
            lastConversation = conversations.first { conversation in
                conversation.id != discardedConversationID && !conversation.messages.isEmpty
            }
        }

        var providerID: String
        var modelID: String

        switch newChatModelMode {
        case .lastUsed:
            let candidateProviderID = lastConversation?.providerID
            let resolvedProviderID = candidateProviderID.flatMap { candidate in
                providers.first(where: { $0.id == candidate })?.id
            }
            providerID = resolvedProviderID
                ?? providers.first(where: { $0.id == "openai" })?.id
                ?? providers.first?.id
                ?? "openai"

            let candidateModelID = lastConversation?.modelID
            let models = modelsForProvider(providerID)
            if let candidateModelID, models.contains(where: { $0.id == candidateModelID }) {
                modelID = candidateModelID
            } else {
                modelID = defaultModelID(for: providerID)
            }

        case .fixed:
            let resolvedProviderID = providers.first(where: { $0.id == newChatFixedProviderID })?.id
            providerID = resolvedProviderID
                ?? providers.first(where: { $0.id == "openai" })?.id
                ?? providers.first?.id
                ?? "openai"

            let models = modelsForProvider(providerID)
            if models.contains(where: { $0.id == newChatFixedModelID }) {
                modelID = newChatFixedModelID
            } else {
                modelID = defaultModelID(for: providerID)
            }
        }

        let inheritedControls = lastConversation.flatMap { conversation in
            try? JSONDecoder().decode(GenerationControls.self, from: conversation.modelConfigData)
        }
        var controls = inheritedControls ?? GenerationControls()
        switch newChatMCPMode {
        case .lastUsed:
            break

        case .fixed:
            guard newChatFixedMCPEnabled else {
                controls.mcpTools = MCPToolsControls(enabled: false, enabledServerIDs: nil)
                break
            }

            if newChatFixedMCPUseAllServers {
                controls.mcpTools = MCPToolsControls(enabled: true, enabledServerIDs: nil)
            } else {
                let ids = AppPreferences.decodeStringArrayJSON(newChatFixedMCPServerIDsJSON)
                controls.mcpTools = MCPToolsControls(enabled: true, enabledServerIDs: ids)
            }
        }

        let controlsData = (try? JSONEncoder().encode(controls)) ?? Data()
        let conversation = ConversationEntity(
            title: "New Chat",
            systemPrompt: nil,
            providerID: providerID,
            modelID: modelID,
            modelConfigData: controlsData,
            assistant: assistant
        )

        selectedConversation = conversation
    }

    private func modelsForProvider(_ providerID: String) -> [ModelInfo] {
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            return []
        }
        return provider.enabledModels
    }

    private func defaultModelID(for providerID: String) -> String {
        let models = modelsForProvider(providerID)
        guard !models.isEmpty else {
            switch providerID {
            case "anthropic":
                return "claude-opus-4-6"
            case "xai":
                return "grok-4-1-fast"
            case "deepseek":
                return "deepseek-chat"
            case "vertexai":
                return "gemini-3-pro-preview"
            default:
                return "gpt-5.2"
            }
        }

        if providerID == "openai", let gpt52 = models.first(where: { $0.id == "gpt-5.2" }) {
            return gpt52.id
        }
        if providerID == "anthropic", let opus46 = models.first(where: { $0.id == "claude-opus-4-6" }) {
            return opus46.id
        }
        if providerID == "anthropic", let sonnet46 = models.first(where: { $0.id == "claude-sonnet-4-6" }) {
            return sonnet46.id
        }
        if providerID == "anthropic", let sonnet45 = models.first(where: { $0.id == "claude-sonnet-4-5-20250929" }) {
            return sonnet45.id
        }
        if providerID == "xai", let grok41Fast = models.first(where: { $0.id == "grok-4-1-fast" }) {
            return grok41Fast.id
        }
        if providerID == "deepseek", let deepseekChat = models.first(where: { $0.id == "deepseek-chat" }) {
            return deepseekChat.id
        }
        if providerID == "vertexai", let gemini3Pro = models.first(where: { $0.id == "gemini-3-pro-preview" }) {
            return gemini3Pro.id
        }
        return models.first?.id ?? (providerID == "anthropic" ? "claude-opus-4-6" : "gpt-5.2")
    }

    private var filteredConversations: [ConversationEntity] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearching = !query.isEmpty

        let baseConversations = conversations.filter { conversation in
            guard !conversation.messages.isEmpty else { return false }
            if isSearching { return true }
            guard let selectedAssistant else { return true }
            return conversation.assistant?.id == selectedAssistant.id
        }

        guard isSearching else { return baseConversations }

        let lowered = query.lowercased()
        return baseConversations.filter {
            $0.title.lowercased().contains(lowered)
                || $0.modelID.lowercased().contains(lowered)
                || providerName(for: $0.providerID).lowercased().contains(lowered)
        }
    }

    private func providerName(for providerID: String) -> String {
        providers.first(where: { $0.id == providerID })?.name ?? providerID
    }

    private func providerIconID(for providerID: String) -> String? {
        providers.first(where: { $0.id == providerID })?.resolvedProviderIconID
    }

    private func resolveAssistantForContextMenu() -> AssistantEntity? {
        if let assistantContextMenuTargetID,
           let assistant = assistants.first(where: { $0.id == assistantContextMenuTargetID }) {
            return assistant
        }

        return selectedAssistant
            ?? assistants.first(where: { $0.id == "default" })
            ?? assistants.first
    }

    private func selectAssistant(_ assistant: AssistantEntity) {
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedAssistant = assistant
            if let selectedConversation, selectedConversation.assistant?.id != assistant.id {
                self.selectedConversation = nil
            }
        }
    }

    private func createAssistant() {
        bootstrapDefaultAssistantsIfNeeded()

        let existingIDs = Set(assistants.map(\.id))
        var counter = 1
        var candidate = "assistant-\(counter)"
        while existingIDs.contains(candidate) {
            counter += 1
            candidate = "assistant-\(counter)"
        }

        let nextSortOrder = (assistants.map(\.sortOrder).max() ?? 0) + 1
        let assistant = AssistantEntity(
            id: candidate,
            name: "New Assistant",
            icon: "sparkles",
            assistantDescription: nil,
            systemInstruction: "",
            temperature: 0.1,
            maxOutputTokens: nil,
            truncateMessages: nil,
            replyLanguage: nil,
            sortOrder: nextSortOrder
        )

        modelContext.insert(assistant)
        selectAssistant(assistant)
        isAssistantInspectorPresented = true
    }

    private func requestDeleteAssistant(_ assistant: AssistantEntity) {
        guard assistants.count > 1 else { return }
        guard assistant.id != "default" else { return }
        assistantPendingDeletion = assistant
        showingDeleteAssistantConfirmation = true
    }

    private func deleteAssistant(_ assistant: AssistantEntity) {
        guard assistant.id != "default" else { return }

        if selectedConversation?.assistant?.id == assistant.id {
            selectedConversation = nil
        }

        if selectedAssistant?.id == assistant.id {
            selectedAssistant = assistants.first(where: { $0.id == "default" && $0.id != assistant.id })
                ?? assistants.first(where: { $0.id != assistant.id })
        }

        modelContext.delete(assistant)
        try? modelContext.save()
        assistantPendingDeletion = nil
    }

    private func requestDeleteConversation(_ conversation: ConversationEntity) {
        conversationPendingDeletion = conversation
        showingDeleteConversationConfirmation = true
    }

    private func requestRenameConversation(_ conversation: ConversationEntity) {
        conversationPendingRename = conversation
        renameConversationDraftTitle = conversation.title
        showingRenameConversationAlert = true
    }

    private func toggleConversationStar(_ conversation: ConversationEntity) {
        conversation.isStarred = !(conversation.isStarred == true)
        try? modelContext.save()
    }

    private func applyManualConversationRename() {
        guard let conversation = conversationPendingRename else { return }
        let trimmed = renameConversationDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        conversation.title = trimmed
        try? modelContext.save()
        conversationPendingRename = nil
        showingRenameConversationAlert = false
    }

    private func deleteConversation(_ conversation: ConversationEntity) {
        streamingStore.cancel(conversationID: conversation.id)
        streamingStore.endSession(conversationID: conversation.id)
        if isPersistedConversation(conversation) {
            modelContext.delete(conversation)
        }
        if selectedConversation == conversation {
            selectedConversation = nil
        }
        conversationPendingDeletion = nil
    }

    private func resolvedChatNamingTargetForRegeneration() -> (provider: ProviderConfig, modelID: String)? {
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

    private func latestMessagesForTitleRegeneration(in conversation: ConversationEntity) -> [Message] {
        let history = conversation.messages
            .sorted(by: { $0.timestamp < $1.timestamp })
            .compactMap { try? $0.toDomain() }

        guard !history.isEmpty else { return [] }

        if let assistantIndex = history.lastIndex(where: { $0.role == .assistant }) {
            let latestAssistant = history[assistantIndex]
            let prior = history[..<assistantIndex]
            if let latestUserBeforeAssistant = prior.last(where: { $0.role == .user }) {
                return [latestUserBeforeAssistant, latestAssistant]
            }
            return [latestAssistant]
        }

        if let latestUser = history.last(where: { $0.role == .user }) {
            return [latestUser]
        }

        return []
    }

    @MainActor
    private func regenerateConversationTitle(_ conversation: ConversationEntity) async {
        guard regeneratingConversationID != conversation.id else { return }

        guard let target = resolvedChatNamingTargetForRegeneration() else {
            titleRegenerationErrorMessage = "Please choose a provider/model in Settings → Plugins → Chat Naming first."
            showingTitleRegenerationError = true
            return
        }

        let contextMessages = latestMessagesForTitleRegeneration(in: conversation)
        guard !contextMessages.isEmpty else {
            titleRegenerationErrorMessage = "No usable conversation messages found to generate a title."
            showingTitleRegenerationError = true
            return
        }

        regeneratingConversationID = conversation.id
        defer { regeneratingConversationID = nil }

        do {
            let title = try await conversationTitleGenerator.generateTitle(
                providerConfig: target.provider,
                modelID: target.modelID,
                contextMessages: contextMessages,
                maxCharacters: 40
            )
            let normalized = ConversationTitleGenerator.normalizeTitle(title, maxCharacters: 40)
            guard !normalized.isEmpty else {
                throw LLMError.decodingError(message: "Generated empty title.")
            }

            conversation.title = normalized
        } catch {
            titleRegenerationErrorMessage = error.localizedDescription
            showingTitleRegenerationError = true
        }
    }

    @ViewBuilder
    private func assistantContextMenu(for assistant: AssistantEntity) -> some View {
        Button {
            selectAssistant(assistant)
            isAssistantInspectorPresented = true
        } label: {
            Label("Assistant Settings", systemImage: "slider.horizontal.3")
        }

        Divider()

        Button(role: .destructive) {
            selectAssistant(assistant)
            requestDeleteAssistant(assistant)
        } label: {
            Label("Delete “\(assistant.displayName)”", systemImage: "trash")
        }
        .disabled(assistant.id == "default" || assistants.count <= 1)
    }

    @MainActor
    private func bootstrapDefaultProvidersIfNeeded() {
        guard !didBootstrapDefaults else { return }
        didBootstrapDefaults = true

        let descriptor = FetchDescriptor<ProviderConfigEntity>()
        guard let persistedProviders = try? modelContext.fetch(descriptor) else {
            return
        }

        var didUpdateProviderIcon = false

        for provider in persistedProviders {
            let current = provider.iconID?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard current == nil || current?.isEmpty == true else { continue }
            guard let providerType = ProviderType(rawValue: provider.typeRaw) else { continue }
            provider.iconID = LobeProviderIconCatalog.defaultIconID(for: providerType)
            didUpdateProviderIcon = true
        }

        if didUpdateProviderIcon {
            try? modelContext.save()
        }

        // Seed defaults only for a fresh install.
        guard persistedProviders.isEmpty else { return }

        for config in DefaultProviderSeeds.allProviders() {
            if let entity = try? ProviderConfigEntity.fromDomain(config) {
                modelContext.insert(entity)
            }
        }

        try? modelContext.save()
    }

    @MainActor
    private func bootstrapDefaultAssistantsIfNeeded() {
        guard !didBootstrapAssistants else { return }
        didBootstrapAssistants = true

        let defaultAssistant: AssistantEntity
        if let existing = assistants.first(where: { $0.id == "default" }) {
            defaultAssistant = existing
        } else {
            let created = AssistantEntity(
                id: "default",
                name: "Default",
                icon: "laptopcomputer",
                assistantDescription: "General-purpose assistant.",
                systemInstruction: "",
                temperature: 0.1,
                maxOutputTokens: nil,
                truncateMessages: nil,
                replyLanguage: nil,
                sortOrder: 0
            )
            modelContext.insert(created)
            defaultAssistant = created
        }

        if selectedAssistant == nil {
            selectedAssistant = defaultAssistant
        }

        for conversation in conversations where conversation.assistant == nil {
            conversation.assistant = defaultAssistant
        }
    }
}

// MARK: - Sidebar Sections

extension ContentView {
    var conversationCountsByAssistantID: [String: Int] {
        Dictionary(grouping: conversations) { conversation in
            conversation.assistant?.id ?? "default"
        }
        .mapValues(\.count)
    }

    @ViewBuilder
    var assistantsSection: some View {
        Section {
            switch assistantSidebarLayout {
            case .dropdown:
                HStack(spacing: 8) {
                    Text("Assistant")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Picker("", selection: selectedAssistantIDBinding) {
                        ForEach(displayedAssistants) { assistant in
                            Text(assistant.displayName).tag(assistant.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .contextMenu {
                        if let assistant = selectedAssistant ?? assistants.first(where: { $0.id == "default" }) {
                            assistantContextMenu(for: assistant)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .contextMenu {
                    if let assistant = selectedAssistant ?? assistants.first(where: { $0.id == "default" }) {
                        assistantContextMenu(for: assistant)
                    }
                }

            case .grid:
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(minimum: 44), spacing: 10),
                        count: assistantSidebarGridColumnCount
                    ),
                    spacing: 10
                ) {
                    ForEach(displayedAssistants) { assistant in
                        let isSelected = selectedAssistant?.id == assistant.id
                        Button {
                            selectAssistant(assistant)
                        } label: {
                            AssistantTileView(
                                assistant: assistant,
                                isSelected: isSelected,
                                showsName: assistantSidebarEffectiveShowName,
                                showsIcon: assistantSidebarEffectiveShowIcon
                            )
                        }
                        .buttonStyle(.plain)
                        .onHover { isHovering in
                            if isHovering {
                                assistantContextMenuTargetID = assistant.id
                            } else if assistantContextMenuTargetID == assistant.id {
                                assistantContextMenuTargetID = nil
                            }
                        }
                    }
                }
                .contextMenu {
                    if let assistant = resolveAssistantForContextMenu() {
                        assistantContextMenu(for: assistant)
                    }
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))

            case .list:
                ForEach(displayedAssistants) { assistant in
                    let isSelected = selectedAssistant?.id == assistant.id
                    Button {
                        selectAssistant(assistant)
                    } label: {
                        AssistantRowView(
                            assistant: assistant,
                            chatCount: conversationCountsByAssistantID[assistant.id, default: 0],
                            isSelected: isSelected
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
                    .contextMenu { assistantContextMenu(for: assistant) }
                }
            }

            Button {
                createAssistant()
            } label: {
                Label("New Assistant", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("New Assistant")
            .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .newAssistant))
        } header: {
            HStack {
                Text("Assistants")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Toggle("Assistant Name", isOn: $assistantSidebarShowName)
                        .disabled(assistantSidebarShowName && !assistantSidebarShowIcon)
                    Toggle("Assistant Icon", isOn: $assistantSidebarShowIcon)
                        .disabled(assistantSidebarShowIcon && !assistantSidebarShowName)

                    Divider()

                    Picker("", selection: assistantSidebarGridColumnsBinding) {
                        Text("1 Column").tag(1)
                        Text("2 Columns").tag(2)
                        Text("3 Columns").tag(3)
                        Text("4 Columns").tag(4)
                    }
                    .labelsHidden()
                    .pickerStyle(.inline)

                    Divider()

                    Toggle("Dropdown View", isOn: assistantSidebarUsesDropdownBinding)

                    Divider()

                    Menu("Sort") {
                        Picker("", selection: assistantSidebarSortBinding) {
                            ForEach(AssistantSidebarSort.allCases, id: \.rawValue) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.inline)
                    }

                    SettingsLink {
                        Text("Settings")
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .help("Assistant view options")
            }
        }
        .onDeleteCommand {
            guard let selectedAssistant else { return }
            requestDeleteAssistant(selectedAssistant)
        }
    }

    @ViewBuilder
    var chatsSection: some View {
        if !filteredConversations.isEmpty {
            ForEach(groupedConversations, id: \.key) { period, convs in
                Section(period) {
                    ForEach(convs) { conversation in
                        let isRegeneratingTitle = regeneratingConversationID == conversation.id
                        let isStarred = conversation.isStarred == true
                        NavigationLink(value: conversation) {
                            ConversationRowView(
                                title: conversation.title,
                                isStarred: isStarred,
                                subtitle: "\(providerName(for: conversation.providerID)) • \(conversation.modelID)",
                                providerIconID: providerIconID(for: conversation.providerID),
                                updatedAt: conversation.updatedAt,
                                isStreaming: streamingStore.isStreaming(conversationID: conversation.id)
                            )
                        }
                        .contextMenu {
                            Button {
                                toggleConversationStar(conversation)
                            } label: {
                                Label(isStarred ? "Unstar Chat" : "Star Chat", systemImage: isStarred ? "star.slash" : "star")
                            }

                            Button {
                                requestRenameConversation(conversation)
                            } label: {
                                Label("Rename Chat", systemImage: "pencil")
                            }

                            Button {
                                Task { await regenerateConversationTitle(conversation) }
                            } label: {
                                Label(isRegeneratingTitle ? "Regenerating Title…" : "Regenerate Title", systemImage: "wand.and.stars")
                            }
                            .disabled(streamingStore.isStreaming(conversationID: conversation.id) || isRegeneratingTitle)

                            Divider()

                            Button(role: .destructive) {
                                requestDeleteConversation(conversation)
                            } label: {
                                Label("Delete Chat", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { indexSet in
                        deleteConversations(at: indexSet, in: convs)
                    }
                }
            }
        } else if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ContentUnavailableView {
                Label("No Conversations", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Start a new chat to begin.")
            }
        }
    }
}
