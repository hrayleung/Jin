import SwiftUI
import SwiftData

private enum AssistantSidebarLayout: String {
    case list
    case grid
    case dropdown
}

private enum AssistantSidebarSort: String, CaseIterable {
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
    @Query(sort: \AssistantEntity.sortOrder, order: .forward) private var assistants: [AssistantEntity]
    @Query(sort: \ConversationEntity.updatedAt, order: .reverse) private var conversations: [ConversationEntity]
    @Query private var providers: [ProviderConfigEntity]

    @State private var selectedAssistant: AssistantEntity?
    @State private var selectedConversation: ConversationEntity?
    @State private var didBootstrapDefaults = false
    @State private var didBootstrapAssistants = false
    @State private var searchText = ""
    @State private var isAssistantInspectorPresented = false
    @State private var assistantPendingDeletion: AssistantEntity?
    @State private var showingDeleteAssistantConfirmation = false
    @State private var conversationPendingDeletion: ConversationEntity?
    @State private var showingDeleteConversationConfirmation = false
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

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedConversation) {
                assistantsSection
                chatsSection
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search chats")
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
            .navigationTitle("Chats")
            .navigationSubtitle(selectedAssistant?.displayName ?? "Default")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: createNewConversation) {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                    .keyboardShortcut("n", modifiers: [.command])

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
            if let conversation = selectedConversation {
                ChatView(
                    conversationEntity: conversation,
                    onRequestDeleteConversation: {
                        requestDeleteConversation(conversation)
                    },
                    isAssistantInspectorPresented: $isAssistantInspectorPresented
                )
                    .id(conversation.id) // Ensure view rebuilds when switching
                    .background(JinSemanticColor.detailSurface)
            } else {
                noConversationSelectedView
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isAssistantInspectorPresented = true
                        } label: {
                            Label("Assistant Settings", systemImage: "slider.horizontal.3")
                        }
                        .help("Assistant Settings")
                        .keyboardShortcut("i", modifiers: [.command])
                    }
                }
                .background(JinSemanticColor.detailSurface)
            }
        }
        .task {
            bootstrapDefaultProvidersIfNeeded()
            bootstrapDefaultAssistantsIfNeeded()
        }
        .sheet(isPresented: $isAssistantInspectorPresented) {
            if let selectedAssistant {
                AssistantInspectorView(
                    assistant: selectedAssistant,
                    onRequestDelete: requestDeleteAssistant
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
            let lastConversationByAssistantID = Dictionary(grouping: conversations) { conversation in
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
            get: { selectedAssistant?.id ?? "default" },
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
        let filtered = filteredConversations
        let grouped = Dictionary(grouping: filtered) { conv in
            relativeDateString(for: conv.updatedAt)
        }
        
        let order = ["Today", "Yesterday", "Previous 7 Days", "Older"]
        return order.compactMap { key in
            guard let values = grouped[key] else { return nil }
            return (key: key, value: values.sorted { $0.updatedAt > $1.updatedAt })
        }
    }

    private func relativeDateString(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()), date > weekAgo {
            return "Previous 7 Days"
        }
        return "Older"
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

    private func createNewConversation() {
        bootstrapDefaultProvidersIfNeeded()
        bootstrapDefaultAssistantsIfNeeded()

        guard let assistant = selectedAssistant ?? assistants.first(where: { $0.id == "default" }) ?? assistants.first else {
            return
        }

        let lastConversation = selectedConversation ?? conversations.first

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

        var controls = GenerationControls()
        switch newChatMCPMode {
        case .lastUsed:
            if let lastConversation,
               let lastControls = try? JSONDecoder().decode(GenerationControls.self, from: lastConversation.modelConfigData) {
                controls.mcpTools = lastControls.mcpTools
            }

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

        modelContext.insert(conversation)
        selectedConversation = conversation
    }

    private func modelsForProvider(_ providerID: String) -> [ModelInfo] {
        guard let provider = providers.first(where: { $0.id == providerID }),
              let models = try? JSONDecoder().decode([ModelInfo].self, from: provider.modelsData) else {
            return []
        }
        return models
    }

    private func defaultModelID(for providerID: String) -> String {
        let models = modelsForProvider(providerID)
        guard !models.isEmpty else {
            switch providerID {
            case "anthropic":
                return "claude-opus-4-6"
            case "xai":
                return "grok-4-1-fast"
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
        if providerID == "anthropic", let sonnet45 = models.first(where: { $0.id == "claude-sonnet-4-5-20250929" }) {
            return sonnet45.id
        }
        if providerID == "xai", let grok41Fast = models.first(where: { $0.id == "grok-4-1-fast" }) {
            return grok41Fast.id
        }
        if providerID == "vertexai", let gemini3Pro = models.first(where: { $0.id == "gemini-3-pro-preview" }) {
            return gemini3Pro.id
        }
        return models.first?.id ?? (providerID == "anthropic" ? "claude-opus-4-6" : "gpt-5.2")
    }

    private var filteredConversations: [ConversationEntity] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistantFiltered = conversations.filter { conversation in
            guard let selectedAssistant else { return true }
            return conversation.assistant?.id == selectedAssistant.id
        }

        guard !query.isEmpty else { return assistantFiltered }

        let lowered = query.lowercased()
        return assistantFiltered.filter {
            $0.title.lowercased().contains(lowered)
                || $0.modelID.lowercased().contains(lowered)
                || providerName(for: $0.providerID).lowercased().contains(lowered)
        }
    }

    private func providerName(for providerID: String) -> String {
        providers.first(where: { $0.id == providerID })?.name ?? providerID
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
        guard assistant.id != "default" else { return }
        assistantPendingDeletion = assistant
        showingDeleteAssistantConfirmation = true
    }

    private func deleteAssistant(_ assistant: AssistantEntity) {
        if selectedConversation?.assistant?.id == assistant.id {
            selectedConversation = nil
        }

        if selectedAssistant?.id == assistant.id {
            selectedAssistant = assistants.first(where: { $0.id == "default" && $0.id != assistant.id })
                ?? assistants.first(where: { $0.id != assistant.id })
        }

        modelContext.delete(assistant)
        assistantPendingDeletion = nil
    }

    private func requestDeleteConversation(_ conversation: ConversationEntity) {
        conversationPendingDeletion = conversation
        showingDeleteConversationConfirmation = true
    }

    private func deleteConversation(_ conversation: ConversationEntity) {
        streamingStore.cancel(conversationID: conversation.id)
        streamingStore.endSession(conversationID: conversation.id)
        modelContext.delete(conversation)
        if selectedConversation == conversation {
            selectedConversation = nil
        }
        conversationPendingDeletion = nil
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
            Label("Delete Assistant", systemImage: "trash")
        }
        .disabled(assistant.id == "default")
    }

    @MainActor
    private func bootstrapDefaultProvidersIfNeeded() {
        guard !didBootstrapDefaults else { return }
        didBootstrapDefaults = true

        guard providers.isEmpty else { return }

        let openAIModels: [ModelInfo] = [
            ModelInfo(
                id: "gpt-5.2",
                name: "GPT-5.2",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning],
                contextWindow: 400000,
                reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            ),
            ModelInfo(
                id: "gpt-5.2-2025-12-11",
                name: "GPT-5.2 (2025-12-11)",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning],
                contextWindow: 400000,
                reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            ),
            ModelInfo(
                id: "gpt-4o",
                name: "GPT-4o",
                capabilities: [.streaming, .toolCalling, .vision],
                contextWindow: 128000,
                reasoningConfig: nil
            )
        ]

        let anthropicModels: [ModelInfo] = [
            ModelInfo(
                id: "claude-opus-4-6",
                name: "Claude Opus 4.6",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
                contextWindow: 200000,
                reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high)
            ),
            ModelInfo(
                id: "claude-opus-4-5-20251101",
                name: "Claude Opus 4.5",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
                contextWindow: 200000,
                reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high)
            ),
            ModelInfo(
                id: "claude-sonnet-4-5-20250929",
                name: "Claude Sonnet 4.5",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
                contextWindow: 200000,
                reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 2048)
            ),
            ModelInfo(
                id: "claude-haiku-4-5-20251001",
                name: "Claude Haiku 4.5",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
                contextWindow: 200000,
                reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 1024)
            )
        ]

        let xAIModels: [ModelInfo] = [
            ModelInfo(
                id: "grok-4-1-fast",
                name: "Grok 4.1 Fast",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning],
                contextWindow: 128000,
                reasoningConfig: nil
            ),
            ModelInfo(
                id: "grok-4-1",
                name: "Grok 4.1",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning],
                contextWindow: 128000,
                reasoningConfig: nil
            )
        ]

        let vertexModels: [ModelInfo] = [
            ModelInfo(
                id: "gemini-3-pro-preview",
                name: "Gemini 3 Pro (Preview)",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning, .nativePDF],
                contextWindow: 1_048_576,
                reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            ),
            ModelInfo(
                id: "gemini-3-flash-preview",
                name: "Gemini 3 Flash (Preview)",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning, .nativePDF],
                contextWindow: 1_048_576,
                reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            )
        ]

        let geminiModels: [ModelInfo] = [
            ModelInfo(
                id: "gemini-3-pro-preview",
                name: "Gemini 3 Pro (Preview)",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning, .nativePDF],
                contextWindow: 1_048_576,
                reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high)
            ),
            ModelInfo(
                id: "gemini-3-flash-preview",
                name: "Gemini 3 Flash (Preview)",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning, .nativePDF],
                contextWindow: 1_048_576,
                reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high)
            )
        ]

        let defaults: [ProviderConfig] = [
            ProviderConfig(
                id: "openai",
                name: "OpenAI",
                type: .openai,
                baseURL: ProviderType.openai.defaultBaseURL,
                models: openAIModels
            ),
            ProviderConfig(
                id: "anthropic",
                name: "Anthropic",
                type: .anthropic,
                baseURL: ProviderType.anthropic.defaultBaseURL,
                models: anthropicModels
            ),
            ProviderConfig(
                id: "xai",
                name: "xAI",
                type: .xai,
                baseURL: ProviderType.xai.defaultBaseURL,
                models: xAIModels
            ),
            ProviderConfig(
                id: "gemini",
                name: "Gemini (AI Studio)",
                type: .gemini,
                baseURL: ProviderType.gemini.defaultBaseURL,
                models: geminiModels
            ),
            ProviderConfig(
                id: "vertexai",
                name: "Vertex AI",
                type: .vertexai,
                models: vertexModels
            )
        ]

        for config in defaults {
            if let entity = try? ProviderConfigEntity.fromDomain(config) {
                modelContext.insert(entity)
            }
        }
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

private struct ConversationRowView: View {
    let title: String
    let subtitle: String
    let updatedAt: Date
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            HStack {
                Text(subtitle)
                    .lineLimit(1)
                Spacer()
                if isStreaming {
                    ProgressView()
                        .controlSize(.mini)
                        .help("Generating…")
                }
                Text(updatedAt, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, JinSpacing.small)
    }
}

private extension ContentView {
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
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

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
                        .contextMenu { assistantContextMenu(for: assistant) }
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
            .keyboardShortcut("n", modifiers: [.command, .shift])
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
    }

    @ViewBuilder
    var chatsSection: some View {
        if !filteredConversations.isEmpty {
            ForEach(groupedConversations, id: \.key) { period, convs in
                Section(period) {
                    ForEach(convs) { conversation in
                        NavigationLink(value: conversation) {
                            ConversationRowView(
                                title: conversation.title,
                                subtitle: "\(providerName(for: conversation.providerID)) • \(conversation.modelID)",
                                updatedAt: conversation.updatedAt,
                                isStreaming: streamingStore.isStreaming(conversationID: conversation.id)
                            )
                        }
                        .contextMenu {
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

private struct AssistantRowView: View {
    let assistant: AssistantEntity
    let chatCount: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: JinSpacing.medium) {
            assistantIconView
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                Text(assistant.displayName)
                    .font(.system(.body, design: .default))
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let description = assistant.assistantDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if chatCount > 0 {
                Text("\(chatCount)")
                    .font(.system(.caption, design: .monospaced))
                    .jinTagStyle()
                    .accessibilityLabel("\(chatCount) chats")
            }
        }
        .padding(.vertical, JinSpacing.small)
    }

    private var assistantIconView: some View {
        let trimmed = (assistant.icon ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Group {
            if trimmed.isEmpty {
                Image(systemName: "person.crop.circle")
            } else if trimmed.count <= 2 {
                Text(trimmed)
            } else {
                Image(systemName: trimmed)
            }
        }
        .font(.system(size: 16, weight: .semibold))
    }
}

private struct AssistantTileView: View {
    let assistant: AssistantEntity
    let isSelected: Bool
    let showsName: Bool
    let showsIcon: Bool

    var body: some View {
        VStack(spacing: showsIcon && showsName ? JinSpacing.small : 0) {
            if showsIcon {
                assistantIcon
                    .frame(width: 24, height: 24)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
            }

            if showsName {
                Text(assistant.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, JinSpacing.small)
        .padding(.horizontal, JinSpacing.small)
        .jinSurface(isSelected ? .selected : .neutral, cornerRadius: JinRadius.medium)
        .contentShape(RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous))
    }

    @ViewBuilder
    private var assistantIcon: some View {
        let trimmed = (assistant.icon ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Image(systemName: "person.crop.circle")
                .font(.system(size: JinControlMetrics.assistantGlyphSize, weight: .semibold))
        } else if trimmed.count <= 2 {
            Text(trimmed)
                .font(.system(size: JinControlMetrics.assistantGlyphSize, weight: .semibold))
        } else {
            Image(systemName: trimmed)
                .font(.system(size: JinControlMetrics.assistantGlyphSize, weight: .semibold))
        }
    }
}
