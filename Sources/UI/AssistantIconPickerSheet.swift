import SwiftUI

struct AssistantIconPickerSheet: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var draftIcon = ""
    @State private var tab: AssistantIconPickerTab = .sfSymbols
    @State private var emojiSections: [AssistantEmojiCatalog.Section] = []
    @State private var emojiDisplayItems: [AssistantEmojiDisplayItem] = []
    @State private var isEmojiCatalogLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker

                Divider()
                    .opacity(0.4)

                Group {
                    switch tab {
                    case .sfSymbols:
                        AssistantSymbolPickerScrollView(
                            searchText: searchText,
                            draftIcon: $draftIcon
                        )
                    case .emoji:
                        AssistantEmojiPickerScrollView(
                            searchText: searchText,
                            draftIcon: $draftIcon,
                            emojiSections: emojiSections,
                            emojiDisplayItems: emojiDisplayItems,
                            isEmojiCatalogLoading: isEmojiCatalogLoading
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(JinSemanticColor.detailSurface)
            .navigationTitle("Choose Icon")
            .searchable(text: $searchText, prompt: searchPrompt)
            .onChange(of: searchText) { _, _ in
                guard tab == .emoji else { return }
                rebuildEmojiDisplayItems()
            }
            .onChange(of: tab) { _, newTab in
                searchText = ""
                guard newTab == .emoji else { return }
                if emojiSections.isEmpty {
                    Task {
                        await ensureEmojiCatalogLoaded()
                    }
                } else {
                    rebuildEmojiDisplayItems(for: "")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        selectedIcon = draftIcon
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 620)
        .onAppear {
            draftIcon = selectedIcon
        }
        .task {
            await ensureEmojiCatalogLoaded()
        }
    }

    private var tabPicker: some View {
        Picker("Mode", selection: $tab) {
            ForEach(AssistantIconPickerTab.allCases, id: \.self) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var searchPrompt: String {
        switch tab {
        case .sfSymbols:
            return "Search symbols…"
        case .emoji:
            return "Search emoji…"
        }
    }

    private var searchQuery: String {
        AssistantIconPickerLayoutSupport.trimmedSearchText(searchText)
    }

    @MainActor
    private func ensureEmojiCatalogLoaded() async {
        guard emojiSections.isEmpty else {
            if emojiDisplayItems.isEmpty {
                rebuildEmojiDisplayItems()
            }
            return
        }
        guard !isEmojiCatalogLoading else { return }

        isEmojiCatalogLoading = true
        let sections = await Task.detached(priority: .utility) {
            AssistantEmojiCatalog.sections
        }.value
        emojiSections = sections
        isEmojiCatalogLoading = false
        rebuildEmojiDisplayItems()
    }

    private func rebuildEmojiDisplayItems(for rawQuery: String? = nil) {
        guard !emojiSections.isEmpty else {
            emojiDisplayItems = []
            return
        }

        let query = AssistantIconPickerLayoutSupport.trimmedSearchText(rawQuery ?? searchQuery)
        if query.isEmpty {
            emojiDisplayItems = AssistantEmojiDisplayItemFactory.makeDisplayItems(
                from: emojiSections,
                columnCount: AssistantIconPickerOptions.emojiColumnCount
            )
            return
        }

        let filteredSections = emojiSections.compactMap { section in
            let hits = section.emojis.filter { AssistantEmojiCatalog.matchesSearchQuery(query, emoji: $0) }
            return hits.isEmpty ? nil : AssistantEmojiCatalog.Section(title: section.title, emojis: hits)
        }
        emojiDisplayItems = AssistantEmojiDisplayItemFactory.makeDisplayItems(
            from: filteredSections,
            columnCount: AssistantIconPickerOptions.emojiColumnCount
        )
    }
}
