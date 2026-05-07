import SwiftUI

struct ExpandedComposerHeader: View {
    let onCollapse: () -> Void
    let onHide: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: JinSpacing.large) {
            Spacer(minLength: 0)

            HStack(spacing: JinSpacing.small) {
                ExpandedComposerHeaderActionButton(
                    systemName: "arrow.down.right.and.arrow.up.left",
                    help: "Compact composer",
                    action: onCollapse
                )
                .keyboardShortcut(.escape, modifiers: [])

                ExpandedComposerHeaderActionButton(
                    systemName: "chevron.down",
                    help: "Hide composer",
                    action: onHide
                )
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

struct ExpandedComposerRemoteVideoURLField: View {
    @Binding var remoteVideoURLText: String

    let isBusy: Bool

    private var trimmedRemoteVideoURLText: String {
        remoteVideoURLText.trimmed
    }

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)

            TextField("Source Video URL", text: $remoteVideoURLText)
                .textFieldStyle(.plain)
                .font(.callout)
                .disabled(isBusy)

            if !trimmedRemoteVideoURLText.isEmpty {
                Button {
                    remoteVideoURLText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small + 2)
        .background(
            RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                .fill(JinSemanticColor.textSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                .stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: JinStrokeWidth.hairline)
        )
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
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(isBusy ? .red : .accentColor)
            .keyboardShortcut(.return, modifiers: sendWithCommandEnter ? [.command] : [])
            .disabled(sendButtonPresentation.isDisabled)
        }
    }
}
