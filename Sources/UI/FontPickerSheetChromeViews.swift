import SwiftUI

struct FontPickerHeader: View {
    let title: String
    let subtitle: String
    let onDone: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            titleBlock
            Spacer(minLength: 0)
            doneButton
        }
        .padding(16)
        .background(JinSemanticColor.panelSurface)
        .overlay(alignment: .bottom) {
            bottomDivider
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var doneButton: some View {
        Button("Done") {
            onDone()
        }
        .keyboardShortcut(.defaultAction)
    }

    private var bottomDivider: some View {
        Rectangle()
            .fill(JinSemanticColor.separator.opacity(0.4))
            .frame(height: JinStrokeWidth.hairline)
    }
}

struct FontPickerSearchField: View {
    @Binding var searchText: String

    let hasSearchText: Bool
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            searchIcon
            searchInput
            clearButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var searchIcon: some View {
        Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)
            .font(.system(size: 12))
    }

    private var searchInput: some View {
        TextField("Search fonts", text: $searchText)
            .textFieldStyle(.plain)
            .font(.body)
    }

    @ViewBuilder
    private var clearButton: some View {
        if hasSearchText {
            Button {
                onClear()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
    }
}

struct FontPickerFontRow: View {
    let name: String
    let preview: String
    let previewFont: Font
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            fontPreviewText
            Spacer(minLength: 0)
            selectedIndicator
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var fontPreviewText: some View {
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
    }

    @ViewBuilder
    private var selectedIndicator: some View {
        if isSelected {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
    }
}
