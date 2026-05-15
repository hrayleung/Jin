import SwiftUI
import SwiftData

/// Owns the conversations List in the sidebar with its own `@Query` so
/// streaming-driven `updatedAt` writes invalidate just this subview, not
/// `ContentView` (which renders the detail pane). All filter/search/group
/// work is scoped here so it doesn't run when only unrelated parent state
/// changes.
struct ChatsSidebarSectionView: View {
    @Query(sort: \ConversationEntity.updatedAt, order: .reverse)
    private var conversations: [ConversationEntity]
    @Query private var providers: [ProviderConfigEntity]
    @State private var searchCache = ConversationSearchCache()
    /// Debounced mirror of `searchText` (150ms quiet window). Filtering /
    /// JSON-decoding for search runs against this, so typing fast doesn't
    /// re-decode all messages per keystroke.
    @State private var debouncedSearchText: String = ""

    let searchText: String
    let selectedAssistantID: String?
    let regeneratingConversationID: UUID?
    @Binding var selection: ConversationEntity?
    let onSelectConversation: (ConversationEntity) -> Void
    let onToggleStar: (ConversationEntity) -> Void
    let onRename: (ConversationEntity) -> Void
    let onRegenerateTitle: (ConversationEntity) -> Void
    let onDelete: (ConversationEntity) -> Void
    let onDeleteAtOffsets: (IndexSet, [ConversationEntity]) -> Void

    var body: some View {
        List(selection: selectionBinding) {
            chatsSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .listStyle(.plain)
        .contentMargins(.vertical, 0, for: .scrollContent)
        .overlayScrollerStyle()
        .scrollContentBackground(.hidden)
        .task(id: searchText) {
            // Empty queries should clear immediately so the "no conversations"
            // / unsearched grouping appears without a delay.
            if searchText.isEmpty {
                debouncedSearchText = ""
                return
            }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            debouncedSearchText = searchText
        }
    }

    // MARK: - Filtering / grouping

    private var normalizedConversationSearchQuery: String {
        ContentViewConversationListSupport.normalizedSearchQuery(debouncedSearchText)
    }

    private var filteredConversations: [ConversationEntity] {
        let query = normalizedConversationSearchQuery
        let isSearching = !query.isEmpty

        let baseConversations = conversations.filter { conversation in
            guard !conversation.messages.isEmpty else { return false }
            if isSearching { return true }
            guard let selectedAssistantID else { return true }
            return conversation.assistant?.id == selectedAssistantID
        }

        guard isSearching else { return baseConversations }

        let lowered = query.lowercased()
        return baseConversations.filter { conversation in
            if conversation.title.lowercased().contains(lowered)
                || activeModelID(for: conversation).lowercased().contains(lowered)
                || providerName(for: conversation).lowercased().contains(lowered) {
                return true
            }
            return searchCache.searchableText(for: conversation)
                .localizedCaseInsensitiveContains(query)
        }
    }

    private var groupedConversations: [(key: String, value: [ConversationEntity])] {
        ConversationGrouping.groupedConversations(filteredConversations)
    }

    private func searchSnippet(for conversation: ConversationEntity) -> String? {
        let query = normalizedConversationSearchQuery
        guard !query.isEmpty else { return nil }
        let lowered = query.lowercased()
        if conversation.title.lowercased().contains(lowered) { return nil }
        return ConversationSearchCache.extractSnippet(
            from: searchCache.searchableText(for: conversation),
            query: query
        )
    }

    // MARK: - Provider / model resolution (scoped to this view's own providers query)

    private func providerName(for providerID: String) -> String {
        providers.first(where: { $0.id == providerID })?.name ?? providerID
    }

    private func providerIconID(for providerID: String) -> String? {
        providers.first(where: { $0.id == providerID })?.resolvedProviderIconID
    }

    private func activeProviderID(for conversation: ConversationEntity) -> String {
        let sortedThreads = ChatThreadSupport.sortedThreads(in: conversation.modelThreads)
        if let active = ChatThreadSupport.activeThread(
            in: sortedThreads,
            preferredID: conversation.activeThreadID
        ) {
            return active.providerID
        }
        return conversation.providerID
    }

    private func activeModelID(for conversation: ConversationEntity) -> String {
        let sortedThreads = ChatThreadSupport.sortedThreads(in: conversation.modelThreads)
        if let active = ChatThreadSupport.activeThread(
            in: sortedThreads,
            preferredID: conversation.activeThreadID
        ) {
            return active.modelID
        }
        return conversation.modelID
    }

    private func providerName(for conversation: ConversationEntity) -> String {
        providerName(for: activeProviderID(for: conversation))
    }

    private func providerIconID(for conversation: ConversationEntity) -> String? {
        providerIconID(for: activeProviderID(for: conversation))
    }

    private func modelName(for conversation: ConversationEntity) -> String {
        let providerID = activeProviderID(for: conversation)
        let modelID = activeModelID(for: conversation)
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            return modelID
        }

        if ProviderType(rawValue: provider.typeRaw) == .claudeManagedAgents {
            let sortedThreads = ChatThreadSupport.sortedThreads(in: conversation.modelThreads)
            let activeThread = ChatThreadSupport.activeThread(
                in: sortedThreads,
                preferredID: conversation.activeThreadID
            )
            let configData = activeThread?.modelConfigData
                ?? conversation.modelConfigData
            let storedControls = try? JSONDecoder().decode(GenerationControls.self, from: configData)
            return ClaudeManagedAgentResolutionSupport.resolvedConversationDisplayName(
                threadModelID: modelID,
                storedControls: storedControls,
                applyProviderDefaults: { controls in
                    provider.applyClaudeManagedDefaults(into: &controls)
                }
            )
        }

        return provider.allModels.first(where: { $0.id == modelID })?.name ?? modelID
    }

    // MARK: - Selection bridge

    private var selectionBinding: Binding<ConversationEntity?> {
        Binding(
            get: {
                guard let selection else { return nil }
                return conversations.first(where: { $0.id == selection.id })
            },
            set: { newValue in
                guard let newValue else {
                    guard let current = selection else { return }
                    if conversations.contains(where: { $0.id == current.id }) {
                        selection = nil
                    }
                    return
                }
                onSelectConversation(newValue)
            }
        )
    }

    // MARK: - Rows

    @ViewBuilder
    private var chatsSection: some View {
        if !filteredConversations.isEmpty {
            ForEach(groupedConversations, id: \.key) { period, convs in
                Section {
                    ForEach(convs) { conversation in
                        SidebarConversationItem(
                            conversation: conversation,
                            subtitle: "\(providerName(for: conversation)) \u{2022} \(modelName(for: conversation))",
                            providerIconID: providerIconID(for: conversation),
                            searchSnippet: searchSnippet(for: conversation),
                            searchQuery: normalizedConversationSearchQuery,
                            isRegeneratingTitle: regeneratingConversationID == conversation.id,
                            onToggleStar: { onToggleStar(conversation) },
                            onRename: { onRename(conversation) },
                            onRegenerateTitle: { onRegenerateTitle(conversation) },
                            onDelete: { onDelete(conversation) }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { indexSet in
                        onDeleteAtOffsets(indexSet, convs)
                    }
                } header: {
                    Text(period)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, JinSpacing.medium + 2)
                        .padding(.top, JinSpacing.medium)
                        .padding(.bottom, JinSpacing.xSmall + 1)
                }
                .textCase(nil)
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
