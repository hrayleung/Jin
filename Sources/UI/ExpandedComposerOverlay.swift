import SwiftUI
import AppKit

// MARK: - Expanded Composer Overlay

struct ExpandedComposerOverlay<ControlsRow: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Not observed from this body — see `CompactComposerOverlayView`. The
    // editor host and the footer observe the store themselves so typing does
    // not rebuild the controls row and its eagerly-evaluated menus.
    let composerTextStore: ComposerTextStore
    @Binding var draftAttachments: [DraftAttachment]
    @Binding var draftQuotes: [DraftQuote]
    @Binding var isPresented: Bool
    @Binding var isComposerDropTargeted: Bool

    let contextUsageEstimate: ChatContextUsageEstimate?
    let currentModelName: String?
    let sendWithCommandEnter: Bool
    let isBusy: Bool
    let isImportingDropAttachments: Bool
    /// Value, not a `Binding` — see `CompactComposerOverlayView`.
    let remoteVideoURLText: String
    let supportsRemoteVideoURLInput: Bool
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
    let onRemoveRemoteVideoURL: () -> Void
    let onRemoveQuote: (DraftQuote) -> Void
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

    init(
        composerTextStore: ComposerTextStore,
        draftAttachments: Binding<[DraftAttachment]>,
        draftQuotes: Binding<[DraftQuote]>,
        isPresented: Binding<Bool>,
        isComposerDropTargeted: Binding<Bool>,
        contextUsageEstimate: ChatContextUsageEstimate?,
        currentModelName: String?,
        sendWithCommandEnter: Bool,
        isBusy: Bool,
        isImportingDropAttachments: Bool,
        remoteVideoURLText: String,
        supportsRemoteVideoURLInput: Bool,
        isPreparingToSend: Bool,
        prepareToSendStatus: String?,
        isRecording: Bool,
        isTranscribing: Bool,
        recordingDurationText: String,
        transcribingStatusText: String,
        onCollapse: @escaping () -> Void,
        onHide: @escaping () -> Void,
        onSend: @escaping () -> Void,
        onDropFileURLs: @escaping ([URL]) -> Bool,
        onDropImages: @escaping ([NSImage]) -> Bool,
        onRemoveAttachment: @escaping (DraftAttachment) -> Void,
        onRemoveRemoteVideoURL: @escaping () -> Void,
        onRemoveQuote: @escaping (DraftQuote) -> Void,
        slashCommandServers: [SlashCommandMCPServerItem],
        isSlashCommandActive: Bool,
        slashCommandFilterText: String,
        slashCommandHighlightedIndex: Int,
        perMessageMCPChips: [SlashCommandMCPServerItem],
        onSlashCommandSelectServer: @escaping (String) -> Void,
        onSlashCommandDismiss: @escaping () -> Void,
        onRemovePerMessageMCPServer: @escaping (String) -> Void,
        onInterceptKeyDown: ((UInt16) -> Bool)?,
        @ViewBuilder controlsRow: @escaping () -> ControlsRow
    ) {
        self.composerTextStore = composerTextStore
        _draftAttachments = draftAttachments
        _draftQuotes = draftQuotes
        _isPresented = isPresented
        _isComposerDropTargeted = isComposerDropTargeted
        self.contextUsageEstimate = contextUsageEstimate
        self.currentModelName = currentModelName
        self.sendWithCommandEnter = sendWithCommandEnter
        self.isBusy = isBusy
        self.isImportingDropAttachments = isImportingDropAttachments
        self.remoteVideoURLText = remoteVideoURLText
        self.supportsRemoteVideoURLInput = supportsRemoteVideoURLInput
        self.isPreparingToSend = isPreparingToSend
        self.prepareToSendStatus = prepareToSendStatus
        self.isRecording = isRecording
        self.isTranscribing = isTranscribing
        self.recordingDurationText = recordingDurationText
        self.transcribingStatusText = transcribingStatusText
        self.onCollapse = onCollapse
        self.onHide = onHide
        self.onSend = onSend
        self.onDropFileURLs = onDropFileURLs
        self.onDropImages = onDropImages
        self.onRemoveAttachment = onRemoveAttachment
        self.onRemoveRemoteVideoURL = onRemoveRemoteVideoURL
        self.onRemoveQuote = onRemoveQuote
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

    private func sendButtonPresentation(canSendDraft: Bool) -> ComposerSendButtonPresentation {
        ComposerSendButtonPresentation(
            usesCommandReturn: sendWithCommandEnter,
            isBusy: isBusy,
            canSendDraft: canSendDraft,
            isRecording: isRecording,
            isTranscribing: isTranscribing
        )
    }

    /// Read outside body evaluation only (submit handlers).
    private var currentCanSendDraft: Bool {
        let hasText = !composerTextStore.text.trimmed.isEmpty
        return (hasText || !draftAttachments.isEmpty || !draftQuotes.isEmpty) && !isImportingDropAttachments
    }

    private var showsRemoteVideoURLChip: Bool {
        supportsRemoteVideoURLInput && !remoteVideoURLText.trimmed.isEmpty
    }

    private var panelStrokeColor: Color {
        isComposerDropTargeted ? Color.accentColor.opacity(0.6) : JinSemanticColor.separator.opacity(0.55)
    }

    @ViewBuilder
    private var inlineAccessoryRows: some View {
        if !perMessageMCPChips.isEmpty {
            ExpandedComposerAccessorySection(title: "MCP Servers", systemName: "hammer") {
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

        if !draftQuotes.isEmpty {
            ExpandedComposerAccessorySection(title: "Quotes", systemName: "quote.opening") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: JinSpacing.small) {
                        ForEach(draftQuotes) { quote in
                            ComposerQuoteCardView(quote: quote) {
                                onRemoveQuote(quote)
                            }
                            .equatable()
                            .transition(ComposerQuoteCardView.transition(reduceMotion: reduceMotion))
                        }
                    }
                    .padding(.horizontal, JinSpacing.xSmall)
                    .padding(.vertical, 2)
                }
            }
        }

        if !draftAttachments.isEmpty || showsRemoteVideoURLChip {
            ExpandedComposerAccessorySection(title: "Attachments", systemName: "paperclip") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: JinSpacing.small) {
                        // Leads the row: there is at most one, and it is the
                        // subject of the turn rather than one of N attachments.
                        if showsRemoteVideoURLChip {
                            ComposerRemoteVideoURLChip(
                                urlText: remoteVideoURLText,
                                onRemove: onRemoveRemoteVideoURL
                            )
                        }

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
            ExpandedComposerHeader(
                onCollapse: {
                    isPresented = false
                    onCollapse()
                },
                onHide: {
                    isPresented = false
                    onHide()
                }
            )
            panelSlashCommandPopover
            inlineAccessoryRows
            editorSection
            ExpandedComposerControlsSection(controlsRow: controlsRow)
            ChatComposerCanSendHost(
                textStore: composerTextStore,
                draftAttachments: draftAttachments,
                draftQuotes: draftQuotes,
                isImportingDropAttachments: isImportingDropAttachments
            ) { canSendDraft in
                ExpandedComposerFooter(
                    textStore: composerTextStore,
                    contextUsageEstimate: contextUsageEstimate,
                    currentModelName: currentModelName,
                    sendWithCommandEnter: sendWithCommandEnter,
                    isBusy: isBusy,
                    isPreparingToSend: isPreparingToSend,
                    prepareToSendStatus: prepareToSendStatus,
                    isRecording: isRecording,
                    isTranscribing: isTranscribing,
                    recordingDurationText: recordingDurationText,
                    transcribingStatusText: transcribingStatusText,
                    sendButtonPresentation: sendButtonPresentation(canSendDraft: canSendDraft),
                    onSend: onSend
                )
            }
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
        .jinBorderBeam(
            isActive: isBusy || isRecording || isPreparingToSend,
            style: isRecording ? .pulseInner : .line,
            cornerRadius: panelCornerRadius
        )
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

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            ComposerEditorSurface(
                isFocused: isEditorFocused,
                isDropTargeted: isComposerDropTargeted
            ) {
                ChatComposerEditorTextHost(textStore: composerTextStore) { textBinding in
                    DroppableTextEditor(
                        text: textBinding,
                        isDropTargeted: $isComposerDropTargeted,
                        isFocused: $isEditorFocused,
                        placeholder: "Write a message",
                        font: NSFont.preferredFont(forTextStyle: .body),
                        useCommandEnterToSubmit: sendWithCommandEnter,
                        onDropFileURLs: onDropFileURLs,
                        onDropImages: onDropImages,
                        onSubmit: {
                            guard !sendButtonPresentation(canSendDraft: currentCanSendDraft).isDisabled else { return }
                            onSend()
                        },
                        onCancel: {
                            isPresented = false
                            onCollapse()
                            return true
                        },
                        onInterceptKeyDown: onInterceptKeyDown
                    )
                }
                .frame(minHeight: 320, maxHeight: .infinity, alignment: .topLeading)
                .shortcutHint(.focusComposer, placement: .trailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
