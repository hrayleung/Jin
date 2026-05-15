import SwiftUI

extension ChatView {

    func chatLifecycle<Content: View>(_ content: Content) -> some View {
        content
            .onAppear(perform: handleChatAppear)
            .onDisappear {
                handleChatDisappear()
            }
            .onChange(of: conversationEntity.id) { _, _ in
                handleConversationSwitch()
            }
            .onChange(of: editingUserMessageText) { _, newValue in
                updateSlashCommandState(for: newValue, target: .editMessage)
            }
            // `conversationEntity.messages.count` and `.updatedAt` are observed
            // inside `ChatConversationChangeObserver` (a 0-sized child view) so
            // streaming-token writes don't re-evaluate `ChatView.body`.
            .background(
                ChatConversationChangeObserver(
                    conversation: conversationEntity,
                    onMessageCountChanged: rebuildMessageCachesIfNeeded,
                    onUpdatedAtChanged: scheduleUpdatedAtDrivenCacheRebuild
                )
            )
            .onChange(of: contextUsageRefreshToken) { _, _ in
                refreshContextUsageEstimate()
            }
            .task {
                // Chat-local state is already prepared in onAppear / onChange.
                // Avoid repeating these mutations here to prevent extra render churn.
                await refreshExtensionCredentialsStatus()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pluginCredentialsDidChange)) { _ in
                Task {
                    await refreshExtensionCredentialsStatus()
                }
            }
            .focusedSceneValue(\.chatActions, chatFocusedActions)
    }

    func handleChatDisappear() {
        renderCache.cancelPendingWork()
        contextUsageRefreshTask?.cancel()
        contextUsageRefreshTask = nil
        draftContextUsageRefreshTask?.cancel()
        draftContextUsageRefreshTask = nil
        flushPendingPersistenceSave()
    }

    func scheduleUpdatedAtDrivenCacheRebuild() {
        // Debounce updatedAt-driven cache rebuilds so that rapid successive
        // updates (e.g. tool-call loops persisting messages back-to-back) are
        // coalesced into a single rebuild.
        renderCache.scheduleDebouncedRebuild(after: .milliseconds(150)) {
            rebuildMessageCachesIfNeeded()
        }
    }
}
