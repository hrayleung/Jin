import SwiftUI
import AppKit

// MARK: - Compact Composer Overlay

struct CompactComposerOverlayView<ControlsRow: View>: View {
    @Binding var messageText: String
    @Binding var remoteVideoURLText: String
    @Binding var draftAttachments: [DraftAttachment]
    @Binding var isComposerDropTargeted: Bool
    @Binding var isComposerFocused: Bool
    @Binding var composerTextContentHeight: CGFloat

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
    let onDropFileURLs: ([URL]) -> Bool
    let onDropImages: ([NSImage]) -> Bool
    let onSubmit: () -> Void
    let onCancel: () -> Bool
    let onRemoveAttachment: (DraftAttachment) -> Void
    let onExpand: () -> Void
    let onHide: () -> Void
    let onSend: () -> Void
    let slashCommandServers: [SlashCommandMCPServerItem]
    let isSlashCommandActive: Bool
    let slashCommandFilterText: String
    let slashCommandHighlightedIndex: Int
    let perMessageMCPChips: [SlashCommandMCPServerItem]
    let onSlashCommandSelectServer: (String) -> Void
    let onSlashCommandDismiss: () -> Void
    let onRemovePerMessageMCPServer: (String) -> Void
    let onInterceptKeyDown: ((UInt16) -> Bool)?
    private let controlsRow: () -> ControlsRow

    init(
        messageText: Binding<String>,
        remoteVideoURLText: Binding<String>,
        draftAttachments: Binding<[DraftAttachment]>,
        isComposerDropTargeted: Binding<Bool>,
        isComposerFocused: Binding<Bool>,
        composerTextContentHeight: Binding<CGFloat>,
        contextUsageEstimate: ChatContextUsageEstimate? = nil,
        currentModelName: String? = nil,
        sendWithCommandEnter: Bool,
        isBusy: Bool,
        canSendDraft: Bool,
        showsRemoteVideoURLField: Bool,
        isPreparingToSend: Bool,
        prepareToSendStatus: String?,
        isRecording: Bool,
        isTranscribing: Bool,
        recordingDurationText: String,
        transcribingStatusText: String,
        onDropFileURLs: @escaping ([URL]) -> Bool,
        onDropImages: @escaping ([NSImage]) -> Bool,
        onSubmit: @escaping () -> Void,
        onCancel: @escaping () -> Bool,
        onRemoveAttachment: @escaping (DraftAttachment) -> Void,
        onExpand: @escaping () -> Void,
        onHide: @escaping () -> Void,
        onSend: @escaping () -> Void,
        slashCommandServers: [SlashCommandMCPServerItem] = [],
        isSlashCommandActive: Bool = false,
        slashCommandFilterText: String = "",
        slashCommandHighlightedIndex: Int = 0,
        perMessageMCPChips: [SlashCommandMCPServerItem] = [],
        onSlashCommandSelectServer: @escaping (String) -> Void = { _ in },
        onSlashCommandDismiss: @escaping () -> Void = {},
        onRemovePerMessageMCPServer: @escaping (String) -> Void = { _ in },
        onInterceptKeyDown: ((UInt16) -> Bool)? = nil,
        @ViewBuilder controlsRow: @escaping () -> ControlsRow
    ) {
        _messageText = messageText
        _remoteVideoURLText = remoteVideoURLText
        _draftAttachments = draftAttachments
        _isComposerDropTargeted = isComposerDropTargeted
        _isComposerFocused = isComposerFocused
        _composerTextContentHeight = composerTextContentHeight
        self.contextUsageEstimate = contextUsageEstimate
        self.currentModelName = currentModelName
        self.sendWithCommandEnter = sendWithCommandEnter
        self.isBusy = isBusy
        self.canSendDraft = canSendDraft
        self.showsRemoteVideoURLField = showsRemoteVideoURLField
        self.isPreparingToSend = isPreparingToSend
        self.prepareToSendStatus = prepareToSendStatus
        self.isRecording = isRecording
        self.isTranscribing = isTranscribing
        self.recordingDurationText = recordingDurationText
        self.transcribingStatusText = transcribingStatusText
        self.onDropFileURLs = onDropFileURLs
        self.onDropImages = onDropImages
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.onRemoveAttachment = onRemoveAttachment
        self.onExpand = onExpand
        self.onHide = onHide
        self.onSend = onSend
        self.slashCommandServers = slashCommandServers
        self.isSlashCommandActive = isSlashCommandActive
        self.slashCommandFilterText = slashCommandFilterText
        self.slashCommandHighlightedIndex = slashCommandHighlightedIndex
        self.perMessageMCPChips = perMessageMCPChips
        self.onSlashCommandSelectServer = onSlashCommandSelectServer
        self.onSlashCommandDismiss = onSlashCommandDismiss
        self.onRemovePerMessageMCPServer = onRemovePerMessageMCPServer
        self.onInterceptKeyDown = onInterceptKeyDown
        self.controlsRow = controlsRow
    }

    private var trimmedRemoteVideoURLText: String {
        remoteVideoURLText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)

        HStack(alignment: .bottom, spacing: JinSpacing.medium) {
            leftColumn
            trailingActions
        }
        .padding(JinSpacing.medium)
        .frame(maxWidth: 800)
        .background {
            shape.fill(.regularMaterial)
        }
        .overlay(
            shape.stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: JinStrokeWidth.hairline)
        )
        .overlay(
            shape.stroke(isComposerDropTargeted ? Color.accentColor : Color.clear, lineWidth: JinStrokeWidth.emphasized)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 2) {
                hideButton
                expandButton
            }
            .padding(.top, JinSpacing.medium)
            .padding(.trailing, JinSpacing.medium)
        }
    }

    @ViewBuilder
    private var trailingActions: some View {
        HStack(alignment: .center, spacing: JinSpacing.small) {
            if let contextUsageEstimate {
                ContextUsageIndicatorView(
                    estimate: contextUsageEstimate,
                    modelName: currentModelName
                )
                .padding(.bottom, 2)
            }

            sendButton
        }
    }

    @ViewBuilder
    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            perMessageMCPChipsRow
            attachmentChipsRow
            remoteVideoInputRow
            composerTextEditor
            controlsRow()
            prepareStatusRow
            speechStatusRow
        }
    }

    @ViewBuilder
    private var perMessageMCPChipsRow: some View {
        if !perMessageMCPChips.isEmpty {
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

    @ViewBuilder
    private var attachmentChipsRow: some View {
        if !draftAttachments.isEmpty {
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

    @ViewBuilder
    private var remoteVideoInputRow: some View {
        if showsRemoteVideoURLField {
            HStack(spacing: JinSpacing.small) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)

                TextField("Public video URL (optional, for video edit)", text: $remoteVideoURLText)
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
                    .help("Clear video URL")
                    .disabled(isBusy)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .jinSurface(.subtle, cornerRadius: JinRadius.medium)
        }
    }

    @ViewBuilder
    private var composerTextEditor: some View {
        DroppableTextEditor(
            text: $messageText,
            isDropTargeted: $isComposerDropTargeted,
            isFocused: $isComposerFocused,
            placeholder: "Write a message",
            font: NSFont.preferredFont(forTextStyle: .body),
            useCommandEnterToSubmit: sendWithCommandEnter,
            onDropFileURLs: onDropFileURLs,
            onDropImages: onDropImages,
            onSubmit: onSubmit,
            onCancel: onCancel,
            onContentHeightChanged: { height in
                let clamped = max(36, min(height, 120))
                if abs(composerTextContentHeight - clamped) > 0.5 {
                    composerTextContentHeight = clamped
                }
            },
            onInterceptKeyDown: onInterceptKeyDown
        )
        .frame(height: composerTextContentHeight)
    }

    @ViewBuilder
    private var prepareStatusRow: some View {
        if isPreparingToSend, let prepareToSendStatus {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(prepareToSendStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var speechStatusRow: some View {
        if isRecording {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Text("Recording… \(recordingDurationText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        } else if isTranscribing {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(transcribingStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    private var hideButton: some View {
        Button(action: onHide) {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Hide composer (\u{21E7}\u{2318}H)")
    }

    private var expandButton: some View {
        Button(action: onExpand) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Expand composer (⇧⌘E)")
        .disabled(isBusy)
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: isBusy ? "stop.circle.fill" : "arrow.up.circle.fill")
                .resizable()
                .symbolRenderingMode(.hierarchical)
                .frame(width: 22, height: 22)
                .foregroundStyle(isBusy ? Color.secondary : (canSendDraft ? Color.accentColor : .gray))
        }
        .buttonStyle(.plain)
        .disabled((!canSendDraft && !isBusy) || isRecording || isTranscribing)
        .padding(.bottom, 2)
    }
}
