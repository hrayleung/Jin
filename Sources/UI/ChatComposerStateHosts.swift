import SwiftUI

/// Wraps the composer-overlay subtree so the keystroke-driven re-evaluation
/// stays inside this view instead of bubbling up to ChatView. The trailing
/// closure receives a fresh binding to the editor text and the live
/// `canSendDraft` boolean.
struct ChatComposerBindingHost<Content: View>: View {
    @Bindable var composerTextStore: ComposerTextStore
    @Binding var draftAttachments: [DraftAttachment]
    @Binding var draftQuotes: [DraftQuote]
    let isImportingDropAttachments: Bool
    let content: (Binding<String>, Bool) -> Content

    private var canSendDraft: Bool {
        let hasText = !composerTextStore.text.trimmed.isEmpty
        let hasAttachments = !draftAttachments.isEmpty
        let hasQuotes = !draftQuotes.isEmpty
        return (hasText || hasAttachments || hasQuotes) && !isImportingDropAttachments
    }

    var body: some View {
        content($composerTextStore.text, canSendDraft)
    }
}

/// Computes `hasContent` for the collapsed composer chip without letting
/// ChatView's body read the composer text directly.
struct ChatCollapsedComposerBarHost: View {
    @Bindable var composerTextStore: ComposerTextStore
    let hasOtherContent: Bool
    let onExpand: () -> Void

    var body: some View {
        CollapsedComposerBar(
            hasContent: !composerTextStore.text.trimmed.isEmpty || hasOtherContent,
            onExpand: onExpand
        )
    }
}

/// Invisible observer that owns the `.onChange` for the composer text. Kept
/// separate from the binding host so that the change callback fires at most
/// once per keystroke, even when both compact and expanded composers are
/// mounted.
struct ChatComposerTextChangeObserver: View {
    @Bindable var composerTextStore: ComposerTextStore
    let onTextChange: (String) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .onChange(of: composerTextStore.text) { _, newValue in
                onTextChange(newValue)
            }
    }
}
