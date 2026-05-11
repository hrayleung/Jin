import SwiftUI
import AppKit

// MARK: - Expanded Composer Overlay

struct ExpandedComposerOverlay<ControlsRow: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var messageText: String
    @Binding var remoteVideoURLText: String
    @Binding var draftAttachments: [DraftAttachment]
    @Binding var draftQuotes: [DraftQuote]
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
    @State private var draftMetrics: ComposerDraftTextMetrics

    private let panelCornerRadius: CGFloat = 26

    // Custom init so `draftMetrics` reflects the existing draft on first render
    // instead of flashing "0 words · 0 characters" while expanding from compact.
    init(
        messageText: Binding<String>,
        remoteVideoURLText: Binding<String>,
        draftAttachments: Binding<[DraftAttachment]>,
        draftQuotes: Binding<[DraftQuote]>,
        isPresented: Binding<Bool>,
        isComposerDropTargeted: Binding<Bool>,
        contextUsageEstimate: ChatContextUsageEstimate?,
        currentModelName: String?,
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
        onCollapse: @escaping () -> Void,
        onHide: @escaping () -> Void,
        onSend: @escaping () -> Void,
        onDropFileURLs: @escaping ([URL]) -> Bool,
        onDropImages: @escaping ([NSImage]) -> Bool,
        onRemoveAttachment: @escaping (DraftAttachment) -> Void,
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
        _messageText = messageText
        _remoteVideoURLText = remoteVideoURLText
        _draftAttachments = draftAttachments
        _draftQuotes = draftQuotes
        _isPresented = isPresented
        _isComposerDropTargeted = isComposerDropTargeted
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
        self.onCollapse = onCollapse
        self.onHide = onHide
        self.onSend = onSend
        self.onDropFileURLs = onDropFileURLs
        self.onDropImages = onDropImages
        self.onRemoveAttachment = onRemoveAttachment
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
        _draftMetrics = State(initialValue: ComposerDraftTextMetrics(messageText: messageText.wrappedValue))
    }

    private var sendButtonPresentation: ComposerSendButtonPresentation {
        ComposerSendButtonPresentation(
            usesCommandReturn: sendWithCommandEnter,
            isBusy: isBusy,
            canSendDraft: canSendDraft,
            isRecording: isRecording,
            isTranscribing: isTranscribing
        )
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

        if !draftAttachments.isEmpty {
            ExpandedComposerAccessorySection(title: "Attachments", systemName: "paperclip") {
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
            ExpandedComposerAccessorySection(title: "Source Video URL", systemName: "link") {
                ExpandedComposerRemoteVideoURLField(
                    remoteVideoURLText: $remoteVideoURLText,
                    isBusy: isBusy
                )
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
            .onChange(of: messageText) { _, newValue in
                draftMetrics = ComposerDraftTextMetrics(messageText: newValue)
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
            ExpandedComposerFooter(
                draftMetrics: draftMetrics,
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
                sendButtonPresentation: sendButtonPresentation,
                onSend: onSend
            )
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

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
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
                        guard !sendButtonPresentation.isDisabled else { return }
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
}
