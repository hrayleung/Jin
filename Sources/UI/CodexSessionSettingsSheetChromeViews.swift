import SwiftUI

struct CodexWorkingDirectoryPresetMenuItemLabel: View {
    let preset: CodexWorkingDirectoryPreset
    let isSelected: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(preset.name)
                Text(preset.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }
}

struct CodexWorkingDirectoryMenuLabel: View {
    let displayText: String
    let isDefault: Bool

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            Image(systemName: isDefault ? "minus" : "folder.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isDefault ? .secondary : .accentColor)

            Text(displayText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(isDefault ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            CodexMenuChevron()
        }
        .padding(.horizontal, JinSpacing.small + 2)
        .padding(.vertical, JinSpacing.small)
        .jinSurface(.subtle, cornerRadius: JinRadius.small)
    }
}

struct CodexSandboxModeTile: View {
    let mode: CodexSandboxMode
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            HStack(spacing: JinSpacing.xSmall) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(mode.displayName)
                    .font(.caption.weight(.semibold))
            }
            Text(mode.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(JinSpacing.small)
        .jinSurface(isSelected ? .selected : .subtle, cornerRadius: JinRadius.small)
    }
}

struct CodexDangerFullAccessWarning: View {
    var body: some View {
        Label("Full Access disables sandbox protection.", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}

struct CodexPersonalityMenuLabel: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 0)
            CodexMenuChevron()
        }
        .padding(.horizontal, JinSpacing.small + 2)
        .padding(.vertical, JinSpacing.small)
        .jinSurface(.subtle, cornerRadius: JinRadius.small)
    }
}

struct CodexSelectedMenuItemLabel: View {
    let title: String
    let isSelected: Bool

    init(_ title: String, isSelected: Bool) {
        self.title = title
        self.isSelected = isSelected
    }

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            Text(title)
            Spacer(minLength: 12)
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

private struct CodexMenuChevron: View {
    var body: some View {
        Image(systemName: "chevron.up.chevron.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
