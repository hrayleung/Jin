import SwiftUI

struct ContentViewEmptyDetailHeaderView: View {
    let isSidebarVisible: Bool
    let leadingPadding: CGFloat
    let assistantSettingsShortcut: KeyboardShortcut?
    let onToggleSidebar: () -> Void
    let onNewChat: () -> Void
    let onOpenAssistantSettings: () -> Void

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            if !isSidebarVisible {
                Button(action: onToggleSidebar) {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
                }
                .buttonStyle(JinIconButtonStyle(showBackground: false))
                .help("Show Sidebar")

                Button(action: onNewChat) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
                }
                .buttonStyle(JinIconButtonStyle(showBackground: false))
                .help("New Chat")
            }

            Spacer(minLength: 0)

            Button(action: onOpenAssistantSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
            }
            .buttonStyle(JinIconButtonStyle())
            .help("Assistant Settings")
            .keyboardShortcut(assistantSettingsShortcut)
        }
        .padding(.leading, leadingPadding)
        .padding(.trailing, JinSpacing.medium)
        .padding(.top, JinSpacing.small)
        .padding(.bottom, JinSpacing.small)
        .frame(minHeight: 38)
        .background(JinSemanticColor.detailSurface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(JinSemanticColor.separator.opacity(0.45))
                .frame(height: JinStrokeWidth.hairline)
        }
    }
}
