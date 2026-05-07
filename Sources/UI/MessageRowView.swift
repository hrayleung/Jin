import SwiftUI
import AppKit
import Foundation

// MARK: - Message Row

struct MessageRow: View {
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
    let onOpenArtifact: (RenderedArtifactVersion, UUID?) -> Void
    let renderMode: MessageRenderMode
    let onExpandCollapsedContent: (UUID) -> Void
    let onActivate: (() -> Void)?

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
                        VStack(alignment: presentation.isUser ? .trailing : .leading, spacing: 6) {
                            MessageRowHeaderView(
                                isUser: presentation.isUser,
                                isTool: presentation.isTool,
                                assistantDisplayName: assistantDisplayName,
                                assistantModelLabel: presentation.assistantModelLabel,
                                providerIconID: item.assistantProviderIconID ?? providerIconID
                            )

                            VStack(alignment: .leading, spacing: 8) {
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
                                            providerLabel: assistantDisplayName == "Assistant" ? nil : assistantDisplayName,
                                            modelLabel: presentation.assistantModelLabel
                                        )
                                    }

                                    if !presentation.visibleCodexToolActivities.isEmpty {
                                        CodexToolTimelineView(
                                            activities: presentation.visibleCodexToolActivities,
                                            isStreaming: false
                                        )
                                    }

                                    if !presentation.visibleAgentToolActivities.isEmpty {
                                        AgentToolTimelineView(
                                            activities: presentation.visibleAgentToolActivities,
                                            isStreaming: false
                                        )
                                    }

                                    if !presentation.visibleCodeExecutionActivities.isEmpty {
                                        CodeExecutionTimelineView(
                                            activities: presentation.visibleCodeExecutionActivities,
                                            isStreaming: false
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
                                                    selectionContextThreadID: item.contextThreadID,
                                                    selectionAnchorID: anchorID,
                                                    persistedHighlights: highlights(for: anchorID),
                                                    selectionActions: selectionActions
                                                )

                                            case .artifact(let artifact):
                                                MessageArtifactCardView(artifact: artifact) {
                                                    onOpenArtifact(artifact, item.contextThreadID)
                                                }
                                            }
                                        }
                                    }

                                    if !presentation.visibleToolCalls.isEmpty {
                                        MCPToolTimelineView(
                                            toolCalls: presentation.visibleToolCalls,
                                            toolResultsByCallID: toolResultsByCallID,
                                            isStreaming: false
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
                                cornerRadius: JinRadius.medium
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
                    }
                    .padding(.horizontal, presentation.isUser ? 0 : JinSpacing.small)

                    if !presentation.isUser {
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: presentation.isUser ? .trailing : .leading)
                .padding(.vertical, JinSpacing.small)
                .onTapGesture {
                    onActivate?()
                }
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
                    onOpenArtifact(artifact, item.contextThreadID)
                }
            }
        }
    }

    private func bubbleBackground(isUser: Bool, isTool: Bool) -> JinSurfaceVariant {
        if isTool { return .tool }
        if isUser { return .accent }
        return .neutral
    }
}
