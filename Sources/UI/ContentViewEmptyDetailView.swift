import SwiftUI

struct ContentViewEmptyDetailView: View {
    let onNewChat: () -> Void

    var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
