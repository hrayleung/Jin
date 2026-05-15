import SwiftUI
import SwiftData

// MARK: - Sidebar Sections

extension ContentView {
    @ViewBuilder
    var assistantsArea: some View {
        AssistantConversationStatsObserverView { conversationCountsByAssistantID, lastConversationByAssistantID in
            VStack(spacing: 0) {
                assistantsAreaHeader
                assistantsAreaBody(
                    conversationCountsByAssistantID: conversationCountsByAssistantID,
                    lastConversationByAssistantID: lastConversationByAssistantID
                )
                newAssistantButton
            }
            .padding(.bottom, JinSpacing.xSmall)
            .onDeleteCommand {
                guard let selectedAssistant else { return }
                requestDeleteAssistant(selectedAssistant)
            }
        }
    }

    @ViewBuilder
    private var assistantsAreaHeader: some View {
        HStack {
            Text("Assistants")
                .font(.system(size: 11, weight: .semibold))
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
        .padding(.horizontal, JinSpacing.medium + 2)
        .padding(.top, JinSpacing.xSmall)
        .padding(.bottom, JinSpacing.xSmall + 1)
    }

    @ViewBuilder
    private func assistantsAreaBody(
        conversationCountsByAssistantID: [String: Int],
        lastConversationByAssistantID: [String: Date]
    ) -> some View {
        let displayedAssistants = displayedAssistants(lastConversationByAssistantID: lastConversationByAssistantID)

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
            .padding(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
            .contextMenu {
                if let assistant = selectedAssistant ?? assistants.first(where: { $0.id == "default" }) {
                    assistantContextMenu(for: assistant)
                }
            }

        case .grid:
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: 44), spacing: 8),
                    count: assistantSidebarGridColumnCount
                ),
                spacing: 8
            ) {
                ForEach(displayedAssistants) { assistant in
                    let isSelected = selectedAssistant?.id == assistant.id
                    AssistantTileView(
                        assistant: assistant,
                        isSelected: isSelected,
                        showsName: assistantSidebarEffectiveShowName,
                        showsIcon: assistantSidebarEffectiveShowIcon
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectAssistant(assistant) }
                    .onHover { isHovering in
                        if isHovering {
                            assistantContextMenuTargetID = assistant.id
                        } else if assistantContextMenuTargetID == assistant.id {
                            assistantContextMenuTargetID = nil
                        }
                    }
                    .assistantDragReorder(
                        isEnabled: assistantSidebarSort == .custom,
                        assistantID: assistant.id
                    ) { sourceID in
                        _ = reorderAssistant(sourceID: sourceID, onto: assistant.id)
                    }
                }
            }
            // No `.animation(value: displayedAssistants.map(\.id))`: spring
            // re-runs on every selection because the array identity allocates,
            // and the actual user-visible event we want to animate (add/delete
            // assistant) is rare — the cost on every click outweighed it.
            .contextMenu {
                if let assistant = resolveAssistantForContextMenu() {
                    assistantContextMenu(for: assistant)
                }
            }
            .padding(EdgeInsets(top: 6, leading: 14, bottom: 8, trailing: 14))

        case .list:
            VStack(spacing: 0) {
                ForEach(displayedAssistants) { assistant in
                    let isSelected = selectedAssistant?.id == assistant.id
                    AssistantRowView(
                        assistant: assistant,
                        chatCount: conversationCountsByAssistantID[assistant.id, default: 0],
                        isSelected: isSelected
                    )
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { selectAssistant(assistant) }
                    .contextMenu { assistantContextMenu(for: assistant) }
                    .assistantDragReorder(
                        isEnabled: assistantSidebarSort == .custom,
                        assistantID: assistant.id
                    ) { sourceID in
                        _ = reorderAssistant(sourceID: sourceID, onto: assistant.id)
                    }
                }
            }
            // No `.animation(value: displayedAssistants.map(\.id))`: spring
            // re-runs on every selection because the array identity allocates,
            // and the actual user-visible event we want to animate (add/delete
            // assistant) is rare — the cost on every click outweighed it.
        }
    }

    @ViewBuilder
    private var newAssistantButton: some View {
        Button {
            createAssistant()
        } label: {
            Label("New Assistant", systemImage: "plus")
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("New Assistant")
        .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .newAssistant))
    }

    // The conversations List moved into `ChatsSidebarSectionView.swift`. That
    // subview owns its own `@Query`; assistant chat counts / recent sort dates
    // are likewise isolated in `AssistantConversationStatsObserverView`.
}

private struct AssistantConversationStatsObserverView<Content: View>: View {
    @Query(sort: \ConversationEntity.updatedAt, order: .reverse)
    private var conversations: [ConversationEntity]
    @ViewBuilder let content: ([String: Int], [String: Date]) -> Content

    var body: some View {
        content(conversationCountsByAssistantID, lastConversationByAssistantID)
    }

    private var conversationCountsByAssistantID: [String: Int] {
        Dictionary(grouping: conversations) { conversation in
            conversation.assistant?.id ?? "default"
        }
        .mapValues(\.count)
    }

    private var lastConversationByAssistantID: [String: Date] {
        Dictionary(grouping: conversations.filter { !$0.messages.isEmpty }) { conversation in
            conversation.assistant?.id ?? "default"
        }
        .mapValues { conversations in
            conversations.map(\.updatedAt).max() ?? Date.distantPast
        }
    }
}
