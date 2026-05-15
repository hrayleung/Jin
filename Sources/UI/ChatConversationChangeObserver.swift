import SwiftUI

/// Isolates the streaming-frequency SwiftData reads (`messages.count`,
/// `updatedAt`) into a 0-sized child view so they don't widen the observation
/// scope of `ChatView.body`. Every token write fires this view's `.onChange`
/// callbacks instead of invalidating the entire chat tree.
struct ChatConversationChangeObserver: View {
    @Bindable var conversation: ConversationEntity
    let onMessageCountChanged: () -> Void
    let onUpdatedAtChanged: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: conversation.messages.count) { _, _ in
                onMessageCountChanged()
            }
            .onChange(of: conversation.updatedAt) { _, _ in
                onUpdatedAtChanged()
            }
    }
}
