import SwiftUI

struct AssistantEmojiPickerScrollView: View {
    let searchText: String
    @Binding var draftIcon: String
    let emojiSections: [AssistantEmojiCatalog.Section]
    let emojiDisplayItems: [AssistantEmojiDisplayItem]
    let isEmojiCatalogLoading: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: JinSpacing.medium) {
                if searchText.isEmpty {
                    AssistantNoIconCard(draftIcon: $draftIcon)
                }

                if isEmojiCatalogLoading && emojiSections.isEmpty {
                    emojiLoadingLabel
                } else if emojiSections.isEmpty {
                    Text("Could not load the emoji catalog.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else if emojiDisplayItems.isEmpty {
                    AssistantIconPickerEmptySearchLabel()
                } else {
                    ForEach(emojiDisplayItems) { item in
                        emojiDisplayItemView(item)
                    }
                }
            }
            .padding(20)
        }
    }

    private var emojiLoadingLabel: some View {
        ProgressView("Loading emoji…")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
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
                columnCount: AssistantIconPickerOptions.emojiColumnCount
            ) { emoji in
                draftIcon = emoji
            }
            .equatable()
        }
    }
}

enum AssistantEmojiDisplayItemFactory {
    static func makeDisplayItems(
        from sections: [AssistantEmojiCatalog.Section],
        columnCount: Int
    ) -> [AssistantEmojiDisplayItem] {
        guard columnCount > 0 else { return [] }

        let estimatedRowCount = sections.reduce(into: sections.count) { partialResult, section in
            partialResult += (section.emojis.count + columnCount - 1) / columnCount
        }

        var items: [AssistantEmojiDisplayItem] = []
        items.reserveCapacity(estimatedRowCount)

        for section in sections {
            items.append(.header(section.title))
            let emojiRows = AssistantIconPickerLayoutSupport.chunked(section.emojis, into: columnCount)
            for (index, row) in emojiRows.enumerated() {
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
