import SwiftUI

struct SidebarHeaderView: View {
    let assistantDisplayName: String
    let extendsContentIntoTitlebar: Bool
    let titlebarLeadingInset: CGFloat
    let titlebarTopInset: CGFloat
    let onNewChat: () -> Void
    let onHideSidebar: () -> Void
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

            // Sidebar-toggle is now provided by NavigationSplitView's system
            // chrome (auto Liquid Glass on macOS 26). New Chat + Settings stay
            // inline here because they're frequently used and a dedicated
            // sidebar location keeps the chat-side toolbar lean.
            Button(action: onNewChat) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
            }
            .buttonStyle(JinIconButtonStyle(showBackground: false))
            .keyboardShortcut(shortcutsStore.keyboardShortcut(for: .newChat))
            .help("New Chat")

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
            }
            .buttonStyle(JinIconButtonStyle(showBackground: false))
            .keyboardShortcut(",", modifiers: [.command])
            .help("Settings")
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
        // now (no more .fullSizeContentView / .windowStyle(.hiddenTitleBar)),
        // so the sidebar content starts below the titlebar automatically and
        // doesn't need to reserve space for traffic lights.
        JinSpacing.small
    }
}
