import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
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

    var body: some View {
        NavigationSplitView {
            // Sidebar: Conversation list
            VStack(spacing: 0) {
                sidebarSearchField
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                assistantPicker
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                Divider()

                List(selection: $selectedConversation) {
                    if !filteredConversations.isEmpty {
                        ForEach(groupedConversations, id: \.key) { period, convs in
                            Section(period) {
                                ForEach(convs) { conversation in
                                    NavigationLink(value: conversation) {
                                        ConversationRowView(
                                            title: conversation.title,
                                            subtitle: "\(providerName(for: conversation.providerID)) • \(conversation.modelID)",
                                            updatedAt: conversation.updatedAt
                                        )
                                    }
                                    .contextMenu {
                                        Button {
                                            isAssistantInspectorPresented = true
                                        } label: {
                                            Label("Assistant Settings", systemImage: "sidebar.right")
                                        }

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
                .listStyle(.sidebar)
                
                // Bottom New Chat Button
                Divider()
                HStack {
                    Button(action: createNewConversation) {
                        Label("New Chat", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding()
                }
                .background(Color(nsColor: .controlBackgroundColor))
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
            .navigationTitle(selectedAssistant?.displayName ?? "Conversations")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        isAssistantInspectorPresented.toggle()
                    } label: {
                        Label("Assistant Settings", systemImage: "sidebar.right")
                    }

                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        } detail: {
            if let conversation = selectedConversation {
                ChatView(
                    conversationEntity: conversation,
                    onRequestDeleteConversation: {
                        requestDeleteConversation(conversation)
                    }
                )
                    .id(conversation.id) // Ensure view rebuilds when switching
            } else {
                ContentUnavailableView {
                    Label("No Conversation Selected", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Pick a conversation from the sidebar, or start a new one.")
                } actions: {
                    Button("New Chat") {
                        createNewConversation()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .task {
            bootstrapDefaultProvidersIfNeeded()
            bootstrapDefaultAssistantsIfNeeded()
        }
        .inspector(isPresented: $isAssistantInspectorPresented) {
            AssistantInspectorView(
                assistant: selectedAssistant,
                onRequestDelete: requestDeleteAssistant
            )
            .frame(minWidth: 320)
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

    // MARK: - Helpers

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

        let providerID = providers.first(where: { $0.id == "openai" })?.id
            ?? providers.first?.id
            ?? "openai"
        let modelID = defaultModelID(for: providerID)

        let controlsData = (try? JSONEncoder().encode(GenerationControls())) ?? Data()
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

    private func defaultModelID(for providerID: String) -> String {
        guard let provider = providers.first(where: { $0.id == providerID }),
              let models = try? JSONDecoder().decode([ModelInfo].self, from: provider.modelsData) else {
            switch providerID {
            case "anthropic":
                return "claude-sonnet-4-5-20250929"
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
        if providerID == "anthropic", let sonnet45 = models.first(where: { $0.id == "claude-sonnet-4-5-20250929" }) {
            return sonnet45.id
        }
        if providerID == "xai", let grok41Fast = models.first(where: { $0.id == "grok-4-1-fast" }) {
            return grok41Fast.id
        }
        if providerID == "vertexai", let gemini3Pro = models.first(where: { $0.id == "gemini-3-pro-preview" }) {
            return gemini3Pro.id
        }
        return models.first?.id ?? (providerID == "anthropic" ? "claude-sonnet-4-5-20250929" : "gpt-5.2")
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
        selectedAssistant = assistant
        if let selectedConversation, selectedConversation.assistant?.id != assistant.id {
            self.selectedConversation = nil
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
        modelContext.delete(conversation)
        if selectedConversation == conversation {
            selectedConversation = nil
        }
        conversationPendingDeletion = nil
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
                id: "claude-opus-4-5-20251101",
                name: "Claude Opus 4.5",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
                contextWindow: 200000,
                reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 4096)
            ),
            ModelInfo(
                id: "claude-sonnet-4-5-20250929",
                name: "Claude Sonnet 4.5",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
                contextWindow: 200000,
                reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 2048)
            ),
            ModelInfo(
                id: "claude-haiku-4-5-20251001",
                name: "Claude Haiku 4.5",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
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
                capabilities: [.streaming, .toolCalling, .vision, .reasoning],
                contextWindow: 1_048_576,
                reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            ),
            ModelInfo(
                id: "gemini-3-flash-preview",
                name: "Gemini 3 Flash (Preview)",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning],
                contextWindow: 1_048_576,
                reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            HStack {
                Text(subtitle)
                    .lineLimit(1)
                Spacer()
                Text(updatedAt, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private extension AssistantEntity {
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? id : trimmed
    }
}

private extension ContentView {
    var sidebarSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    var assistantPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
            ForEach(assistants) { assistant in
                AssistantTileView(
                    assistant: assistant,
                    isSelected: selectedAssistant?.id == assistant.id,
                    onSelect: { selectAssistant(assistant) },
                    onOpenSettings: { isAssistantInspectorPresented = true },
                    onRequestDelete: { requestDeleteAssistant(assistant) }
                )
            }

            Button {
                createAssistant()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text("New")
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.001))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Create a new assistant")
        }
    }
}

private struct AssistantTileView: View {
    let assistant: AssistantEntity
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpenSettings: () -> Void
    let onRequestDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                assistantIconView
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(assistant.displayName)
                    .font(.system(.caption, design: .default))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(assistant.assistantDescription ?? "")
        .contextMenu {
            Button {
                onOpenSettings()
            } label: {
                Label("Assistant Settings", systemImage: "sidebar.right")
            }

            Divider()

            Button(role: .destructive) {
                onRequestDelete()
            } label: {
                Label("Delete Assistant", systemImage: "trash")
            }
            .disabled(assistant.id == "default")
        }
    }

    @ViewBuilder
    private var assistantIconView: some View {
        let trimmed = (assistant.icon ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Image(systemName: "person.crop.circle")
        } else if trimmed.count <= 2 {
            Text(trimmed)
        } else {
            Image(systemName: trimmed)
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.001)
    }
}
