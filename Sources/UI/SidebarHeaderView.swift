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
        .padding(.leading, leadingPadding)
        .padding(.trailing, JinSpacing.medium)
        .padding(.top, topPadding)
        .padding(.bottom, JinSpacing.small)
        .frame(minHeight: 44)
    }

    private var leadingPadding: CGFloat {
        guard extendsContentIntoTitlebar, hasMeasuredTitlebarControls else {
            return JinSpacing.medium
        }

        return max(JinSpacing.medium, titlebarLeadingInset)
    }

    private var hasMeasuredTitlebarControls: Bool {
        titlebarLeadingInset.isFinite && titlebarLeadingInset > JinSpacing.medium
    }

    private var topPadding: CGFloat {
        guard extendsContentIntoTitlebar else { return JinSpacing.large }
        return max(JinSpacing.large, titlebarTopInset)
    }
}
