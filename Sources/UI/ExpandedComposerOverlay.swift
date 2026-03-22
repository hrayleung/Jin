import SwiftUI
import AppKit

// MARK: - Expanded Composer Overlay

struct ExpandedComposerOverlay<ControlsRow: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var messageText: String
    @Binding var remoteVideoURLText: String
    @Binding var draftAttachments: [DraftAttachment]
    @Binding var isPresented: Bool
    @Binding var isComposerDropTargeted: Bool

    let contextUsageEstimate: ChatContextUsageEstimate?
    let currentModelName: String?
    let sendWithCommandEnter: Bool
    let isBusy: Bool
    let canSendDraft: Bool
    let showsRemoteVideoURLField: Bool
    let isPreparingToSend: Bool
    let prepareToSendStatus: String?
    let isRecording: Bool
    let isTranscribing: Bool
    let recordingDurationText: String
    let transcribingStatusText: String
    let onCollapse: () -> Void
    let onHide: () -> Void
    let onSend: () -> Void
    let onDropFileURLs: ([URL]) -> Bool
    let onDropImages: ([NSImage]) -> Bool
    let onRemoveAttachment: (DraftAttachment) -> Void
    let slashCommandServers: [SlashCommandMCPServerItem]
    let isSlashCommandActive: Bool
    let slashCommandFilterText: String
    let slashCommandHighlightedIndex: Int
    let perMessageMCPChips: [SlashCommandMCPServerItem]
    let onSlashCommandSelectServer: (String) -> Void
    let onSlashCommandDismiss: () -> Void
    let onRemovePerMessageMCPServer: (String) -> Void
    let onInterceptKeyDown: ((UInt16) -> Bool)?
    let controlsRow: () -> ControlsRow

    @State private var isEditorFocused = false

    private let panelCornerRadius: CGFloat = 26

    private var wordCount: Int {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    private var characterCount: Int {
        messageText.count
    }

    private var trimmedRemoteVideoURLText: String {
        remoteVideoURLText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var draftSummary: String {
        guard characterCount > 0 else { return "0 words · 0 characters" }

        let wordLabel = wordCount == 1 ? "1 word" : "\(wordCount) words"
        let characterLabel = characterCount == 1 ? "1 character" : "\(characterCount) characters"
        return "\(wordLabel) · \(characterLabel)"
    }

    private var submitShortcutLabel: String {
        sendWithCommandEnter ? "⌘↩ Send" : "↩ Send"
    }

    private var primaryActionDisabled: Bool {
        ((!canSendDraft && !isBusy) || isRecording || isTranscribing)
    }

    private var primaryActionTitle: String {
        isBusy ? "Stop" : "Send"
    }

    private var primaryActionSymbol: String {
        isBusy ? "stop.fill" : "arrow.up"
    }

    private var panelStrokeColor: Color {
        isComposerDropTargeted ? Color.accentColor.opacity(0.6) : JinSemanticColor.separator.opacity(0.55)
    }

    @ViewBuilder
    private var inlineAccessoryRows: some View {
        if !perMessageMCPChips.isEmpty {
            accessorySection(title: "Servers", systemName: "hammer") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: JinSpacing.small) {
                        ForEach(perMessageMCPChips) { chip in
                            PerMessageMCPChip(
                                name: chip.name,
                                onRemove: { onRemovePerMessageMCPServer(chip.id) }
                            )
                        }
                    }
                    .padding(.horizontal, JinSpacing.xSmall)
                }
            }
        }

        if !draftAttachments.isEmpty {
            accessorySection(title: "Attachments", systemName: "paperclip") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: JinSpacing.small) {
                        ForEach(draftAttachments) { attachment in
                            DraftAttachmentChip(
                                attachment: attachment,
                                onRemove: { onRemoveAttachment(attachment) }
                            )
                        }
                    }
                    .padding(.horizontal, JinSpacing.xSmall)
                }
            }
        }

        if showsRemoteVideoURLField {
            accessorySection(title: "Video URL", systemName: "link") {
                remoteVideoURLField
            }
        }
    }

    var body: some View {
        panelShell
            .frame(minWidth: 760, idealWidth: 820, maxWidth: 860, minHeight: 560, idealHeight: 640, maxHeight: 680)
            .background(sheetBackground)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.02 : 0.08)) {
                    guard isPresented else { return }
                    isEditorFocused = true
                }
            }
            .onDisappear {
                isEditorFocused = false
            }
    }

    private var sheetBackground: some View {
        ZStack {
            JinSemanticColor.panelSurface

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(reduceMotion ? 0.04 : 0.08),
                    JinSemanticColor.panelSurface.opacity(0.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var panelShell: some View {
        VStack(alignment: .leading, spacing: JinSpacing.large) {
            panelHeader
            panelSlashCommandPopover
            inlineAccessoryRows
            editorSection
            controlsSection
            panelFooter
        }
        .padding(JinSpacing.xLarge)
        .background {
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .fill(JinSemanticColor.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .stroke(panelStrokeColor, lineWidth: isComposerDropTargeted ? JinStrokeWidth.emphasized : JinStrokeWidth.hairline)
        }
    }

    @ViewBuilder
    private var panelSlashCommandPopover: some View {
        if isSlashCommandActive {
            SlashCommandMCPPopover(
                servers: slashCommandServers,
                filterText: slashCommandFilterText,
                highlightedIndex: slashCommandHighlightedIndex,
                onSelectServer: onSlashCommandSelectServer,
                onDismiss: onSlashCommandDismiss
            )
            .padding(.horizontal, JinSpacing.small)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.easeOut(duration: 0.12), value: isSlashCommandActive)
        }
    }

    private func accessorySection<Content: View>(
        title: String,
        systemName: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Label(title, systemImage: systemName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            content()
        }
        .padding(JinSpacing.medium)
        .jinSurface(.subtle, cornerRadius: JinRadius.large)
    }

    private var panelHeader: some View {
        HStack(alignment: .top, spacing: JinSpacing.large) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Compose Message")
                    .font(.title3.weight(.semibold))
            }

            Spacer(minLength: JinSpacing.medium)

            HStack(spacing: JinSpacing.small) {
                headerActionButton(systemName: "arrow.down.right.and.arrow.up.left", help: "Compact composer") {
                    isPresented = false
                    onCollapse()
                }
                .keyboardShortcut(.escape, modifiers: [])

                headerActionButton(systemName: "chevron.down", help: "Hide composer") {
                    isPresented = false
                    onHide()
                }
            }
        }
    }

    private func headerActionButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
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

    private var remoteVideoURLField: some View {
        HStack(spacing: JinSpacing.small) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)

            TextField("Source video URL", text: $remoteVideoURLText)
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

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Message")
                    .font(.headline)
            }

            ComposerEditorSurface(
                isFocused: isEditorFocused,
                isDropTargeted: isComposerDropTargeted
            ) {
                DroppableTextEditor(
                    text: $messageText,
                    isDropTargeted: $isComposerDropTargeted,
                    isFocused: $isEditorFocused,
                    placeholder: "Write a message",
                    font: NSFont.preferredFont(forTextStyle: .body),
                    useCommandEnterToSubmit: sendWithCommandEnter,
                    onDropFileURLs: onDropFileURLs,
                    onDropImages: onDropImages,
                    onSubmit: {
                        guard !primaryActionDisabled else { return }
                        onSend()
                    },
                    onCancel: {
                        isPresented = false
                        onCollapse()
                        return true
                    },
                    onInterceptKeyDown: onInterceptKeyDown
                )
                .frame(minHeight: 320, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var controlsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            controlsRow()
                .padding(.vertical, 2)
        }
        .padding(JinSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jinSurface(.subtle, cornerRadius: JinRadius.large)
    }

    private var panelFooter: some View {
        HStack(alignment: .bottom, spacing: JinSpacing.large) {
            VStack(alignment: .leading, spacing: 6) {
                Text(draftSummary)
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

            Spacer(minLength: 0)

            HStack(spacing: JinSpacing.medium) {
                if let contextUsageEstimate {
                    ContextUsageIndicatorView(
                        estimate: contextUsageEstimate,
                        modelName: currentModelName
                    )
                }

                Text(sendWithCommandEnter ? "⌘↩" : "↩")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospaced()

                Button {
                    onSend()
                } label: {
                    Label(primaryActionTitle, systemImage: primaryActionSymbol)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(isBusy ? .red : .accentColor)
                .keyboardShortcut(.return, modifiers: sendWithCommandEnter ? [.command] : [])
                .disabled(primaryActionDisabled)
            }
        }
    }
}

// MARK: - Composer Meta Badge

private struct ComposerMetaBadge: View {
    let systemName: String
    let text: String

    private static let maxLabelWidth: CGFloat = 240

    var body: some View {
        Label(text, systemImage: systemName)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: Self.maxLabelWidth)
            .padding(.horizontal, JinSpacing.medium)
            .padding(.vertical, JinSpacing.small)
            .background(
                Capsule(style: .continuous)
                    .fill(JinSemanticColor.subtleSurface)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(JinSemanticColor.separator.opacity(0.5), lineWidth: JinStrokeWidth.hairline)
            )
            .help(text)
    }
}
