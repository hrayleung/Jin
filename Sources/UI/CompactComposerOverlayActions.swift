import SwiftUI

extension CompactComposerOverlayView {
    var hideButton: some View {
        Button(action: onHide) {
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(JinSemanticColor.textTertiary)
                .frame(width: JinControlMetrics.iconButtonHitSize, height: JinControlMetrics.iconButtonHitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(JinIconButtonStyle(showBackground: false))
        .help(shortcutsStore.helpText("Hide composer", for: .toggleComposerVisibility))
        .accessibilityLabel("Hide composer")
        .shortcutHint(.toggleComposerVisibility)
    }

    var expandButton: some View {
        Button(action: onExpand) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(JinSemanticColor.textTertiary)
                .frame(width: JinControlMetrics.iconButtonHitSize, height: JinControlMetrics.iconButtonHitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(JinIconButtonStyle(showBackground: false))
        .help(shortcutsStore.helpText("Expand composer", for: .expandComposer))
        .accessibilityLabel("Expand composer")
        .shortcutHint(.expandComposer)
    }

    func sendButton(canSendDraft: Bool) -> some View {
        let presentation = sendButtonPresentation(canSendDraft: canSendDraft)
        return Button(action: onSend) {
            Image(systemName: presentation.compactSystemImage)
                .resizable()
                .symbolRenderingMode(.hierarchical)
                .frame(width: 26, height: 26)
                .foregroundStyle(isBusy ? Color.secondary : (canSendDraft ? Color.accentColor : .gray))
                // Soft morph between send ↔ stop so the busy flip doesn't pop.
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace.downUp))
                .animation(reduceMotion ? nil : JinMotion.sendGlyph, value: presentation.compactSystemImage)
                .animation(reduceMotion ? nil : JinMotion.sendGlyph, value: isBusy)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(presentation.isDisabled)
        .padding(.bottom, 2)
        .accessibilityLabel(presentation.isBusy ? "Stop" : "Send")
        .help(
            isBusy
                ? shortcutsStore.helpText("Stop", for: .stopGenerating)
                : (sendWithCommandEnter ? "Send (⌘↩)" : "Send")
        )
        .shortcutHint(.stopGenerating, available: isBusy)
        .fixedShortcutHint(
            sendWithCommandEnter
                ? AppShortcutBinding(key: .returnKey, modifiers: [.command])
                : nil,
            available: !isBusy && !presentation.isDisabled
        )
    }
}
