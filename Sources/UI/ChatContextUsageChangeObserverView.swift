import SwiftUI

/// Owns the context-usage refresh token so `ChatView.body` does not read
/// `ComposerControlsStore.controls` on every thinking / search / MCP write.
struct ChatContextUsageChangeObserverView: View {
    @Bindable var store: ComposerControlsStore
    let token: (GenerationControls) -> ContextUsageRefreshToken?
    let onTokenChange: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: token(store.controls)) { _, _ in
                onTokenChange()
            }
    }
}
