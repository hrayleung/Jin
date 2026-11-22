import SwiftUI

struct KeyboardShortcutSettingsRow: View {
    let title: String
    let binding: AppShortcutBinding?
    let isCustomized: Bool
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: JinSpacing.small) {
                Text(title)
                    .foregroundStyle(.primary)
                customBadge
                Spacer(minLength: JinSpacing.small)
                ShortcutKeycaps(binding: binding)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Edit shortcut")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Edit shortcut")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var customBadge: some View {
        if isCustomized {
            Text("Edited")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(JinSemanticColor.controlFill)
                )
        }
    }

    private var accessibilityValue: String {
        let shortcut = binding?.displayLabel ?? "No shortcut"
        return isCustomized ? "\(shortcut), edited" : shortcut
    }
}

struct ShortcutEditorCurrentDefaultLabel: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            titleText
            valueText
        }
        .font(.caption)
    }

    private var titleText: some View {
        Text(title + ":")
            .foregroundStyle(.secondary)
    }

    private var valueText: some View {
        Text(value)
            .foregroundStyle(.primary)
    }
}

/// A shortcut drawn the way a keyboard shows it: one cap per key.
struct ShortcutKeycaps: View {
    let binding: AppShortcutBinding?

    var body: some View {
        if let binding {
            HStack(spacing: 3) {
                ForEach(Array(Self.keys(for: binding).enumerated()), id: \.offset) { _, key in
                    keycap(key)
                }
            }
        } else {
            Text("None")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }

    static func keys(for binding: AppShortcutBinding) -> [String] {
        binding.modifiers.displaySymbols.map(String.init) + [binding.key.displayText]
    }

    private func keycap(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .frame(minWidth: 22, minHeight: 22)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(JinSemanticColor.controlFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(JinSemanticColor.borderSubtle, lineWidth: JinStrokeWidth.hairline)
            }
    }
}
