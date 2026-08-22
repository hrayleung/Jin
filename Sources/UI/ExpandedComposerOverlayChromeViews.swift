import SwiftUI

struct ExpandedComposerHeader: View {
    @EnvironmentObject private var shortcutsStore: AppShortcutsStore

    let onCollapse: () -> Void
    let onHide: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: JinSpacing.large) {
            Spacer(minLength: 0)

            HStack(spacing: JinSpacing.small) {
                ExpandedComposerHeaderActionButton(
                    systemName: "arrow.down.right.and.arrow.up.left",
                    help: shortcutsStore.helpText("Compact composer", for: .expandComposer),
                    action: onCollapse
                )
                .keyboardShortcut(.escape, modifiers: [])
                .shortcutHint(.expandComposer)

                ExpandedComposerHeaderActionButton(
                    systemName: "chevron.down",
                    help: shortcutsStore.helpText("Hide composer", for: .toggleComposerVisibility),
                    action: onHide
                )
                .shortcutHint(.toggleComposerVisibility)
            }
        }
    }
}

private struct ExpandedComposerHeaderActionButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                        .fill(JinSemanticColor.subtleSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                        .stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: JinStrokeWidth.hairline)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct ExpandedComposerAccessorySection<Content: View>: View {
    let title: String
    let systemName: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Label(title, systemImage: systemName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            content()
        }
        .padding(JinSpacing.medium)
        .jinSurface(.subtle, cornerRadius: JinRadius.large)
    }
}

struct ExpandedComposerControlsSection<ControlsRow: View>: View {
    @ViewBuilder let controlsRow: () -> ControlsRow

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            controlsRow()
                .padding(.vertical, 2)
        }
        .padding(JinSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jinSurface(.subtle, cornerRadius: JinRadius.large)
    }
}

struct ExpandedComposerFooter: View {
    let draftMetrics: ComposerDraftTextMetrics
    let contextUsageEstimate: ChatContextUsageEstimate?
    let currentModelName: String?
    let sendWithCommandEnter: Bool
    let isBusy: Bool
    let isPreparingToSend: Bool
    let prepareToSendStatus: String?
    let isRecording: Bool
    let isTranscribing: Bool
    let recordingDurationText: String
    let transcribingStatusText: String
    let sendButtonPresentation: ComposerSendButtonPresentation
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: JinSpacing.large) {
            statusColumn

            Spacer(minLength: 0)

            actionCluster
        }
    }

    private var statusColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(draftMetrics.summaryText)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            ComposerStatusSummaryView(
                isPreparingToSend: isPreparingToSend,
                prepareToSendStatus: prepareToSendStatus,
                isRecording: isRecording,
                isTranscribing: isTranscribing,
                recordingDurationText: recordingDurationText,
                transcribingStatusText: transcribingStatusText
            )
        }
    }

    private var actionCluster: some View {
        HStack(spacing: JinSpacing.medium) {
            if let contextUsageEstimate {
                ContextUsageIndicatorView(
                    estimate: contextUsageEstimate,
                    modelName: currentModelName
                )
                .equatable()
            }

            Text(sendButtonPresentation.shortcutGlyph)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospaced()

            Button {
                onSend()
            } label: {
                Label(
                    sendButtonPresentation.expandedTitle,
                    systemImage: sendButtonPresentation.expandedSystemImage
                )
                .contentTransition(.symbolEffect(.replace.downUp))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(isBusy ? .red : .accentColor)
            .animation(JinMotion.sendGlyph, value: sendButtonPresentation.expandedSystemImage)
            .animation(JinMotion.sendGlyph, value: isBusy)
            .keyboardShortcut(.return, modifiers: sendWithCommandEnter ? [.command] : [])
            .disabled(sendButtonPresentation.isDisabled)
            .shortcutHint(.stopGenerating, available: isBusy)
            .fixedShortcutHint(
                sendWithCommandEnter
                    ? AppShortcutBinding(key: .returnKey, modifiers: [.command])
                    : nil,
                available: !isBusy && !sendButtonPresentation.isDisabled
            )
        }
    }
}
