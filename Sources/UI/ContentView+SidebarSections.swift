import SwiftUI
import SwiftData

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
                        SidebarConversationItem(
                            conversation: conversation,
                            subtitle: "\(providerName(for: conversation.providerID)) \u{2022} \(modelName(id: conversation.modelID, providerID: conversation.providerID))",
                            providerIconID: providerIconID(for: conversation.providerID),
                            searchSnippet: searchSnippet(for: conversation),
                            searchQuery: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                            isRegeneratingTitle: regeneratingConversationID == conversation.id,
                            onToggleStar: { toggleConversationStar(conversation) },
                            onRename: { requestRenameConversation(conversation) },
                            onRegenerateTitle: { Task { await regenerateConversationTitle(conversation) } },
                            onDelete: { requestDeleteConversation(conversation) }
                        )
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
