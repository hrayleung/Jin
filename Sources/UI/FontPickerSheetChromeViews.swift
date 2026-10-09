import SwiftUI

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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
