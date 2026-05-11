import SwiftUI

// MARK: - Composer Views & Controls Row

extension ChatView {

    var composerOverlay: some View {
        ChatComposerBindingHost(
            composerTextStore: composerTextStore,
            draftAttachments: $draftAttachments,
            draftQuotes: $draftQuotes,
            isImportingDropAttachments: isImportingDropAttachments
        ) { textBinding, canSendDraft in
            CompactComposerOverlayView(
                messageText: textBinding,
                remoteVideoURLText: $remoteVideoInputURLText,
                draftAttachments: $draftAttachments,
                draftQuotes: $draftQuotes,
                isComposerDropTargeted: $isComposerDropTargeted,
                isComposerFocused: $isComposerFocused,
                composerTextContentHeight: $composerTextContentHeight,
                contextUsageEstimate: currentContextUsageEstimate,
                currentModelName: currentModelName,
                sendWithCommandEnter: sendWithCommandEnter,
                isBusy: isBusy,
                canSendDraft: canSendDraft,
                showsRemoteVideoURLField: supportsExplicitRemoteVideoURLInput,
                isPreparingToSend: isPreparingToSend,
                prepareToSendStatus: prepareToSendStatus,
                isRecording: speechToTextManager.isRecording,
                isTranscribing: speechToTextManager.isTranscribing,
                recordingDurationText: formattedRecordingDuration,
                transcribingStatusText: ChatComposerSupport.transcribingStatusText(
                    usesAudioAttachment: speechToTextUsesAudioAttachment
                ),
                onDropFileURLs: handleDroppedFileURLs,
                onDropImages: handleDroppedImages,
                onSubmit: handleComposerSubmit,
                onCancel: handleComposerCancel,
                onRemoveAttachment: removeDraftAttachment,
                onRemoveQuote: removeDraftQuote,
                onExpand: {
                    isComposerFocused = false
                    isExpandedComposerPresented = true
                },
                onHide: toggleComposerVisibility,
                onSend: sendMessage,
                slashCommandServers: slashCommandMCPItems,
                isSlashCommandActive: isSlashMCPPopoverVisible,
                slashCommandFilterText: slashMCPFilterText,
                slashCommandHighlightedIndex: slashMCPHighlightedIndex,
                perMessageMCPChips: perMessageMCPChips,
                onSlashCommandSelectServer: handleSlashCommandSelectServer,
                onSlashCommandDismiss: dismissSlashCommandPopover,
                onRemovePerMessageMCPServer: removePerMessageMCPServer,
                onInterceptKeyDown: isSlashMCPPopoverVisible ? handleSlashCommandKeyDown : nil
            ) {
                composerControlsRow()
            }
        }
    }

    var composerTextChangeObserver: some View {
        ChatComposerTextChangeObserver(composerTextStore: composerTextStore) { newValue in
            updateSlashCommandState(for: newValue, target: .composer)
            scheduleDraftContextUsageRefresh()
        }
    }

    var expandedComposerSheet: some View {
        let isComposerTarget = slashCommandTarget == .composer

        return ChatComposerBindingHost(
            composerTextStore: composerTextStore,
            draftAttachments: $draftAttachments,
            draftQuotes: $draftQuotes,
            isImportingDropAttachments: isImportingDropAttachments
        ) { textBinding, canSendDraft in
            ExpandedComposerOverlay(
                messageText: textBinding,
                remoteVideoURLText: $remoteVideoInputURLText,
                draftAttachments: $draftAttachments,
                draftQuotes: $draftQuotes,
                isPresented: $isExpandedComposerPresented,
                isComposerDropTargeted: $isComposerDropTargeted,
                contextUsageEstimate: currentContextUsageEstimate,
                currentModelName: currentModelName,
                sendWithCommandEnter: sendWithCommandEnter,
                isBusy: isBusy,
                canSendDraft: canSendDraft,
                showsRemoteVideoURLField: supportsExplicitRemoteVideoURLInput,
                isPreparingToSend: isPreparingToSend,
                prepareToSendStatus: prepareToSendStatus,
                isRecording: speechToTextManager.isRecording,
                isTranscribing: speechToTextManager.isTranscribing,
                recordingDurationText: formattedRecordingDuration,
                transcribingStatusText: ChatComposerSupport.transcribingStatusText(
                    usesAudioAttachment: speechToTextUsesAudioAttachment
                ),
                onCollapse: { isExpandedComposerPresented = false },
                onHide: toggleComposerVisibility,
                onSend: {
                    if !isBusy {
                        isExpandedComposerPresented = false
                    }
                    sendMessage()
                },
                onDropFileURLs: handleDroppedFileURLs,
                onDropImages: handleDroppedImages,
                onRemoveAttachment: removeDraftAttachment,
                onRemoveQuote: removeDraftQuote,
                slashCommandServers: slashCommandMCPItems,
                isSlashCommandActive: isSlashMCPPopoverVisible && isComposerTarget,
                slashCommandFilterText: isComposerTarget ? slashMCPFilterText : "",
                slashCommandHighlightedIndex: isComposerTarget ? slashMCPHighlightedIndex : 0,
                perMessageMCPChips: perMessageMCPChips,
                onSlashCommandSelectServer: handleSlashCommandSelectServer,
                onSlashCommandDismiss: dismissSlashCommandPopover,
                onRemovePerMessageMCPServer: removePerMessageMCPServer,
                onInterceptKeyDown: (isSlashMCPPopoverVisible && isComposerTarget) ? handleSlashCommandKeyDown : nil
            ) {
                composerControlsRow(showsTrailingSpacer: false)
            }
        }
    }

}
