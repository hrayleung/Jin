import SwiftUI

struct FontPickerSheet: View {
    let title: String
    let subtitle: String
    @Binding var selectedFontFamily: String

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var trimmedSearchText: String {
        FontPickerSupport.trimmedSearchText(searchText)
    }

    private var filteredFamilies: [String] {
        FontPickerSupport.filteredFamilies(
            JinTypography.availableFontFamilies,
            searchText: searchText
        )
    }

    private var normalizedSelection: String {
        FontPickerSupport.normalizedSelection(selectedFontFamily)
    }

    var body: some View {
        VStack(spacing: 0) {
            FontPickerHeader(title: title, subtitle: subtitle, onDone: { dismiss() })

            FontPickerSearchField(
                searchText: $searchText,
                hasSearchText: !trimmedSearchText.isEmpty,
                onClear: { searchText = "" }
            )

            List {
                if FontPickerSupport.shouldShowSystemDefaultRow(searchText: searchText) {
                    Button {
                        selectFont(JinTypography.systemFontPreferenceValue)
                    } label: {
                        FontPickerFontRow(
                            name: JinTypography.defaultFontDisplayName,
                            preview: FontPickerSupport.systemDefaultPreviewText,
                            previewFont: .system(size: 13),
                            isSelected: normalizedSelection.isEmpty
                        )
                    }
                    .buttonStyle(.plain)
                }

                Section("All Fonts") {
                    ForEach(filteredFamilies, id: \.self) { family in
                        Button {
                            selectFont(family)
                        } label: {
                            FontPickerFontRow(
                                name: family,
                                preview: FontPickerSupport.fontPreviewText,
                                previewFont: JinTypography.pickerPreviewFont(familyName: family),
                                isSelected: normalizedSelection == family
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.inset)
            .overlay {
                if let emptySearchText = FontPickerSupport.emptySearchText(
                    searchText: searchText,
                    filteredFamilies: filteredFamilies
                ) {
                    ContentUnavailableView.search(text: emptySearchText)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    private func selectFont(_ family: String) {
        selectedFontFamily = FontPickerSupport.selectedFontFamily(family)
    }
}
