import SwiftUI
import AppKit

// MARK: - Compact Composer Overlay

struct CompactComposerOverlayView<ControlsRow: View>: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @Binding var messageText: String
    @Binding var remoteVideoURLText: String
    @Binding var draftAttachments: [DraftAttachment]
    @Binding var draftQuotes: [DraftQuote]
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
    let onRemoveQuote: (DraftQuote) -> Void
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
    let controlsRow: () -> ControlsRow

    init(
        messageText: Binding<String>,
        remoteVideoURLText: Binding<String>,
        draftAttachments: Binding<[DraftAttachment]>,
        draftQuotes: Binding<[DraftQuote]>,
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
        onRemoveQuote: @escaping (DraftQuote) -> Void,
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
        _draftQuotes = draftQuotes
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
        self.onRemoveQuote = onRemoveQuote
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

    var sendButtonPresentation: ComposerSendButtonPresentation {
        ComposerSendButtonPresentation(
            usesCommandReturn: sendWithCommandEnter,
            isBusy: isBusy,
            canSendDraft: canSendDraft,
            isRecording: isRecording,
            isTranscribing: isTranscribing
        )
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)

        leftColumn
            .padding(JinSpacing.medium)
            .frame(maxWidth: ChatConversationLayoutMetrics.composerMaxWidth)
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
    }
}

extension CompactComposerOverlayView {
    func updateComposerTextContentHeight(to measuredHeight: CGFloat) {
        if let nextHeight = CompactComposerTextHeightMetrics.updatedHeight(
            current: composerTextContentHeight,
            measured: measuredHeight
        ) {
            composerTextContentHeight = nextHeight
        }
    }
}
