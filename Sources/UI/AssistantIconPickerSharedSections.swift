import SwiftUI

struct AssistantNoIconCard: View {
    @Binding var draftIcon: String

    var body: some View {
        Button {
            draftIcon = ""
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "xmark.circle").font(.system(size: 18))
                    .frame(width: 32, height: 32)
                Text("No Icon")
                if draftIcon.isEmpty {
                    Image(systemName: "checkmark").font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                draftIcon.isEmpty ? JinSemanticColor.selectedSurface : Color.clear,
                in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(draftIcon.isEmpty ? .isSelected : [])
    }
}

struct AssistantIconPickerEmptySearchLabel: View {
    var body: some View {
        Text("No matches.")
            .font(.body)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
    }
}
