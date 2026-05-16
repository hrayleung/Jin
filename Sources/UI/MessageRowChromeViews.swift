import SwiftUI

// MARK: - User Message MCP Badge Row

struct UserMessageMCPBadgeRow: View {
    let serverNames: [String]

    var body: some View {
        if !normalizedServerNames.isEmpty {
            HStack(spacing: JinSpacing.xSmall) {
                badgeIcon
                ForEach(normalizedServerNames, id: \.self) { name in
                    serverBadge(name)
                }
            }
        }
    }

    private var normalizedServerNames: [String] {
        MessageRowPresentationSupport.normalizedMCPServerNames(serverNames)
    }

    private var badgeIcon: some View {
        Image(systemName: "hammer")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private func serverBadge(_ name: String) -> some View {
        Text(name)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(JinSemanticColor.subtleSurface)
            )
    }
}

// MARK: - Header

struct MessageRowHeaderView: View {
    let isUser: Bool
    let isTool: Bool
    let assistantDisplayName: String
    let assistantModelLabel: String?
    let providerIconID: String?

    var body: some View {
        if isUser {
            EmptyView()
        } else {
            headerRow
                .padding(.horizontal, JinSpacing.medium)
                .padding(.bottom, 2)
        }
    }

    private var headerRow: some View {
        HStack(spacing: JinSpacing.small - 2) {
            if !isTool {
                ProviderBadgeIcon(iconID: providerIconID)
            }

            identityLabel
            modelLabel
        }
    }

    @ViewBuilder
    private var identityLabel: some View {
        if isTool {
            Image(systemName: "hammer")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Tool Output")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if assistantDisplayName != "Assistant" {
            Text(assistantDisplayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var modelLabel: some View {
        if !isTool, let label = normalizedAssistantModelLabel {
            Text(label)
                .jinTagStyle()
        }
    }

    private var normalizedAssistantModelLabel: String? {
        MessageRowPresentationSupport.normalizedAssistantModelLabel(assistantModelLabel)
    }
}

struct ProviderBadgeIcon: View {
    let iconID: String?

    var body: some View {
        ProviderIconView(iconID: iconID, fallbackSystemName: "network", size: 14)
            .frame(width: 14, height: 14)
    }
}

// MARK: - Collapsed Preview

struct CollapsedAssistantPreviewView: View {
    let preview: LightweightMessagePreview
    let onExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            previewHeader
            previewFooter
        }
        .frame(maxWidth: 420, alignment: .leading)
    }

    private var previewHeader: some View {
        HStack(alignment: .top, spacing: JinSpacing.small) {
            previewIcon
            previewText
            Spacer(minLength: 0)
        }
    }

    private var previewIcon: some View {
        Image(systemName: preview.containsCode ? "curlybraces.square" : "doc.text")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 18)
    }

    private var previewText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(preview.headline)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            if !preview.body.isEmpty {
                Text(preview.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var previewFooter: some View {
        HStack(spacing: JinSpacing.small) {
            if preview.containsCode {
                Text("Code")
                    .jinTagStyle()
            }

            if preview.lineCount > 1 {
                Text("\(preview.lineCount) lines")
                    .font(.caption)
                    .foregroundStyle(JinSemanticColor.textTertiary)
            }

            Spacer(minLength: 0)
            expandButton
        }
    }

    private var expandButton: some View {
        Button("Expand") {
            onExpand()
        }
        .buttonStyle(.borderless)
        .font(.caption.weight(.semibold))
    }
}
