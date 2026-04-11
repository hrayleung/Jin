import SwiftUI

struct SidebarHeaderView: View {
    let assistantDisplayName: String
    let onNewChat: () -> Void
    let onHideSidebar: () -> Void
    let shortcutsStore: AppShortcutsStore

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Chats")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(assistantDisplayName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onHideSidebar) {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
            }
            .buttonStyle(JinIconButtonStyle(showBackground: false))
            .help("Hide Sidebar")

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
        .padding(.horizontal, JinSpacing.medium)
        .padding(.top, JinSpacing.large)
        .padding(.bottom, JinSpacing.small)
        .frame(minHeight: 44)
    }
}
