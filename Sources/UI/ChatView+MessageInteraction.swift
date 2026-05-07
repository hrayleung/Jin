import SwiftUI

extension ChatView {
    var messageInteractionContext: ChatMessageInteractionContext {
        ChatMessageInteractionContext(
            textToSpeechEnabled: textToSpeechPluginEnabled,
            textToSpeechConfigured: textToSpeechConfigured,
            editingUserMessageID: editingUserMessageID,
            editingUserMessageText: $editingUserMessageText,
            editingUserMessageFocused: $isEditingUserMessageFocused,
            textToSpeechIsGenerating: { messageID in
                ttsPlaybackManager.isGenerating(messageID: messageID)
            },
            textToSpeechIsPlaying: { messageID in
                ttsPlaybackManager.isPlaying(messageID: messageID)
            },
            textToSpeechIsPaused: { messageID in
                ttsPlaybackManager.isPaused(messageID: messageID)
            },
            onToggleSpeakAssistantMessage: { entity, text in
                toggleSpeakAssistantMessage(entity, text: text)
            },
            onStopSpeakAssistantMessage: { entity in
                stopSpeakAssistantMessage(entity)
            },
            onRegenerate: { entity in
                regenerateMessage(entity)
            },
            onEditUserMessage: { entity in
                beginEditingUserMessage(entity)
            },
            onSubmitUserEdit: { entity in
                submitEditingUserMessage(entity)
            },
            onCancelUserEdit: {
                cancelEditingUserMessage()
            },
            onDeleteMessage: { entity in
                deleteMessage(entity)
            },
            onDeleteResponse: { entity in
                deleteResponse(entity)
            },
            onQuoteSelection: { snapshot, modelName, providerIconID in
                addDraftQuote(
                    from: snapshot,
                    sourceModelName: modelName,
                    sourceProviderIconID: providerIconID
                )
            },
            onCreateHighlight: { snapshot in
                persistHighlight(from: snapshot)
            },
            onRemoveHighlights: { highlightIDs in
                removeHighlights(ids: highlightIDs)
            },
            editSlashCommand: editSlashCommandContext
        )
    }

    var editSlashCommandContext: EditSlashCommandContext {
        let isEditTarget = slashCommandTarget == .editMessage
        return EditSlashCommandContext(
            servers: slashCommandMCPItems,
            isActive: isSlashMCPPopoverVisible && isEditTarget,
            filterText: isEditTarget ? slashMCPFilterText : "",
            highlightedIndex: isEditTarget ? slashMCPHighlightedIndex : 0,
            perMessageChips: perMessageMCPChips,
            onSelectServer: handleSlashCommandSelectServer,
            onDismiss: dismissSlashCommandPopover,
            onRemovePerMessageServer: removePerMessageMCPServer,
            onInterceptKeyDown: (isSlashMCPPopoverVisible && isEditTarget) ? handleSlashCommandKeyDown : nil
        )
    }
}
