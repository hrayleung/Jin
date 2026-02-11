import SwiftUI

struct FontPickerSheet: View {
    let title: String
    let subtitle: String
    @Binding var selectedFontFamily: String

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredFamilies: [String] {
        let query = trimmedSearchText
        guard !query.isEmpty else { return JinTypography.availableFontFamilies }

        return JinTypography.availableFontFamilies.filter {
            $0.localizedCaseInsensitiveContains(query)
        }
    }

    private var normalizedSelection: String {
        JinTypography.normalizedFontPreference(selectedFontFamily)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("Search fonts", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.body)
                if !trimmedSearchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            List {
                if trimmedSearchText.isEmpty {
                    Button {
                        selectFont(JinTypography.systemFontPreferenceValue)
                    } label: {
                        row(
                            name: JinTypography.defaultFontDisplayName,
                            preview: "Use the system default font.",
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
                            row(
                                name: family,
                                preview: "The quick brown fox jumps over 0123456789.",
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
                if filteredFamilies.isEmpty && !trimmedSearchText.isEmpty {
                    ContentUnavailableView.search(text: trimmedSearchText)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .background(JinSemanticColor.panelSurface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(JinSemanticColor.separator.opacity(0.4))
                .frame(height: JinStrokeWidth.hairline)
        }
    }

    private func row(name: String, preview: String, previewFont: Font, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(preview)
                    .font(previewFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func selectFont(_ family: String) {
        selectedFontFamily = JinTypography.normalizedFontPreference(family)
    }
}
