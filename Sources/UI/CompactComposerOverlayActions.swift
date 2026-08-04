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
        .buttonStyle(.plain)
        .help("Hide composer")
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
        .buttonStyle(.plain)
        .help("Expand composer")
        .disabled(isBusy)
    }

    var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: sendButtonPresentation.compactSystemImage)
                .resizable()
                .symbolRenderingMode(.hierarchical)
                .frame(width: 22, height: 22)
                .foregroundStyle(isBusy ? Color.secondary : (canSendDraft ? Color.accentColor : .gray))
                // Soft morph between send ↔ stop so the busy flip doesn't pop.
                .contentTransition(.symbolEffect(.replace.downUp))
                .animation(JinMotion.sendGlyph, value: sendButtonPresentation.compactSystemImage)
                .animation(JinMotion.sendGlyph, value: isBusy)
        }
        .buttonStyle(.plain)
        .disabled(sendButtonPresentation.isDisabled)
        .padding(.bottom, 2)
        .accessibilityLabel(sendButtonPresentation.isBusy ? "Stop" : "Send")
    }
}
