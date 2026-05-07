import SwiftUI

struct ContentViewEmptyDetailView: View {
    let sidebarWidth: CGFloat
    let isSidebarHidden: Bool
    let compensationRatio: CGFloat
    let onNewChat: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let visibleWidth = ChatConversationLayoutMetrics.visibleContainerWidth(
                containerWidth: geometry.size.width,
                sidebarWidth: sidebarWidth,
                isSidebarHidden: isSidebarHidden
            )
            let offset = ChatConversationLayoutMetrics.sidebarCompensationOffset(
                sidebarWidth: sidebarWidth,
                isSidebarHidden: isSidebarHidden,
                compensationRatio: compensationRatio
            )

            VStack(spacing: JinSpacing.large) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.tertiary)

                VStack(spacing: JinSpacing.xSmall + 2) {
                    Text("No Conversation Selected")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Pick a conversation from the sidebar, or start a new one.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                Button("New Chat", action: onNewChat)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(.horizontal, JinSpacing.xLarge)
            .frame(width: visibleWidth, height: geometry.size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: offset)
        }
    }
}
