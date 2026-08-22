import SwiftUI

// MARK: - Composer State Hosts

/// Hosts the composer text editor. This is the **only** view whose body
/// re-evaluates while the user types: it reads `textStore.text` so external
/// writes (clear-on-submit, STT insertion, slash-token removal, failure
/// restore) still reach the NSTextView through `updateNSView`, while keeping
/// per-keystroke invalidation scoped to this leaf. Before this host existed
/// the whole composer — controls row, every `Menu` (whose content closures
/// SwiftUI evaluates eagerly at construction), capability chains — rebuilt on
/// every keystroke, which is what made typing lag.
struct ChatComposerEditorTextHost<Content: View>: View {
    @Bindable var textStore: ComposerTextStore
    let content: (Binding<String>) -> Content

    var body: some View {
        // Register the observation; `$textStore.text` alone would not.
        let _ = textStore.text
        content($textStore.text)
    }
}

/// Computes `canSendDraft` for a send button without letting the surrounding
/// composer body observe the composer text. Only this small subtree
/// re-evaluates when typing flips the draft between empty and non-empty.
struct ChatComposerCanSendHost<Content: View>: View {
    @Bindable var textStore: ComposerTextStore
    let draftAttachments: [DraftAttachment]
    let draftQuotes: [DraftQuote]
    let isImportingDropAttachments: Bool
    let content: (Bool) -> Content

    private var canSendDraft: Bool {
        let hasText = !textStore.text.trimmed.isEmpty
        let hasAttachments = !draftAttachments.isEmpty
        let hasQuotes = !draftQuotes.isEmpty
        return (hasText || hasAttachments || hasQuotes) && !isImportingDropAttachments
    }

    var body: some View {
        content(canSendDraft)
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
/// separate from the editor host so that the change callback fires at most
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
