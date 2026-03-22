import SwiftUI
import SwiftData

// MARK: - Assistant CRUD & Selection

extension ContentView {
    func selectAssistant(_ assistant: AssistantEntity) {
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedAssistant = assistant
            if let selectedConversation, selectedConversation.assistant?.id != assistant.id {
                self.selectedConversation = nil
            }
        }
    }

    func createAssistant() {
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

    func requestDeleteAssistant(_ assistant: AssistantEntity) {
        guard assistants.count > 1 else { return }
        guard assistant.id != "default" else { return }
        assistantPendingDeletion = assistant
        showingDeleteAssistantConfirmation = true
    }

    func deleteAssistant(_ assistant: AssistantEntity) {
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

    // MARK: - Sidebar Layout Helpers

    var displayedAssistants: [AssistantEntity] {
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

    var assistantSidebarLayout: AssistantSidebarLayout {
        AssistantSidebarLayout(rawValue: assistantSidebarLayoutRaw) ?? .grid
    }

    var assistantSidebarSort: AssistantSidebarSort {
        AssistantSidebarSort(rawValue: assistantSidebarSortRaw) ?? .custom
    }

    var assistantSidebarGridColumnCount: Int {
        max(1, min(assistantSidebarGridColumns, 4))
    }

    var assistantSidebarEffectiveShowName: Bool {
        assistantSidebarShowName
    }

    var assistantSidebarEffectiveShowIcon: Bool {
        assistantSidebarShowIcon || !assistantSidebarShowName
    }

    var selectedAssistantIDBinding: Binding<String> {
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

    var assistantSidebarGridColumnsBinding: Binding<Int> {
        Binding(
            get: { assistantSidebarGridColumnCount },
            set: { newValue in
                assistantSidebarLayoutRaw = AssistantSidebarLayout.grid.rawValue
                assistantSidebarGridColumns = newValue
            }
        )
    }

    var assistantSidebarUsesDropdownBinding: Binding<Bool> {
        Binding(
            get: { assistantSidebarLayout == .dropdown },
            set: { newValue in
                assistantSidebarLayoutRaw = newValue
                    ? AssistantSidebarLayout.dropdown.rawValue
                    : AssistantSidebarLayout.grid.rawValue
            }
        )
    }

    var assistantSidebarSortBinding: Binding<AssistantSidebarSort> {
        Binding(
            get: { assistantSidebarSort },
            set: { newValue in
                assistantSidebarSortRaw = newValue.rawValue
            }
        )
    }

    func resolveAssistantForContextMenu() -> AssistantEntity? {
        if let assistantContextMenuTargetID,
           let assistant = assistants.first(where: { $0.id == assistantContextMenuTargetID }) {
            return assistant
        }

        return selectedAssistant
            ?? assistants.first(where: { $0.id == "default" })
            ?? assistants.first
    }

    @ViewBuilder
    func assistantContextMenu(for assistant: AssistantEntity) -> some View {
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
            Label("Delete \u{201C}\(assistant.displayName)\u{201D}", systemImage: "trash")
        }
        .disabled(assistant.id == "default" || assistants.count <= 1)
    }
}
