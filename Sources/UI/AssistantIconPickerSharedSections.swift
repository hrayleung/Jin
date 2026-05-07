import SwiftUI

struct AssistantNoIconCard: View {
    @Binding var draftIcon: String

    var body: some View {
        JinSettingsCard(spacing: 12, padding: 12, cornerRadius: JinRadius.medium) {
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
