import SwiftUI
import AppKit
import Foundation

// MARK: - Message Row

struct MessageRow: View, Equatable {
    let item: MessageRenderItem
    let maxBubbleWidth: CGFloat
    let assistantDisplayName: String
    let providerType: ProviderType?
    let providerIconID: String?
    let deferCodeHighlightUpgrade: Bool
    let payloadResolver: RenderedMessagePayloadResolver
    let toolResultsByCallID: [String: ToolResult]
    let textToSpeechEnabled: Bool
    let textToSpeechConfigured: Bool
    let textToSpeechIsGenerating: Bool
    let textToSpeechIsPlaying: Bool
    let textToSpeechIsPaused: Bool
    let onToggleSpeakAssistantMessage: (UUID, String) -> Void
    let onStopSpeakAssistantMessage: (UUID) -> Void
    let onRegenerate: (UUID) -> Void
    let onEditUserMessage: (UUID) -> Void
    let onDeleteMessage: (UUID) -> Void
    let onDeleteResponse: (UUID) -> Void
    let onQuoteSelection: (MessageSelectionSnapshot, String?, String?) -> Void
    let onCreateHighlight: (MessageSelectionSnapshot) -> Void
    let onRemoveHighlights: ([UUID]) -> Void
    let editingUserMessageID: UUID?
    let editingUserMessageText: Binding<String>
    let editingUserMessageFocused: Binding<Bool>
    let onSubmitUserEdit: (UUID) -> Void
    let onCancelUserEdit: () -> Void
    let editSlashCommand: EditSlashCommandContext
    let onOpenArtifact: (RenderedArtifactVersion) -> Void
    let renderMode: MessageRenderMode
    let onExpandCollapsedContent: (UUID) -> Void

    /// Bumped when row-internal disclosures (MCP / thinking / code exec /
    /// search) change height without the parent message data changing.
    /// Folded into `ConstrainedWidth` so the bubble remeasures instead of
    /// leaving residual empty gray after collapse.
    @State private var layoutEpoch = 0

    var body: some View {
        let presentation = MessageRowPresentationSupport.Presentation(
            item: item,
            maxBubbleWidth: maxBubbleWidth,
            providerType: providerType,
            renderMode: renderMode,
            editingUserMessageID: editingUserMessageID
        )
        Group {
            if !presentation.rendersRow {
                EmptyView()
            } else {
                HStack(alignment: .top, spacing: 0) {
                    if presentation.isUser {
                        Spacer(minLength: 0)
                    }

                    ConstrainedWidth(presentation.effectiveMaxBubbleWidth) {
                        // User rows must expand to the full proposed max width and
                        // trail-align children. Hugging alone + ConstrainedWidth's
                        // leading frame parks a short bubble mid-column (macOS 27
                        // frame+fixedSize path). Footer actions hug; this frame
                        // is what pins them under the bubble's right edge.
                        VStack(alignment: presentation.isUser ? .trailing : .leading, spacing: 6) {
                            VStack(alignment: .leading, spacing: JinSpacing.small) {
                                MessageRowHeaderView(
                                    isUser: presentation.isUser,
                                    isTool: presentation.isTool,
                                    assistantDisplayName: assistantDisplayName,
                                    assistantModelLabel: presentation.assistantModelLabel,
                                    providerIconID: item.assistantProviderIconID ?? providerIconID
                                )

                                if presentation.isEditingUserMessage {
                                    if editSlashCommand.isActive {
                                        SlashCommandMCPPopover(
                                            servers: editSlashCommand.servers,
                                            filterText: editSlashCommand.filterText,
                                            highlightedIndex: editSlashCommand.highlightedIndex,
                                            onSelectServer: editSlashCommand.onSelectServer,
                                            onDismiss: editSlashCommand.onDismiss
                                        )
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                        .animation(.easeOut(duration: 0.12), value: editSlashCommand.isActive)
                                    }

                                    if !editSlashCommand.perMessageChips.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: JinSpacing.xSmall) {
                                                ForEach(editSlashCommand.perMessageChips) { chip in
                                                    PerMessageMCPChip(
                                                        name: chip.name,
                                                        onRemove: { editSlashCommand.onRemovePerMessageServer(chip.id) }
                                                    )
                                                }
                                            }
                                        }
                                    }

                                    DroppableTextEditor(
                                        text: editingUserMessageText,
                                        isDropTargeted: .constant(false),
                                        isFocused: editingUserMessageFocused,
                                        font: NSFont.preferredFont(forTextStyle: .body),
                                        onDropFileURLs: { _ in false },
                                        onDropImages: { _ in false },
                                        onSubmit: { onSubmitUserEdit(item.id) },
                                        onCancel: {
                                            onCancelUserEdit()
                                            return true
                                        },
                                        onInterceptKeyDown: editSlashCommand.onInterceptKeyDown
                                    )
                                    .frame(minHeight: 36, maxHeight: 400)
                                } else {
                                    if presentation.isUser,
                                       !presentation.hidesManagedAgentInternalUI,
                                       !item.perMessageMCPServerNames.isEmpty {
                                        UserMessageMCPBadgeRow(serverNames: item.perMessageMCPServerNames)
                                    }

                                    if !item.searchActivities.isEmpty {
                                        SearchActivityTimelineView(
                                            activities: item.searchActivities,
                                            isStreaming: false,
                                            providerLabel: ChatConversationMinimapGeometry.customAssistantDisplayName(assistantDisplayName),
                                            modelLabel: presentation.assistantModelLabel,
                                            onExpansionChanged: { layoutEpoch &+= 1 }
                                        )
                                    }

                                    if !presentation.visibleCodeExecutionActivities.isEmpty {
                                        CodeExecutionTimelineView(
                                            activities: presentation.visibleCodeExecutionActivities,
                                            isStreaming: false,
                                            onExpansionChanged: { layoutEpoch &+= 1 }
                                        )
                                    }

                                    if let collapsedPreview = presentation.collapsedPreview {
                                        CollapsedAssistantPreviewView(preview: collapsedPreview) {
                                            onExpandCollapsedContent(item.id)
                                        }
                                    } else if presentation.isUser {
                                        userBlocksView(blocks: item.renderedBlocks)
                                    } else {
                                        ForEach(Array(presentation.visibleRenderedBlocks.enumerated()), id: \.offset) { _, block in
                                            switch block {
                                            case .content(let anchorID, let part):
                                                ContentPartView(
                                                    part: part,
                                                    isUser: false,
                                                    deferCodeHighlightUpgrade: deferCodeHighlightUpgrade,
                                                    forceNativeText: renderMode == .nativeText,
                                                    payloadResolver: payloadResolver,
                                                    selectionMessageID: item.id,
                                                    selectionAnchorID: anchorID,
                                                    persistedHighlights: highlights(for: anchorID),
                                                    selectionActions: selectionActions
                                                )

                                            case .artifact(let artifact):
                                                MessageArtifactCardView(artifact: artifact) {
                                                    onOpenArtifact(artifact)
                                                }
                                            }
                                        }
                                    }

                                    if !presentation.visibleToolCalls.isEmpty {
                                        MCPToolTimelineView(
                                            toolCalls: presentation.visibleToolCalls,
                                            toolResultsByCallID: toolResultsByCallID,
                                            isStreaming: false,
                                            onExpansionChanged: { layoutEpoch &+= 1 }
                                        )
                                    }
                                }
                            }
                            .padding(JinSpacing.medium)
                            .jinSurface(
                                bubbleBackground(
                                    isUser: presentation.isUser,
                                    isTool: presentation.isTool
                                ),
                                cornerRadius: JinRadius.large
                            )

                            if presentation.isUser || presentation.isAssistant {
                                MessageRowFooterView(
                                    itemID: item.id,
                                    timestamp: item.timestamp,
                                    isUser: presentation.isUser,
                                    isAssistant: presentation.isAssistant,
                                    isEditingUserMessage: presentation.isEditingUserMessage,
                                    showsCopyButton: presentation.showsCopyButton,
                                    copyText: presentation.copyText,
                                    canEditUserMessage: presentation.canEditUserMessage,
                                    canDeleteResponse: presentation.canDeleteResponse,
                                    responseMetrics: item.responseMetrics,
                                    textToSpeechEnabled: textToSpeechEnabled,
                                    textToSpeechConfigured: textToSpeechConfigured,
                                    textToSpeechIsGenerating: textToSpeechIsGenerating,
                                    textToSpeechIsPlaying: textToSpeechIsPlaying,
                                    textToSpeechIsPaused: textToSpeechIsPaused,
                                    onToggleSpeakAssistantMessage: onToggleSpeakAssistantMessage,
                                    onStopSpeakAssistantMessage: onStopSpeakAssistantMessage,
                                    onRegenerate: onRegenerate,
                                    onEditUserMessage: onEditUserMessage,
                                    onDeleteMessage: onDeleteMessage,
                                    onDeleteResponse: onDeleteResponse,
                                    onSubmitUserEdit: onSubmitUserEdit,
                                    onCancelUserEdit: onCancelUserEdit
                                )
                                .padding(.top, 2)
                            }
                        }
                        .frame(
                            maxWidth: .infinity,
                            alignment: presentation.isUser ? .trailing : .leading
                        )
                        // Disclosure expand/collapse bumps `layoutEpoch` without
                        // changing the render item; fold it into ConstrainedWidth
                        // so the row remeasures instead of leaving residual empty
                        // gray under a stale height (especially on macOS 27's
                        // frame+fixedSize path).
                        .layoutValue(
                            key: ConstrainedWidthContentVersionKey.self,
                            value: .version(layoutEpoch)
                        )
                    }
                    .padding(.horizontal, presentation.isUser ? 0 : JinSpacing.small)

                    if !presentation.isUser {
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: presentation.isUser ? .trailing : .leading)
                .padding(.vertical, JinSpacing.small)
                .contentShape(Rectangle())
            }
        }
    }

    private func highlights(for anchorID: String) -> [MessageHighlightSnapshot] {
        return item.highlights.filter { $0.anchorID == anchorID }
    }

    private var selectionActions: MessageTextSelectionActions {
        guard item.isAssistant else { return .none }
        let resolvedProviderIconID = item.assistantProviderIconID ?? providerIconID
        return MessageTextSelectionActions(
            onQuote: { snapshot in
                onQuoteSelection(snapshot, item.assistantModelLabel, resolvedProviderIconID)
            },
            onHighlight: onCreateHighlight,
            onRemoveHighlights: onRemoveHighlights
        )
    }

    @ViewBuilder
    private func userBlocksView(blocks: [RenderedMessageBlock]) -> some View {
        let partition = MessageRowPresentationSupport.UserBlockPartition(blocks: blocks)

        if !partition.imageParts.isEmpty {
            HStack(spacing: JinSpacing.small) {
                ForEach(Array(partition.imageParts.enumerated()), id: \.offset) { _, part in
                    ContentPartView(
                        part: part,
                        isUser: true,
                        deferCodeHighlightUpgrade: deferCodeHighlightUpgrade,
                        payloadResolver: payloadResolver
                    )
                }
            }
        }

        ForEach(Array(partition.remainingBlocks.enumerated()), id: \.offset) { _, block in
            switch block {
            case .content(_, let part):
                ContentPartView(
                    part: part,
                    isUser: true,
                    deferCodeHighlightUpgrade: deferCodeHighlightUpgrade,
                    payloadResolver: payloadResolver
                )
            case .artifact(let artifact):
                MessageArtifactCardView(artifact: artifact) {
                    onOpenArtifact(artifact)
                }
            }
        }
    }

    private func bubbleBackground(isUser: Bool, isTool: Bool) -> JinSurfaceVariant {
        if isTool { return .tool }
        // User bubbles keep a soft accent tint so they still read as "mine".
        // Assistant bubbles use the inline island (subtle + hairline) so long
        // replies don't melt into the canvas without competing with the
        // composer's reserved raised surface.
        if isUser { return .accent }
        return .subtle
    }

    // MARK: - Equatable

    /// SwiftUI's default `View` diff reflects over every stored property,
    /// which for `MessageRow` includes the entire `MessageRenderItem` (with
    /// all rendered blocks). For long conversations that diff runs on every
    /// timeline re-eval and dominates CPU. A targeted `==` lets the parent
    /// `LazyVStack` skip identical rows. Closures and bindings are
    /// intentionally excluded — they're behaviorally equivalent across
    /// re-evaluations as long as the data identity is unchanged. Whenever
    /// the message is in edit mode we bail out (`return false`) so typing
    /// always re-renders.
    static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
        let lhsEditing = lhs.editingUserMessageID == lhs.item.id
        let rhsEditing = rhs.editingUserMessageID == rhs.item.id
        if lhsEditing || rhsEditing { return false }

        guard lhs.item.id == rhs.item.id,
              lhs.item.timestamp == rhs.item.timestamp,
              lhs.item.copyText == rhs.item.copyText,
              lhs.item.highlights == rhs.item.highlights,
              lhs.item.renderedBlocks.count == rhs.item.renderedBlocks.count,
              lhs.item.toolCalls.count == rhs.item.toolCalls.count,
              lhs.item.searchActivities.count == rhs.item.searchActivities.count,
              lhs.item.codeExecutionActivities.count == rhs.item.codeExecutionActivities.count,
              lhs.item.preferredRenderMode == rhs.item.preferredRenderMode,
              lhs.item.collapsedPreview == rhs.item.collapsedPreview,
              // Footer/action state. `canDeleteResponse` is derived from the
              // messages AFTER this row, so it can flip (e.g. when the
              // assistant reply lands) while everything above stays equal.
              lhs.item.canEditUserMessage == rhs.item.canEditUserMessage,
              lhs.item.canDeleteResponse == rhs.item.canDeleteResponse,
              lhs.item.responseMetrics == rhs.item.responseMetrics,
              lhs.renderMode == rhs.renderMode,
              lhs.maxBubbleWidth == rhs.maxBubbleWidth,
              lhs.assistantDisplayName == rhs.assistantDisplayName,
              lhs.providerType == rhs.providerType,
              lhs.providerIconID == rhs.providerIconID,
              lhs.deferCodeHighlightUpgrade == rhs.deferCodeHighlightUpgrade,
              lhs.textToSpeechEnabled == rhs.textToSpeechEnabled,
              lhs.textToSpeechConfigured == rhs.textToSpeechConfigured,
              lhs.textToSpeechIsGenerating == rhs.textToSpeechIsGenerating,
              lhs.textToSpeechIsPlaying == rhs.textToSpeechIsPlaying,
              lhs.textToSpeechIsPaused == rhs.textToSpeechIsPaused,
              lhs.toolResultsByCallID == rhs.toolResultsByCallID
        else { return false }
        return true
    }
}
