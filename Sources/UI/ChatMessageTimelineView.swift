import SwiftUI

struct ChatMessageTimelineView: View {
    let visibleMessages: [MessageRenderItem]
    let hiddenCount: Int
    let messageRenderPageSize: Int?
    let onLoadEarlier: (() -> Void)?
    let bubbleMaxWidth: CGFloat
    let assistantDisplayName: String
    let providerType: ProviderType?
    let providerIconID: String?
    let eagerCodeHighlightStartIndex: Int
    let toolResultsByCallID: [String: ToolResult]
    let messageEntitiesByID: [UUID: MessageEntity]
    let interaction: ChatMessageInteractionContext
    let streamingMessage: StreamingMessageState?
    let streamingModelLabel: String?
    let streamingModelID: String?
    let bottomSpacerHeight: CGFloat
    let bottomID: String
    let onActivateThreadForMessage: (UUID?) -> Void
    let onActivateTimeline: () -> Void
    let onOpenArtifact: (RenderedArtifactVersion, UUID?) -> Void
    let effectiveRenderMode: (Int, MessageRenderItem) -> MessageRenderMode
    let onExpandCollapsedContent: (UUID) -> Void

    private var payloadResolver: RenderedMessagePayloadResolver {
        ChatTimelinePayloadResolverFactory.make(messageEntitiesByID: messageEntitiesByID)
    }

    @ViewBuilder
    var body: some View {
        if hiddenCount > 0,
           let messageRenderPageSize,
           let onLoadEarlier {
            LoadEarlierMessagesRow(
                hiddenCount: hiddenCount,
                pageSize: messageRenderPageSize,
                onLoad: onLoadEarlier
            )
            .id("loadEarlier")
        }

        ForEach(Array(visibleMessages.enumerated()), id: \.element.id) { index, message in
            MessageRow(
                item: message,
                maxBubbleWidth: bubbleMaxWidth,
                assistantDisplayName: assistantDisplayName,
                providerType: providerType,
                providerIconID: providerIconID,
                deferCodeHighlightUpgrade: index < eagerCodeHighlightStartIndex,
                payloadResolver: payloadResolver,
                toolResultsByCallID: toolResultsByCallID,
                textToSpeechEnabled: interaction.textToSpeechEnabled,
                textToSpeechConfigured: interaction.textToSpeechConfigured,
                textToSpeechIsGenerating: interaction.textToSpeechIsGenerating(message.id),
                textToSpeechIsPlaying: interaction.textToSpeechIsPlaying(message.id),
                textToSpeechIsPaused: interaction.textToSpeechIsPaused(message.id),
                onToggleSpeakAssistantMessage: { messageID, text in
                    guard let entity = messageEntitiesByID[messageID] else { return }
                    interaction.onToggleSpeakAssistantMessage(entity, text)
                },
                onStopSpeakAssistantMessage: { messageID in
                    guard let entity = messageEntitiesByID[messageID] else { return }
                    interaction.onStopSpeakAssistantMessage(entity)
                },
                onRegenerate: { messageID in
                    guard let entity = messageEntitiesByID[messageID] else { return }
                    interaction.onRegenerate(entity)
                },
                onEditUserMessage: { messageID in
                    guard let entity = messageEntitiesByID[messageID] else { return }
                    interaction.onEditUserMessage(entity)
                },
                onDeleteMessage: { messageID in
                    guard let entity = messageEntitiesByID[messageID] else { return }
                    interaction.onDeleteMessage(entity)
                },
                onDeleteResponse: { messageID in
                    guard let entity = messageEntitiesByID[messageID] else { return }
                    interaction.onDeleteResponse(entity)
                },
                onQuoteSelection: interaction.onQuoteSelection,
                onCreateHighlight: interaction.onCreateHighlight,
                onRemoveHighlights: interaction.onRemoveHighlights,
                editingUserMessageID: interaction.editingUserMessageID,
                editingUserMessageText: interaction.editingUserMessageText,
                editingUserMessageFocused: interaction.editingUserMessageFocused,
                onSubmitUserEdit: { messageID in
                    guard let entity = messageEntitiesByID[messageID] else { return }
                    interaction.onSubmitUserEdit(entity)
                },
                onCancelUserEdit: interaction.onCancelUserEdit,
                editSlashCommand: interaction.editSlashCommand,
                onOpenArtifact: onOpenArtifact,
                renderMode: effectiveRenderMode(index, message),
                onExpandCollapsedContent: onExpandCollapsedContent,
                onActivate: {
                    if let threadID = message.contextThreadID {
                        onActivateThreadForMessage(threadID)
                    } else {
                        onActivateTimeline()
                    }
                }
            )
            .id(message.id)
        }

        if let streamingMessage {
            StreamingMessageView(
                state: streamingMessage,
                maxBubbleWidth: bubbleMaxWidth,
                assistantDisplayName: assistantDisplayName,
                modelLabel: streamingModelLabel,
                modelID: streamingModelID,
                providerType: providerType,
                providerIconID: providerIconID,
                onContentUpdate: { }
            )
            .id(bottomID == "bottom" ? "streaming" : "streaming-\(bottomID)")
        }

        Color.clear
            .frame(height: bottomSpacerHeight)
            .id(bottomID)
    }
}
