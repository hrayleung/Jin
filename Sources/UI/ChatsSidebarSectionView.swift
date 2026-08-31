import SwiftUI
import SwiftData

/// Owns the conversations List in the sidebar with its own `@Query` so
/// streaming-driven `updatedAt` writes invalidate just this subview, not
/// `ContentView` (which renders the detail pane). All filter/search/group
/// work is scoped here so it doesn't run when only unrelated parent state
/// changes.
///
/// The batch selection lives here for the same reason: ⌘-clicking a second
/// row must not re-evaluate `ChatView`. Only the actions that mutate the
/// store (delete / star) are handed up to `ContentView`.
struct ChatsSidebarSectionView: View {
    @Query(sort: \ConversationEntity.updatedAt, order: .reverse)
    private var conversations: [ConversationEntity]
    @Query private var providers: [ProviderConfigEntity]
    @State private var searchCache = ConversationSearchCache()
    /// Debounced mirror of `searchText` (150ms quiet window). Filtering /
    /// JSON-decoding for search runs against this, so typing fast doesn't
    /// re-decode all messages per keystroke.
    @State private var debouncedSearchText: String = ""
    /// Chats the user explicitly multi-selected. Empty means "no explicit
    /// selection", and the list then highlights whatever chat is open — the
    /// behaviour the sidebar had before batch actions existed.
    @State private var explicitSelection: Set<UUID> = []
    /// Anchor row for ⇧-click range selection while in selection mode.
    @State private var rangeAnchorID: UUID?

    let searchText: String
    let selectedAssistantID: String?
    let regeneratingConversationID: UUID?
    @Binding var selection: ConversationEntity?
    @Binding var isSelectionModeActive: Bool
    let onSelectConversation: (ConversationEntity) -> Void
    let onToggleStar: (ConversationEntity) -> Void
    let onRename: (ConversationEntity) -> Void
    let onRegenerateTitle: (ConversationEntity) -> Void
    let onDelete: (ConversationEntity) -> Void
    let onDeleteAtOffsets: (IndexSet, [ConversationEntity]) -> Void
    let onDeleteConversations: ([ConversationEntity]) -> Void
    let onSetStarred: ([ConversationEntity], Bool) -> Void

    var body: some View {
        // Computed once per pass and threaded down. Reading them from inside
        // the row loop would multiply an O(conversations) scan by the number
        // of rows — SwiftUI never memoizes a View's computed properties.
        let filtered = filteredConversations
        let grouped = ConversationGrouping.groupedConversations(filtered)
        let batch = batchState(filtered: filtered)

        VStack(spacing: 0) {
            List(selection: listSelectionBinding) {
                chatsSection(grouped: grouped, hasConversations: !filtered.isEmpty, batch: batch)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .listStyle(.plain)
            .contentMargins(.vertical, 0, for: .scrollContent)
            .overlayScrollerStyle()
            .scrollContentBackground(.hidden)
            .onDeleteCommand { requestBatchDelete(batch: batch) }

            if isSelectionModeActive || batch.count > 1 {
                ChatsSidebarSelectionActionBar(
                    selectedCount: batch.count,
                    allVisibleSelected: batch.allVisibleSelected,
                    hasVisibleConversations: !filtered.isEmpty,
                    shouldStarSelection: batch.shouldStar,
                    onToggleSelectAll: { toggleSelectAll(filtered: filtered) },
                    onToggleStar: { applyBatchStar(batch: batch) },
                    onDelete: { requestBatchDelete(batch: batch) },
                    onDone: endSelection
                )
            }
        }
        // Published from here, not `ContentView`: keeping the selected set in
        // this subview is what stops a ⌘-click from re-evaluating `ChatView`.
        .focusedSceneValue(\.chatSelectionActions, ChatSelectionFocusedActions(
            selectedCount: batch.count,
            hasExplicitSelection: !explicitSelection.isEmpty,
            hasVisibleChats: !filtered.isEmpty,
            allVisibleSelected: batch.allVisibleSelected,
            selectAllChats: { toggleSelectAll(filtered: filtered) },
            deleteSelectedChats: { requestBatchDelete(batch: batch) }
        ))
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
        .onChange(of: isSelectionModeActive) { _, isActive in
            guard !isActive else { return }
            clearExplicitSelection()
        }
        .onChange(of: selection?.id) { _, _ in
            // Navigating elsewhere (new chat, mini player, ⌘-clicking a
            // notification) abandons a multi-selection the user built for
            // some other chat. Selection mode is explicit, so leave it alone.
            guard !isSelectionModeActive else { return }
            clearExplicitSelection()
        }
        .onChange(of: conversations.count) { _, _ in
            pruneExplicitSelection()
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
            // `resolvedMessageCount` reads the denormalized scalar; testing
            // `messages.isEmpty` here faulted every conversation's message
            // rows on every body evaluation (and this recomputes throughout
            // streaming, because `updatedAt` — the @Query sort key — changes).
            guard conversation.resolvedMessageCount > 0 else { return false }
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
        conversation.providerID
    }

    private func activeModelID(for conversation: ConversationEntity) -> String {
        conversation.modelID
    }

    private func providerName(for conversation: ConversationEntity) -> String {
        providerName(for: conversation.providerID)
    }

    private func providerIconID(for conversation: ConversationEntity) -> String? {
        providerIconID(for: conversation.providerID)
    }

    private func modelName(for conversation: ConversationEntity) -> String {
        let providerID = conversation.providerID
        let modelID = conversation.modelID
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            return modelID
        }

        if ProviderType(rawValue: provider.typeRaw) == .claudeManagedAgents {
            let storedControls = try? JSONDecoder().decode(GenerationControls.self, from: conversation.modelConfigData)
            return ClaudeManagedAgentResolutionSupport.resolvedConversationDisplayName(
                threadModelID: modelID,
                storedControls: storedControls,
                applyProviderDefaults: { controls in
                    provider.applyClaudeManagedDefaults(into: &controls)
                }
            )
        }

        return ProviderModelAliasResolver.resolvedModel(
            for: modelID,
            providerType: ProviderType(rawValue: provider.typeRaw),
            availableModels: provider.allModels
        )?.name ?? modelID
    }

    // MARK: - Selection bridge

    /// `nil` while selection mode is on: without a selection binding the List
    /// stops consuming clicks, so each row's own tap gesture can toggle its
    /// checkbox instead of moving a single-row highlight.
    private var listSelectionBinding: Binding<Set<UUID>>? {
        guard !isSelectionModeActive else { return nil }
        return Binding(
            get: {
                ChatsSidebarSelectionSupport.highlightedIDs(
                    explicitSelection: explicitSelection,
                    openConversationID: selection?.id,
                    openConversationIsListed: isOpenConversationListed
                )
            },
            set: { applyListSelection($0) }
        )
    }

    private var isOpenConversationListed: Bool {
        guard let selection else { return false }
        return conversations.contains(where: { $0.id == selection.id })
    }

    private func applyListSelection(_ newValue: Set<UUID>) {
        explicitSelection = newValue
        if newValue.count == 1 { rangeAnchorID = newValue.first }

        switch ChatsSidebarSelectionSupport.openAction(
            newSelection: newValue,
            openConversationID: selection?.id,
            openConversationIsListed: isOpenConversationListed
        ) {
        case .open(let id):
            guard let conversation = conversations.first(where: { $0.id == id }) else { return }
            onSelectConversation(conversation)
        case .clear:
            selection = nil
        case .keep:
            break
        }
    }

    // MARK: - Batch selection

    private struct BatchSelectionState {
        var ids: Set<UUID>
        /// Selected chats that still exist. Stale IDs (deleted rows) are
        /// dropped, so the action bar can never offer to delete a ghost.
        var count: Int
        var shouldStar: Bool
        var allVisibleSelected: Bool
    }

    /// What a batch action applies to. With no explicit selection that's the
    /// open chat, so ⌫ and the context menu keep working on a single row.
    private var actionableIDs: Set<UUID> {
        guard explicitSelection.isEmpty else { return explicitSelection }
        guard !isSelectionModeActive, let selection else { return [] }
        return [selection.id]
    }

    private func batchState(filtered: [ConversationEntity]) -> BatchSelectionState {
        let ids = actionableIDs
        guard !ids.isEmpty else {
            return BatchSelectionState(ids: [], count: 0, shouldStar: true, allVisibleSelected: false)
        }

        var starredFlags: [Bool] = []
        starredFlags.reserveCapacity(ids.count)
        for conversation in conversations where ids.contains(conversation.id) {
            starredFlags.append(conversation.isStarred == true)
        }

        return BatchSelectionState(
            ids: ids,
            count: starredFlags.count,
            shouldStar: ChatsSidebarSelectionSupport.shouldStarSelection(starredFlags: starredFlags),
            allVisibleSelected: ChatsSidebarSelectionSupport.allVisibleSelected(ids, visibleIDs: filtered.map(\.id))
        )
    }

    private func batchTargets(_ batch: BatchSelectionState) -> [ConversationEntity] {
        ChatsSidebarSelectionSupport.orderedSelection(from: conversations, matching: batch.ids, id: \.id)
    }

    private func requestBatchDelete(batch: BatchSelectionState) {
        let targets = batchTargets(batch)
        guard !targets.isEmpty else { return }
        onDeleteConversations(targets)
    }

    private func applyBatchStar(batch: BatchSelectionState) {
        let targets = batchTargets(batch)
        guard !targets.isEmpty else { return }
        onSetStarred(targets, batch.shouldStar)
    }

    private func toggleSelectAll(filtered: [ConversationEntity]) {
        explicitSelection = ChatsSidebarSelectionSupport.selectAllToggled(
            explicitSelection,
            visibleIDs: filtered.map(\.id)
        )
        rangeAnchorID = nil
    }

    private func toggleSelection(of conversation: ConversationEntity, extendingRange: Bool) {
        let id = conversation.id

        if extendingRange,
           let range = ChatsSidebarSelectionSupport.rangeSelection(
               from: rangeAnchorID,
               to: id,
               in: orderedVisibleIDs
           ) {
            explicitSelection.formUnion(range)
            rangeAnchorID = id
            return
        }

        explicitSelection = ChatsSidebarSelectionSupport.toggled(explicitSelection, id: id)
        rangeAnchorID = explicitSelection.contains(id) ? id : nil
    }

    private func beginSelection(with conversation: ConversationEntity) {
        explicitSelection = [conversation.id]
        rangeAnchorID = conversation.id
        isSelectionModeActive = true
    }

    private func endSelection() {
        clearExplicitSelection()
        if isSelectionModeActive { isSelectionModeActive = false }
    }

    private func clearExplicitSelection() {
        guard !explicitSelection.isEmpty || rangeAnchorID != nil else { return }
        explicitSelection = []
        rangeAnchorID = nil
    }

    private func pruneExplicitSelection() {
        guard !explicitSelection.isEmpty else { return }
        let live = Set(conversations.map(\.id))
        let pruned = explicitSelection.intersection(live)
        guard pruned != explicitSelection else { return }
        explicitSelection = pruned
        if let rangeAnchorID, !pruned.contains(rangeAnchorID) { self.rangeAnchorID = nil }
    }

    /// Row order as displayed (grouped, starred first) — what a ⇧-click range
    /// has to follow.
    private var orderedVisibleIDs: [UUID] {
        ConversationGrouping.groupedConversations(filteredConversations)
            .flatMap { $0.value.map(\.id) }
    }

    private func selectionActions(for conversation: ConversationEntity, batch: BatchSelectionState) -> SidebarConversationSelectionActions {
        SidebarConversationSelectionActions(
            toggle: { extendingRange in
                toggleSelection(of: conversation, extendingRange: extendingRange)
            },
            beginSelection: { beginSelection(with: conversation) },
            batchStar: { applyBatchStar(batch: batch) },
            batchDelete: { requestBatchDelete(batch: batch) },
            // Deselect only — leaving selection mode is the action bar's ✕.
            clearSelection: clearExplicitSelection
        )
    }

    // MARK: - Rows

    @ViewBuilder
    private func chatsSection(
        grouped: [(key: String, value: [ConversationEntity])],
        hasConversations: Bool,
        batch: BatchSelectionState
    ) -> some View {
        if hasConversations {
            ForEach(grouped, id: \.key) { period, convs in
                Section {
                    ForEach(convs) { conversation in
                        SidebarConversationItem(
                            conversation: conversation,
                            subtitle: "\(providerName(for: conversation)) \u{2022} \(modelName(for: conversation))",
                            providerIconID: providerIconID(for: conversation),
                            searchSnippet: searchSnippet(for: conversation),
                            searchQuery: normalizedConversationSearchQuery,
                            isRegeneratingTitle: regeneratingConversationID == conversation.id,
                            selection: SidebarConversationSelectionState(
                                isSelectionModeActive: isSelectionModeActive,
                                isSelected: batch.ids.contains(conversation.id),
                                batchCount: batch.count,
                                shouldStarBatch: batch.shouldStar
                            ),
                            selectionActions: selectionActions(for: conversation, batch: batch),
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
