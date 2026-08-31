import AppKit
import SwiftData
import SwiftUI

/// Isolates the `streamingStore` read to a per-row boundary so that
/// `ConversationStreamingStore.objectWillChange` only causes the affected
/// row — not every visible row — to re-evaluate.
struct SidebarConversationItem: View {
    let conversation: ConversationEntity
    let subtitle: String
    let providerIconID: String?
    let searchSnippet: String?
    let searchQuery: String
    let isRegeneratingTitle: Bool
    let selection: SidebarConversationSelectionState
    let selectionActions: SidebarConversationSelectionActions
    let onToggleStar: () -> Void
    let onRename: () -> Void
    let onRegenerateTitle: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var streamingStore: ConversationStreamingStore

    var body: some View {
        let isStreaming = streamingStore.isStreaming(conversationID: conversation.id)
        let isStarred = conversation.isStarred == true

        rowContent(isStarred: isStarred, isStreaming: isStreaming)
            .tag(conversation.id)
            .contentShape(Rectangle())
            // In selection mode the List has no selection binding, so clicks
            // reach this gesture instead of moving the row highlight.
            .selectionModeTap(isActive: selection.isSelectionModeActive) { extendingRange in
                selectionActions.toggle(extendingRange)
            }
            .contextMenu {
                if selection.appliesToBatch {
                    batchMenuItems
                } else {
                    singleChatMenuItems(isStarred: isStarred, isStreaming: isStreaming)
                }
            }
    }

    @ViewBuilder
    private func rowContent(isStarred: Bool, isStreaming: Bool) -> some View {
        HStack(spacing: JinSpacing.small) {
            if selection.isSelectionModeActive {
                Image(systemName: selection.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(selection.isSelected ? Color.accentColor : Color.secondary.opacity(0.65))
                    .accessibilityLabel(selection.isSelected ? "Selected" : "Not selected")
            }

            ConversationRowView(
                title: conversation.title,
                isStarred: isStarred,
                subtitle: subtitle,
                providerIconID: providerIconID,
                activityDate: ConversationActivitySupport.activityDate(for: conversation),
                isStreaming: isStreaming,
                searchSnippet: searchSnippet,
                searchQuery: searchQuery
            )
        }
        .background {
            // The List draws no highlight in selection mode (it has no
            // selection binding there), so checked rows tint themselves.
            if selection.isSelectionModeActive, selection.isSelected {
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .fill(JinSemanticColor.selectedSurface)
                    .padding(.horizontal, -JinSpacing.small)
            }
        }
    }

    @ViewBuilder
    private var batchMenuItems: some View {
        Button {
            selectionActions.batchStar()
        } label: {
            Label(
                ChatsSidebarSelectionSupport.starTitle(
                    shouldStar: selection.shouldStarBatch,
                    count: selection.batchCount
                ),
                systemImage: selection.shouldStarBatch ? "star" : "star.slash"
            )
        }

        Button {
            selectionActions.clearSelection()
        } label: {
            Label("Deselect All", systemImage: "circle.dashed")
        }

        Divider()

        Button(role: .destructive) {
            selectionActions.batchDelete()
        } label: {
            Label(
                ChatsSidebarSelectionSupport.deleteTitle(count: selection.batchCount),
                systemImage: "trash"
            )
        }
    }

    @ViewBuilder
    private func singleChatMenuItems(isStarred: Bool, isStreaming: Bool) -> some View {
        Button {
            onToggleStar()
        } label: {
            Label(isStarred ? "Unstar Chat" : "Star Chat", systemImage: isStarred ? "star.slash" : "star")
        }

        Button {
            onRename()
        } label: {
            Label("Rename Chat", systemImage: "pencil")
        }

        Button {
            onRegenerateTitle()
        } label: {
            Label(isRegeneratingTitle ? "Regenerating Title…" : "Regenerate Title", systemImage: "wand.and.stars")
        }
        .disabled(isStreaming || isRegeneratingTitle)

        Divider()

        Button {
            selectionActions.beginSelection()
        } label: {
            Label("Select Chats…", systemImage: "checklist")
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete Chat", systemImage: "trash")
        }
    }
}

private extension View {
    /// Attaches the selection-mode tap only while selection mode is on, so
    /// normal mode keeps the List's native click-to-open / ⌘-click / ⇧-click
    /// handling untouched.
    @ViewBuilder
    func selectionModeTap(isActive: Bool, action: @escaping (Bool) -> Void) -> some View {
        if isActive {
            onTapGesture {
                action(NSEvent.modifierFlags.contains(.shift))
            }
        } else {
            self
        }
    }
}

struct ConversationRowView: View {
    let title: String
    let isStarred: Bool
    let subtitle: String
    let providerIconID: String?
    let activityDate: Date
    let isStreaming: Bool
    let searchSnippet: String?
    let searchQuery: String

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall + 1) {
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
            .font(.system(size: 13, weight: .medium))

            if let searchSnippet {
                highlightedSnippet(searchSnippet, query: searchQuery)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                HStack(spacing: 4) {
                    ProviderIconView(iconID: providerIconID, fallbackSystemName: "network", size: 12)
                        .frame(width: 12, height: 12)
                    Text(subtitle)
                        .lineLimit(1)
                }
                Spacer()
                if isStreaming {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .help("Generating…")
                        .accessibilityLabel("Generating")
                }
                Text(activityDate, format: .relative(presentation: .named))
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
        .padding(.vertical, JinSpacing.xSmall + 1)
    }

    private func highlightedSnippet(_ text: String, query: String) -> Text {
        guard !query.isEmpty,
              let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(text)
        }

        let before = String(text[text.startIndex..<range.lowerBound])
        let match = String(text[range])
        let after = String(text[range.upperBound..<text.endIndex])

        return Text(before) + Text(match).bold().foregroundStyle(.primary) + Text(after)
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

                if let description = assistant.assistantDescription?.trimmedNonEmpty {
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
        let trimmed = AssistantGlyphRendering.normalizedGlyph(assistant.icon)
        return AssistantGlyphRendering.coreGlyph(trimmed: trimmed, pointSize: 16, weight: .semibold)
    }
}

struct AssistantTileView: View {
    let assistant: AssistantEntity
    let isSelected: Bool
    let showsName: Bool
    let showsIcon: Bool

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: showsIcon && showsName ? JinSpacing.small : 0) {
            if showsIcon {
                assistantIcon
                    .frame(width: 24, height: 24)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }

            if showsName {
                Text(assistant.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, JinSpacing.small)
        .padding(.horizontal, JinSpacing.small)
        .background {
            if isSelected || isHovered {
                RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                    .fill(isSelected ? JinSemanticColor.selectedSurface : JinSemanticColor.subtleSurface)
            }
        }
        .overlay {
            if isSelected || isHovered {
                RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                    .stroke(
                        isSelected ? JinSemanticColor.selectedStroke : JinSemanticColor.borderSubtle,
                        lineWidth: JinStrokeWidth.hairline
                    )
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous))
        .onHover { isHovered = $0 }
    }

    private var assistantIcon: some View {
        let trimmed = AssistantGlyphRendering.normalizedGlyph(assistant.icon)
        return AssistantGlyphRendering.coreGlyph(
            trimmed: trimmed,
            pointSize: JinControlMetrics.assistantGlyphSize,
            weight: .semibold
        )
    }
}
