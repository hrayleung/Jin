import SwiftUI
import AppKit

// MARK: - Constants

enum AttachmentConstants {
    static let maxDraftAttachments = 8
    static let maxAttachmentBytes = 25 * 1024 * 1024
    static let maxPDFExtractedCharacters = 120_000
    static let maxSpreadsheetExtractedCharacters = 120_000
    static let maxMistralOCRImagesToAttach = 8
    static let maxMistralOCRTotalImageBytes = 12 * 1024 * 1024
}

// MARK: - Error

struct AttachmentImportError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}

// MARK: - Draft Attachment

struct DraftAttachment: Identifiable, Hashable, Sendable {
    let id: UUID
    let filename: String
    let mimeType: String
    let fileURL: URL
    let extractedText: String?

    var isImage: Bool { mimeType.hasPrefix("image/") }
    var isVideo: Bool { mimeType.hasPrefix("video/") }
    var isAudio: Bool { mimeType.hasPrefix("audio/") }
    var isPDF: Bool { mimeType == "application/pdf" }
}

// MARK: - Draft Attachment Chip

struct DraftAttachmentChip: View {
    let attachment: DraftAttachment
    let onRemove: () -> Void

    private static let maxLabelWidth: CGFloat = 220

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            thumbnailView
                .frame(width: 26, height: 26)

            Text(attachment.filename)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: Self.maxLabelWidth, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, JinSpacing.medium - 2)
        .padding(.vertical, JinSpacing.xSmall + 2)
        .jinSurface(.neutral, cornerRadius: JinRadius.medium)
        .onDrag {
            NSItemProvider(contentsOf: attachment.fileURL)
                ?? NSItemProvider(object: attachment.fileURL as NSURL)
        }
        .help(attachment.filename)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(attachment.filename)
        .contextMenu {
            chipContextMenu
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if attachment.isImage, let image = NSImage(contentsOf: attachment.fileURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
        } else if attachment.isAudio {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
        } else if attachment.isVideo {
            Image(systemName: "video")
                .foregroundStyle(.secondary)
        } else if attachment.isPDF {
            Image(systemName: "doc.richtext")
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var chipContextMenu: some View {
        Button {
            NSWorkspace.shared.open(attachment.fileURL)
        } label: {
            Label("Open", systemImage: "arrow.up.right.square")
        }

        Button {
            NSWorkspace.shared.activateFileViewerSelecting([attachment.fileURL])
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        Divider()

        if attachment.isImage, let image = NSImage(contentsOf: attachment.fileURL) {
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([image])
            } label: {
                Label("Copy Image", systemImage: "doc.on.doc")
            }
        }

        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(attachment.fileURL.path, forType: .string)
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            onRemove()
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }
}

// MARK: - Per-Message MCP Chip

struct PerMessageMCPChip: View {
    let name: String
    let onRemove: () -> Void

    private static let maxLabelWidth: CGFloat = 180

    var body: some View {
        HStack(spacing: JinSpacing.xSmall) {
            Text(name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: Self.maxLabelWidth, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, JinSpacing.medium - 2)
        .padding(.vertical, JinSpacing.xSmall + 2)
        .background(
            Capsule()
                .fill(JinSemanticColor.accentSurface)
        )
        .overlay(
            Capsule()
                .stroke(JinSemanticColor.selectedStroke, lineWidth: JinStrokeWidth.hairline)
        )
        .help(name)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
    }
}

// MARK: - Composer Control Icon

struct ComposerControlIconLabel: View {
    let systemName: String
    let isActive: Bool
    let badgeText: String?
    let activeColor: Color

    init(systemName: String, isActive: Bool, badgeText: String?, activeColor: Color = .accentColor) {
        self.systemName = systemName
        self.isActive = isActive
        self.badgeText = badgeText
        self.activeColor = activeColor
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? activeColor : Color.secondary)
                .frame(width: JinControlMetrics.iconButtonHitSize, height: JinControlMetrics.iconButtonHitSize)
                .background(
                    Circle()
                        .fill(isActive ? activeColor.opacity(0.18) : Color.clear)
                )
                .overlay(
                    Circle()
                        .stroke(isActive ? JinSemanticColor.separator.opacity(0.45) : Color.clear, lineWidth: JinStrokeWidth.hairline)
                )
                .shadow(color: isActive ? activeColor.opacity(0.35) : Color.clear, radius: 6, x: 0, y: 0)

            if let badgeText, !badgeText.isEmpty {
                Text(badgeText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .padding(.horizontal, JinSpacing.xSmall)
                    .padding(.vertical, 1)
                    .foregroundStyle(.primary)
                    .background(
                        Capsule()
                            .fill(JinSemanticColor.surface)
                    )
                    .overlay(
                        Capsule()
                            .stroke(JinSemanticColor.separator.opacity(0.7), lineWidth: JinStrokeWidth.hairline)
                    )
                    .offset(x: JinSpacing.xSmall, y: JinSpacing.xSmall)
            }
        }
    }
}

private struct ComposerEditorSurface<Content: View>: View {
    let isFocused: Bool
    let isDropTargeted: Bool
    @ViewBuilder let content: () -> Content

    private var borderColor: Color {
        if isDropTargeted {
            return Color.accentColor.opacity(0.7)
        }
        if isFocused {
            return Color.accentColor.opacity(0.34)
        }
        return JinSemanticColor.separator.opacity(0.5)
    }

    private var shadowColor: Color {
        if isDropTargeted {
            return Color.accentColor.opacity(0.16)
        }
        if isFocused {
            return Color.accentColor.opacity(0.10)
        }
        return Color.black.opacity(0.04)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)

        VStack(alignment: .leading, spacing: JinSpacing.small) {
            content()
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small + 2)
        .background {
            shape.fill(JinSemanticColor.textSurface)
        }
        .overlay(
            shape.stroke(
                borderColor,
                lineWidth: isDropTargeted ? JinStrokeWidth.emphasized : JinStrokeWidth.hairline
            )
        )
        .shadow(color: shadowColor, radius: isFocused || isDropTargeted ? 12 : 4, x: 0, y: isFocused || isDropTargeted ? 2 : 0)
        .animation(.easeInOut(duration: 0.14), value: isFocused)
        .animation(.easeInOut(duration: 0.14), value: isDropTargeted)
    }
}

private struct ComposerStatusSummaryView: View {
    let isPreparingToSend: Bool
    let prepareToSendStatus: String?
    let isRecording: Bool
    let isTranscribing: Bool
    let recordingDurationText: String
    let transcribingStatusText: String

    @ViewBuilder
    var body: some View {
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
            .accessibilityElement(children: .combine)
        } else if isRecording {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("Recording… \(recordingDurationText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
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
            .accessibilityElement(children: .combine)
        }
    }
}

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

// MARK: - Collapsed Composer Bar

struct CollapsedComposerBar: View {
    let hasContent: Bool
    let onExpand: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)

        Button(action: onExpand) {
            HStack(spacing: JinSpacing.medium) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)

                Text(hasContent ? "Continue typing\u{2026}" : "Type a message\u{2026}")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, JinSpacing.large)
            .padding(.vertical, 10)
            .frame(maxWidth: 800)
            .background {
                shape.fill(.regularMaterial)
            }
            .overlay(
                shape.stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: JinStrokeWidth.hairline)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show message composer")
        .accessibilityHint("Double-click to expand the message input area")
    }
}

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
