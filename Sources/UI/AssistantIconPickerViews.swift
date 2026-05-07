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
        let trimmed = AssistantGlyphRendering.normalizedGlyph(selectedIcon)
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
