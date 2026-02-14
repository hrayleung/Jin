import SwiftUI
import SwiftData

struct ConversationRowView: View {
    let title: String
    let isStarred: Bool
    let subtitle: String
    let providerIconID: String?
    let updatedAt: Date
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            HStack(spacing: 8) {
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.orange)
                        .help("Starred")
                }
            }
            .font(.headline)
            HStack {
                HStack(spacing: 4) {
                    ProviderIconView(iconID: providerIconID, fallbackSystemName: "network", size: 10)
                        .frame(width: 10, height: 10)
                    Text(subtitle)
                        .lineLimit(1)
                }
                Spacer()
                if isStreaming {
                    ProgressView()
                        .controlSize(.mini)
                        .help("Generating…")
                }
                Text(updatedAt, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, JinSpacing.small)
    }
}

struct AssistantRowView: View {
    let assistant: AssistantEntity
    let chatCount: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: JinSpacing.medium) {
            assistantIconView
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                Text(assistant.displayName)
                    .font(.system(.body, design: .default))
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let description = assistant.assistantDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if chatCount > 0 {
                Text("\(chatCount)")
                    .font(.system(.caption, design: .monospaced))
                    .jinTagStyle()
                    .accessibilityLabel("\(chatCount) chats")
            }
        }
        .padding(.vertical, JinSpacing.small)
    }

    private var assistantIconView: some View {
        let trimmed = (assistant.icon ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Group {
            if trimmed.isEmpty {
                Image(systemName: "person.crop.circle")
            } else if trimmed.count <= 2 {
                Text(trimmed)
            } else {
                Image(systemName: trimmed)
            }
        }
        .font(.system(size: 16, weight: .semibold))
    }
}

struct AssistantTileView: View {
    let assistant: AssistantEntity
    let isSelected: Bool
    let showsName: Bool
    let showsIcon: Bool

    var body: some View {
        VStack(spacing: showsIcon && showsName ? JinSpacing.small : 0) {
            if showsIcon {
                assistantIcon
                    .frame(width: 24, height: 24)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
            }

            if showsName {
                Text(assistant.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, JinSpacing.small)
        .padding(.horizontal, JinSpacing.small)
        .jinSurface(isSelected ? .selected : .neutral, cornerRadius: JinRadius.medium)
        .contentShape(RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous))
    }

    @ViewBuilder
    private var assistantIcon: some View {
        let trimmed = (assistant.icon ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Image(systemName: "person.crop.circle")
                .font(.system(size: JinControlMetrics.assistantGlyphSize, weight: .semibold))
        } else if trimmed.count <= 2 {
            Text(trimmed)
                .font(.system(size: JinControlMetrics.assistantGlyphSize, weight: .semibold))
        } else {
            Image(systemName: trimmed)
                .font(.system(size: JinControlMetrics.assistantGlyphSize, weight: .semibold))
        }
    }
}
