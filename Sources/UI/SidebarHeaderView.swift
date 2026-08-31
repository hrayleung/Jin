import SwiftUI

struct SidebarHeaderView: View {
    @Environment(\.openSettings) private var openSettings

    let assistantDisplayName: String
    let extendsContentIntoTitlebar: Bool
    let titlebarLeadingInset: CGFloat
    let titlebarTopInset: CGFloat
    let onNewChat: () -> Void
    let onHideSidebar: () -> Void
    @Binding var isChatSelectionModeActive: Bool
    let shortcutsStore: AppShortcutsStore

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Chats")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Text(assistantDisplayName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(1)

            Spacer(minLength: JinSpacing.small)

            // Sidebar toggle lives in the column toolbar (`MainSidebarToggleButton`)
            // so it occupies the system title-bar slot. Select / New Chat /
            // Settings stay inline here because they're frequently used and a
            // dedicated sidebar location keeps the chat-side toolbar lean.
            //
            // Select is the discoverable entry to multi-select; ⌘-click and
            // ⇧-click in the list work without it.
            Button {
                isChatSelectionModeActive.toggle()
            } label: {
                Image(systemName: isChatSelectionModeActive ? "checklist.checked" : "checklist")
                    .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
                    .foregroundStyle(isChatSelectionModeActive ? Color.accentColor : Color.primary)
            }
            .buttonStyle(JinIconButtonStyle(showBackground: false))
            .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .selectChats))
            .help(shortcutsStore.helpText(
                isChatSelectionModeActive ? "Done Selecting Chats" : "Select Chats",
                for: .selectChats
            ))
            .accessibilityLabel(isChatSelectionModeActive ? "Done selecting chats" : "Select chats")
            .shortcutHint(.selectChats, placement: .overlayBottom)

            Button(action: onNewChat) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
            }
            .buttonStyle(JinIconButtonStyle(showBackground: false))
            .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .newChat))
            .help(shortcutsStore.helpText("New Chat", for: .newChat))
            .shortcutHint(.newChat, placement: .overlayBottom)

            Button(action: { openSettings() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
            }
            .buttonStyle(JinIconButtonStyle(showBackground: false))
            .keyboardShortcut(",", modifiers: [.command])
            .help("Settings (⌘,)")
            .fixedShortcutHint(.command(","), placement: .overlayBottom)
        }
        .padding(.leading, leadingPadding)
        .padding(.trailing, JinSpacing.medium)
        .padding(.top, topPadding)
        .padding(.bottom, JinSpacing.small)
        .frame(minHeight: 44)
    }

    private var leadingPadding: CGFloat {
        JinSpacing.medium
    }

    private var topPadding: CGFloat {
        // Natural small padding. The system titlebar lives above this view
        // (no .fullSizeContentView on the main window), so the sidebar
        // content starts below the titlebar automatically and doesn't
        // need to reserve space for traffic lights.
        JinSpacing.small
    }
}
