import SwiftUI

struct AssistantSymbolPickerScrollView: View {
    let searchText: String
    @Binding var draftIcon: String

    private var filteredSymbolCategories: [AssistantIconCategory] {
        AssistantIconPickerLayoutSupport.filteredSymbolCategories(
            AssistantIconPickerOptions.iconOptions,
            searchText: searchText
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if searchText.isEmpty {
                    AssistantNoIconCard(draftIcon: $draftIcon)
                }

                if filteredSymbolCategories.isEmpty {
                    AssistantIconPickerEmptySearchLabel()
                } else {
                    ForEach(filteredSymbolCategories) { category in
                        symbolCategorySection(category)
                    }
                }
            }
            .padding(20)
        }
    }

    private func symbolCategorySection(_ category: AssistantIconCategory) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            Text(category.name)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            Grid(horizontalSpacing: JinSpacing.medium, verticalSpacing: JinSpacing.medium) {
                ForEach(Array(symbolRows(for: category).enumerated()), id: \.offset) { _, row in
                    GridRow(alignment: .center) {
                        ForEach(0..<AssistantIconPickerOptions.symbolColumnCount, id: \.self) { column in
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

    private func symbolRows(for category: AssistantIconCategory) -> [[String]] {
        AssistantIconPickerLayoutSupport.chunked(
            category.icons,
            into: AssistantIconPickerOptions.symbolColumnCount
        )
    }
}
