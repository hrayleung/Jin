import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ConversationEntity.updatedAt, order: .reverse) private var conversations: [ConversationEntity]
    @Query private var providers: [ProviderConfigEntity]

    @State private var selectedConversation: ConversationEntity?
    @State private var didBootstrapDefaults = false
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            // Sidebar: Conversation list
            VStack(spacing: 0) {
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
                .searchable(text: $searchText, placement: .sidebar, prompt: "Search chats")
                
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
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                     SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        } detail: {
            if let conversation = selectedConversation {
                ChatView(conversationEntity: conversation)
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
            modelConfigData: controlsData
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
        guard !query.isEmpty else { return conversations }

        let lowered = query.lowercased()
        return conversations.filter {
            $0.title.lowercased().contains(lowered)
                || $0.modelID.lowercased().contains(lowered)
                || providerName(for: $0.providerID).lowercased().contains(lowered)
        }
    }

    private func providerName(for providerID: String) -> String {
        providers.first(where: { $0.id == providerID })?.name ?? providerID
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
