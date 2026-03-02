import SwiftUI

struct SidebarHeaderView: View {
    let assistantDisplayName: String
    let onNewChat: () -> Void
    let onHideSidebar: () -> Void
    let shortcutsStore: AppShortcutsStore
    let titleBarClearance: CGFloat

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Chats")
                    .font(.system(size: 13, weight: .semibold))

                Text(assistantDisplayName)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
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
        .padding(.top, titleBarClearance)
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small)
        .frame(minHeight: 38)
        .background(JinSemanticColor.sidebarSurface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(JinSemanticColor.separator.opacity(0.45))
                .frame(height: JinStrokeWidth.hairline)
        }
    }
}
