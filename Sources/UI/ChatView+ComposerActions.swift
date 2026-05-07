import SwiftUI

// MARK: - Composer Actions

extension ChatView {

    func removeDraftQuote(_ quote: DraftQuote) {
        withAnimation(quoteListAnimation) {
            draftQuotes.removeAll { $0.id == quote.id }
        }
    }

    var fullPageDropOverlay: some View {
        ZStack {
            Color.accentColor.opacity(0.08)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Drop to attach")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous))
        }
        .allowsHitTesting(false)
        .opacity(isFullPageDropTargeted ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: isFullPageDropTargeted)
    }

    var chatFocusedActions: ChatFocusedActions {
        ChatFocusedActions(
            canAttach: !isBusy,
            canStopStreaming: isBusy,
            isComposerHidden: isComposerHidden,
            focusComposer: {
                if isComposerHidden {
                    showComposer()
                } else {
                    isComposerFocused = true
                }
            },
            openModelPicker: { isModelPickerPresented.toggle() },
            openAddModelPicker: { isAddModelPickerPresented.toggle() },
            attach: { isFileImporterPresented = true },
            stopStreaming: {
                guard isBusy else { return }
                sendMessage()
            },
            toggleExpandedComposer: {
                if isExpandedComposerPresented {
                    isExpandedComposerPresented = false
                } else {
                    isComposerFocused = false
                    isExpandedComposerPresented = true
                }
            },
            toggleComposerVisibility: toggleComposerVisibility
        )
    }
}
