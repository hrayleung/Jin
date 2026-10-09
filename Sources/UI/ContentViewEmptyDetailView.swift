import SwiftUI

struct ContentViewEmptyDetailView: View {
    let onNewChat: () -> Void

    var body: some View {
        VStack(spacing: JinSpacing.large) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(JinSemanticColor.textTertiary)
                .accessibilityHidden(true)

            VStack(spacing: JinSpacing.xSmall + 2) {
                Text("Start a conversation")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Choose a chat from the sidebar, or start with something new.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 300)

            Button(action: onNewChat) {
                Label("New Chat", systemImage: "square.and.pencil")
            }
                .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.horizontal, JinSpacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
