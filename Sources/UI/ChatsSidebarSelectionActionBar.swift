import SwiftUI

/// Bottom strip of the chats sidebar. Appears once a batch selection exists —
/// either because the user entered selection mode or because they ⌘/⇧-clicked
/// more than one row — and hosts the actions that apply to the whole set.
///
/// No background fill: the strip sits directly on the sidebar material
/// (Liquid Glass on macOS 26), so a solid panel here would read as a
/// box-in-box. A single hairline divider is enough separation.
struct ChatsSidebarSelectionActionBar: View {
    let selectedCount: Int
    let allVisibleSelected: Bool
    let hasVisibleConversations: Bool
    let shouldStarSelection: Bool
    let onToggleSelectAll: () -> Void
    let onToggleStar: () -> Void
    let onDelete: () -> Void
    let onDone: () -> Void

    @EnvironmentObject private var shortcutsStore: AppShortcutsStore

    private var hasSelection: Bool { selectedCount > 0 }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: JinSpacing.xSmall) {
                Button(action: onToggleSelectAll) {
                    Image(systemName: allVisibleSelected ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(glyphFont)
                        .foregroundStyle(allVisibleSelected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(JinIconButtonStyle(showBackground: false))
                .disabled(!hasVisibleConversations)
                .help(shortcutsStore.helpText(
                    allVisibleSelected ? "Deselect All" : "Select All",
                    for: .selectAllChats
                ))
                .accessibilityLabel(allVisibleSelected ? "Deselect all chats" : "Select all chats")
                // `.above`: this strip is the last thing in the sidebar, so a
                // badge placed below it would be clipped by the window edge.
                .shortcutHint(.selectAllChats, available: hasVisibleConversations, placement: .above)

                Text(ChatsSidebarSelectionSupport.selectionSummary(count: selectedCount))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel("\(selectedCount) chats selected")

                Spacer(minLength: 0)

                Button(action: onToggleStar) {
                    Image(systemName: shouldStarSelection ? "star" : "star.slash")
                        .font(glyphFont)
                }
                .buttonStyle(JinIconButtonStyle(showBackground: false))
                .disabled(!hasSelection)
                .help(ChatsSidebarSelectionSupport.starTitle(shouldStar: shouldStarSelection, count: selectedCount))

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(glyphFont)
                        .foregroundStyle(hasSelection ? Color.red : Color.secondary)
                }
                .buttonStyle(JinIconButtonStyle(showBackground: false))
                .disabled(!hasSelection)
                .help(shortcutsStore.helpText(
                    ChatsSidebarSelectionSupport.deleteTitle(count: selectedCount),
                    for: .deleteChat
                ))
                .shortcutHint(.deleteChat, available: hasSelection, placement: .above)

                Button(action: onDone) {
                    Image(systemName: "xmark")
                        .font(glyphFont)
                }
                .buttonStyle(JinIconButtonStyle(showBackground: false))
                .help("Done Selecting")
                .accessibilityLabel("Done selecting chats")
            }
            .padding(.horizontal, JinSpacing.small)
            .padding(.vertical, JinSpacing.xSmall)
        }
    }

    private var glyphFont: Font {
        .system(size: JinControlMetrics.iconButtonGlyphSize + 1, weight: .semibold)
    }
}
