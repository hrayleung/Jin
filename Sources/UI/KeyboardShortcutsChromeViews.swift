import SwiftUI

struct KeyboardShortcutSettingsRow: View {
    let title: String
    let displayLabel: String
    let isCustomized: Bool
    let onEdit: () -> Void

    var body: some View {
        Button {
            onEdit()
        } label: {
            HStack(spacing: JinSpacing.small) {
                titleText
                customBadge
                Spacer(minLength: JinSpacing.small)
                ShortcutKeyCapsule(label: displayLabel)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Edit shortcut")
    }

    private var titleText: some View {
        Text(title)
            .font(.system(.body, design: .default))
            .fontWeight(.medium)
            .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var customBadge: some View {
        if isCustomized {
            Text("Custom")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(JinSemanticColor.subtleSurface)
                )
        }
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
            .font(.system(.caption, design: .monospaced))
    }
}

private struct ShortcutKeyCapsule: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(minWidth: 56, alignment: .center)
            .background(
                capsuleBackground
            )
            .overlay(
                capsuleBorder
            )
    }

    private var capsuleBackground: some View {
        Capsule(style: .continuous)
            .fill(JinSemanticColor.subtleSurface)
    }

    private var capsuleBorder: some View {
        Capsule(style: .continuous)
            .stroke(JinSemanticColor.separator.opacity(0.5), lineWidth: JinStrokeWidth.hairline)
    }
}
