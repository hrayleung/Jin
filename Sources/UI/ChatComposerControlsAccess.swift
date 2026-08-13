import SwiftUI

/// Scopes observation of `ComposerControlsStore` to the composer chrome.
/// The trailing closure is executed from this view's body so a thinking /
/// search / MCP write does not re-evaluate `ChatView`.
struct ChatComposerControlsAccess<Content: View>: View {
    @Bindable var store: ComposerControlsStore
    let content: () -> Content

    init(
        store: ComposerControlsStore,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.store = store
        self.content = content
    }

    var body: some View {
        let _ = store.controls
        content()
            // Menu / Picker actions inherit an implicit animation transaction.
            // Composer chrome should snap, not interpolate under the menu.
            .transaction { transaction in
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
    }
}
