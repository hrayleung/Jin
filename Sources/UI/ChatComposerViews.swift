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

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            thumbnailView
                .frame(width: 26, height: 26)

            Text(attachment.filename)
                .font(.caption)
                .lineLimit(1)

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

    var body: some View {
        HStack(spacing: JinSpacing.xSmall) {
            Text(name)
                .font(.callout.weight(.medium))
                .lineLimit(1)

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

// MARK: - Compact Composer Overlay

struct CompactComposerOverlayView<ControlsRow: View>: View {
    @Binding var messageText: String
    @Binding var remoteVideoURLText: String
    @Binding var draftAttachments: [DraftAttachment]
    @Binding var isComposerDropTargeted: Bool
    @Binding var isComposerFocused: Bool
    @Binding var composerTextContentHeight: CGFloat

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
            sendButton
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
        ZStack(alignment: .topLeading) {
            if messageText.isEmpty {
                Text("Type a message...")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .padding(.leading, 6)
            }

            DroppableTextEditor(
                text: $messageText,
                isDropTargeted: $isComposerDropTargeted,
                isFocused: $isComposerFocused,
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

struct ExpandedComposerOverlay: View {
    @Binding var messageText: String
    @Binding var remoteVideoURLText: String
    @Binding var draftAttachments: [DraftAttachment]
    @Binding var isPresented: Bool
    @Binding var isComposerDropTargeted: Bool

    let isBusy: Bool
    let canSendDraft: Bool
    let showsRemoteVideoURLField: Bool
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

    @State private var isEditorFocused = true

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

    var body: some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            panelContent
                .frame(maxWidth: 720, maxHeight: 560)
                .background {
                    RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)
                        .fill(.regularMaterial)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)
                        .stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: JinStrokeWidth.hairline)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 8)
                .padding(40)
        }
    }

    private var panelContent: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider()
            panelSlashCommandPopover
            panelPerMessageMCPChips
            panelAttachmentChips
            panelRemoteVideoURLField
            panelEditor
            Divider()
            panelFooter
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
            .padding(.horizontal, JinSpacing.large)
            .padding(.vertical, JinSpacing.small)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.easeOut(duration: 0.12), value: isSlashCommandActive)
        }
    }

    @ViewBuilder
    private var panelPerMessageMCPChips: some View {
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
                .padding(.horizontal, JinSpacing.large)
                .padding(.vertical, JinSpacing.small)
            }
        }
    }

    private var panelHeader: some View {
        HStack {
            Text("Compose")
                .font(.headline)

            Spacer()

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.secondary.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, JinSpacing.large)
        .padding(.vertical, JinSpacing.medium)
    }

    @ViewBuilder
    private var panelAttachmentChips: some View {
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
                .padding(.horizontal, JinSpacing.large)
                .padding(.vertical, JinSpacing.small)
            }
        }
    }

    @ViewBuilder
    private var panelRemoteVideoURLField: some View {
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
                    .disabled(isBusy)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, JinSpacing.large)
            .padding(.top, JinSpacing.small)
            .jinSurface(.subtle, cornerRadius: JinRadius.medium)
        }
    }

    private var panelEditor: some View {
        ZStack(alignment: .topLeading) {
            if messageText.isEmpty {
                Text("Type a message...")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
                    .padding(.leading, 6)
            }

            DroppableTextEditor(
                text: $messageText,
                isDropTargeted: $isComposerDropTargeted,
                isFocused: $isEditorFocused,
                font: NSFont.preferredFont(forTextStyle: .body),
                useCommandEnterToSubmit: true,
                onDropFileURLs: onDropFileURLs,
                onDropImages: onDropImages,
                onSubmit: {
                    guard canSendDraft, !isBusy else { return }
                    onSend()
                },
                onCancel: {
                    isPresented = false
                    return true
                },
                onInterceptKeyDown: onInterceptKeyDown
            )
        }
        .padding(.horizontal, JinSpacing.large)
        .frame(maxHeight: .infinity)
    }

    private var panelFooter: some View {
        HStack(spacing: JinSpacing.small) {
            Text("\(wordCount) words \u{00B7} \(characterCount) characters")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Spacer()

            Text("\u{2318}\u{21A9}")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button {
                guard canSendDraft, !isBusy else { return }
                onSend()
            } label: {
                HStack(spacing: 4) {
                    Text("Send")
                        .font(.body.weight(.medium))
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.body)
                }
                .foregroundStyle(canSendDraft && !isBusy ? Color.accentColor : .gray)
            }
            .buttonStyle(.plain)
            .disabled(!canSendDraft || isBusy)
        }
        .padding(.horizontal, JinSpacing.large)
        .padding(.vertical, JinSpacing.medium)
    }
}
