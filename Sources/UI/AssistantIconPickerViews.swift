import AppKit
import SwiftUI

struct AssistantIconPickerButton: View {
    @Binding var selectedIcon: String
    @State private var isPickerPresented = false

    var body: some View {
        Button {
            isPickerPresented = true
        } label: {
            HStack(spacing: JinSpacing.small) {
                iconPreview
                    .frame(width: JinControlMetrics.iconButtonHitSize, height: JinControlMetrics.iconButtonHitSize)
                    .jinSurface(.selected, cornerRadius: JinRadius.small)

                Text(selectedIcon.isEmpty ? "Choose Icon\u{2026}" : "Change Icon")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, JinSpacing.medium - 2)
            .padding(.vertical, JinSpacing.xSmall + 2)
            .jinSurface(.neutral, cornerRadius: JinRadius.small)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPickerPresented) {
            AssistantIconPickerSheet(selectedIcon: $selectedIcon)
        }
    }

    private var iconPreview: some View {
        let trimmed = selectedIcon.trimmingCharacters(in: .whitespacesAndNewlines)
        return Group {
            if trimmed.isEmpty {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: JinControlMetrics.assistantGlyphSize, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else if AssistantGlyphRendering.isSFSymbolName(trimmed) {
                Image(systemName: trimmed)
                    .font(.system(size: JinControlMetrics.assistantGlyphSize, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            } else {
                Text(trimmed)
                    .font(.system(size: JinControlMetrics.assistantGlyphSize))
                    .foregroundStyle(.primary)
            }
        }
    }
}

struct AssistantIconCategory: Identifiable {
    let name: String
    let icons: [String]

    var id: String { name }
}

private enum AssistantIconPickerTab: String, CaseIterable {
    case sfSymbols = "SF Symbols"
    case emoji = "Emoji"
}

private struct AssistantEmojiRow: Identifiable, Equatable {
    let id: String
    let emojis: [String]
}

private enum AssistantEmojiDisplayItem: Identifiable, Equatable {
    case header(String)
    case row(AssistantEmojiRow)

    var id: String {
        switch self {
        case .header(let title):
            return "header:\(title)"
        case .row(let row):
            return row.id
        }
    }
}

struct AssistantIconPickerSheet: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var draftIcon = ""
    @State private var tab: AssistantIconPickerTab = .sfSymbols
    @State private var emojiSections: [AssistantEmojiCatalog.Section] = []
    @State private var emojiDisplayItems: [AssistantEmojiDisplayItem] = []
    @State private var isEmojiCatalogLoading = false

    private let symbolColumnCount = 6
    private let emojiColumnCount = 8

    let iconOptions: [AssistantIconCategory] = [
        AssistantIconCategory(
            name: "Characters",
            icons: ["person.crop.circle", "person.fill", "person.2.fill", "figure.wave", "sparkles", "star.fill", "heart.fill", "face.smiling", "crown.fill", "moon.stars.fill"]
        ),
        AssistantIconCategory(
            name: "Technology",
            icons: ["laptopcomputer", "desktopcomputer", "iphone", "applewatch", "brain", "cpu", "antenna.radiowaves.left.and.right", "waveform", "bolt.fill", "lightbulb.fill"]
        ),
        AssistantIconCategory(
            name: "Communication",
            icons: ["bubble.left.and.bubble.right", "message.fill", "envelope.fill", "phone.fill", "video.fill", "mic.fill", "speaker.wave.3.fill", "quote.bubble", "megaphone.fill", "bell.fill"]
        ),
        AssistantIconCategory(
            name: "Creative",
            icons: ["paintbrush.fill", "pencil", "pencil.and.outline", "book.fill", "doc.text.fill", "photo.fill", "music.note", "film", "camera.fill", "theatermasks.fill"]
        ),
        AssistantIconCategory(
            name: "Business",
            icons: ["briefcase.fill", "chart.line.uptrend.xyaxis", "dollarsign.circle.fill", "building.2.fill", "cart.fill", "creditcard.fill", "paperplane.fill", "folder.fill", "calendar", "clock.fill"]
        ),
        AssistantIconCategory(
            name: "Science",
            icons: ["graduationcap.fill", "atom", "flask.fill", "testtube.2", "leaf.fill", "globe", "pawprint.fill", "microbe.fill", "fossil.shell.fill", "mountain.2.fill"]
        )
    ]

    var filteredSymbolCategories: [AssistantIconCategory] {
        let query = searchQuery
        if query.isEmpty {
            return iconOptions
        }
        return iconOptions.compactMap { category in
            if category.name.localizedStandardContains(query) {
                return category
            }
            let filtered = category.icons.filter { icon in
                icon.localizedStandardContains(query)
            }
            return filtered.isEmpty ? nil : AssistantIconCategory(name: category.name, icons: filtered)
        }
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchPrompt: String {
        switch tab {
        case .sfSymbols:
            return "Search symbols…"
        case .emoji:
            return "Search emoji…"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $tab) {
                    ForEach(AssistantIconPickerTab.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                Divider()
                    .opacity(0.4)

                Group {
                    switch tab {
                    case .sfSymbols:
                        symbolPickerScroll
                    case .emoji:
                        emojiPickerScroll
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

    private var symbolPickerScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if searchText.isEmpty {
                    noneIconCard
                }

                if filteredSymbolCategories.isEmpty {
                    emptySearchLabel
                } else {
                    ForEach(filteredSymbolCategories) { category in
                        symbolCategorySection(category)
                    }
                }
            }
            .padding(20)
        }
    }

    private var emojiPickerScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: JinSpacing.medium) {
                if searchText.isEmpty {
                    noneIconCard
                }

                if isEmojiCatalogLoading && emojiSections.isEmpty {
                    emojiLoadingLabel
                } else if emojiSections.isEmpty {
                    Text("Could not load the emoji catalog.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else if emojiDisplayItems.isEmpty {
                    emptySearchLabel
                } else {
                    ForEach(emojiDisplayItems) { item in
                        emojiDisplayItemView(item)
                    }
                }
            }
            .padding(20)
        }
    }

    private var noneIconCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("None")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            Button {
                draftIcon = ""
            } label: {
                HStack(spacing: JinSpacing.small) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .jinSurface(draftIcon.isEmpty ? .selected : .neutral, cornerRadius: JinRadius.medium)

                    Text("No Icon")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .jinSurface(.raised, cornerRadius: JinRadius.medium)
    }

    private var emptySearchLabel: some View {
        Text("No matches.")
            .font(.body)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
    }

    private var emojiLoadingLabel: some View {
        ProgressView("Loading emoji…")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
    }

    private func symbolCategorySection(_ category: AssistantIconCategory) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            Text(category.name)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            Grid(horizontalSpacing: JinSpacing.medium, verticalSpacing: JinSpacing.medium) {
                ForEach(Array(category.icons.chunked(into: symbolColumnCount).enumerated()), id: \.offset) { _, row in
                    GridRow(alignment: .center) {
                        ForEach(0..<symbolColumnCount, id: \.self) { column in
                            Group {
                                if column < row.count {
                                    AssistantSFSymbolPickerTile(
                                        symbolName: row[column],
                                        isSelected: draftIcon == row[column]
                                    ) {
                                        draftIcon = row[column]
                                    }
                                } else {
                                    Color.clear
                                        .frame(maxWidth: .infinity)
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(12)
        .jinSurface(.raised, cornerRadius: JinRadius.medium)
    }

    @ViewBuilder
    private func emojiDisplayItemView(_ item: AssistantEmojiDisplayItem) -> some View {
        switch item {
        case .header(let title):
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.top, JinSpacing.small)
        case .row(let row):
            AssistantEmojiPickerRow(
                emojis: row.emojis,
                selectedEmoji: draftIcon,
                columnCount: emojiColumnCount
            ) { emoji in
                draftIcon = emoji
            }
            .equatable()
        }
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

        let query = (rawQuery ?? searchQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            emojiDisplayItems = makeEmojiDisplayItems(from: emojiSections)
            return
        }

        let filteredSections = emojiSections.compactMap { section in
            let hits = section.emojis.filter { AssistantEmojiCatalog.matchesSearchQuery(query, emoji: $0) }
            return hits.isEmpty ? nil : AssistantEmojiCatalog.Section(title: section.title, emojis: hits)
        }
        emojiDisplayItems = makeEmojiDisplayItems(from: filteredSections)
    }

    private func makeEmojiDisplayItems(from sections: [AssistantEmojiCatalog.Section]) -> [AssistantEmojiDisplayItem] {
        let estimatedRowCount = sections.reduce(into: sections.count) { partialResult, section in
            partialResult += (section.emojis.count + emojiColumnCount - 1) / emojiColumnCount
        }

        var items: [AssistantEmojiDisplayItem] = []
        items.reserveCapacity(estimatedRowCount)

        for section in sections {
            items.append(.header(section.title))
            for (index, row) in section.emojis.chunked(into: emojiColumnCount).enumerated() {
                let firstEmoji = row.first ?? "empty"
                items.append(
                    .row(
                        AssistantEmojiRow(
                            id: "\(section.id)-\(index)-\(firstEmoji)",
                            emojis: row
                        )
                    )
                )
            }
        }

        return items
    }
}

// MARK: - Tiles

private struct AssistantSFSymbolPickerTile: View {
    private static let tileSide: CGFloat = 44
    private static let symbolPointSize: CGFloat = 19

    let symbolName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil {
                    Image(systemName: symbolName)
                        .font(.system(size: Self.symbolPointSize, weight: .medium))
                        .imageScale(.medium)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                } else {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: Self.symbolPointSize, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: Self.tileSide, height: Self.tileSide)
            .jinSurface(isSelected ? .selected : .neutral, cornerRadius: JinRadius.medium)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct AssistantEmojiPickerRow: View, Equatable {
    private static let placeholderHeight: CGFloat = 40

    let emojis: [String]
    let selectedEmoji: String
    let columnCount: Int
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            ForEach(0..<columnCount, id: \.self) { index in
                Group {
                    if index < emojis.count {
                        let emoji = emojis[index]
                        AssistantEmojiPickerTile(
                            emoji: emoji,
                            isSelected: selectedEmoji == emoji
                        ) {
                            onSelect(emoji)
                        }
                    } else {
                        Color.clear
                            .frame(height: Self.placeholderHeight)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    static func == (lhs: AssistantEmojiPickerRow, rhs: AssistantEmojiPickerRow) -> Bool {
        lhs.emojis == rhs.emojis &&
        lhs.columnCount == rhs.columnCount &&
        lhs.selectionState == rhs.selectionState
    }

    private var selectionState: String? {
        emojis.contains(selectedEmoji) ? selectedEmoji : nil
    }
}

private struct AssistantEmojiPickerTile: View, Equatable {
    private static let tileSide: CGFloat = 40
    private static let fontSize: CGFloat = 25

    let emoji: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(emoji)
                    .font(.system(size: Self.fontSize))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
            }
            .frame(width: Self.tileSide, height: Self.tileSide)
            .jinSurface(isSelected ? .selected : .neutral, cornerRadius: JinRadius.medium)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    static func == (lhs: AssistantEmojiPickerTile, rhs: AssistantEmojiPickerTile) -> Bool {
        lhs.emoji == rhs.emoji && lhs.isSelected == rhs.isSelected
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
