import SwiftUI

// MARK: - Composer Views & Controls Row

extension ChatView {

    var composerOverlay: some View {
        CompactComposerOverlayView(
            composerTextStore: composerTextStore,
            draftAttachments: $draftAttachments,
            draftQuotes: $draftQuotes,
            isComposerDropTargeted: $isComposerDropTargeted,
            isComposerFocused: $isComposerFocused,
            composerTextContentHeight: $composerTextContentHeight,
            contextUsageEstimate: currentContextUsageEstimate,
            currentModelName: currentModelName,
            sendWithCommandEnter: sendWithCommandEnter,
            isBusy: isBusy,
            isImportingDropAttachments: isImportingDropAttachments,
            remoteVideoURLText: remoteVideoInputURLText,
            supportsRemoteVideoURLInput: supportsExplicitRemoteVideoURLInput,
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
            onRemoveRemoteVideoURL: clearRemoteVideoInputURL,
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
            ChatComposerControlsAccess(store: composerControlsStore) {
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

        return ExpandedComposerOverlay(
            composerTextStore: composerTextStore,
            draftAttachments: $draftAttachments,
            draftQuotes: $draftQuotes,
            isPresented: $isExpandedComposerPresented,
            isComposerDropTargeted: $isComposerDropTargeted,
            contextUsageEstimate: currentContextUsageEstimate,
            currentModelName: currentModelName,
            sendWithCommandEnter: sendWithCommandEnter,
            isBusy: isBusy,
            isImportingDropAttachments: isImportingDropAttachments,
            remoteVideoURLText: remoteVideoInputURLText,
            supportsRemoteVideoURLInput: supportsExplicitRemoteVideoURLInput,
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
            onRemoveRemoteVideoURL: clearRemoteVideoInputURL,
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
            ChatComposerControlsAccess(store: composerControlsStore) {
                composerControlsRow(showsTrailingSpacer: false)
            }
        }
    }

}
