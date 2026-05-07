import SwiftUI
import UniformTypeIdentifiers

// MARK: - Composer Helpers

extension ChatView {

    var trimmedMessageText: String {
        messageText.trimmed
    }

    var trimmedRemoteVideoInputURLText: String {
        remoteVideoInputURLText.trimmed
    }

    var supportsExplicitRemoteVideoURLInput: Bool {
        (supportsVideoGenerationControl && providerType == .xai) || supportsVideoInput
    }

    var canSendDraft: Bool {
        (!trimmedMessageText.isEmpty || !draftAttachments.isEmpty || !draftQuotes.isEmpty) && !isImportingDropAttachments
    }

    var assistantDisplayName: String {
        conversationEntity.assistant?.displayName ?? "Assistant"
    }

    var speechToTextManagerActive: Bool {
        speechToTextManager.isRecording || speechToTextManager.isTranscribing
    }

    var speechToTextSystemImageName: String {
        ChatComposerSupport.speechToTextSystemImageName(
            isRecording: speechToTextManager.isRecording,
            isTranscribing: speechToTextManager.isTranscribing
        )
    }

    var speechToTextActiveColor: Color {
        speechToTextManager.isRecording ? .red : .accentColor
    }

    var speechToTextBadgeText: String? {
        ChatComposerSupport.speechToTextBadgeText(isTranscribing: speechToTextManager.isTranscribing)
    }

    var speechToTextUsesAudioAttachment: Bool {
        ChatComposerSupport.speechToTextUsesAudioAttachment(
            addRecordingAsFile: sttAddRecordingAsFile,
            supportsAudioInput: supportsAudioInput
        )
    }

    var speechToTextReadyForCurrentMode: Bool {
        ChatComposerSupport.speechToTextReadyForCurrentMode(
            usesAudioAttachment: speechToTextUsesAudioAttachment,
            isConfigured: speechToTextConfigured
        )
    }

    var speechToTextHelpText: String {
        ChatComposerSupport.speechToTextHelpText(
            isRecording: speechToTextManager.isRecording,
            isTranscribing: speechToTextManager.isTranscribing,
            usesAudioAttachment: speechToTextUsesAudioAttachment,
            isPluginEnabled: speechToTextPluginEnabled,
            addRecordingAsFile: sttAddRecordingAsFile,
            supportsAudioInput: supportsAudioInput,
            isConfigured: speechToTextConfigured
        )
    }

    var fileAttachmentHelpText: String {
        ChatComposerSupport.fileAttachmentHelpText(
            supportsAudioInput: supportsAudioInput,
            supportsNativePDF: supportsNativePDF
        )
    }

    var artifactsHelpText: String {
        ChatComposerSupport.artifactsHelpText(isEnabled: conversationEntity.artifactsEnabled == true)
    }

    var formattedRecordingDuration: String {
        ChatComposerSupport.formattedRecordingDuration(elapsedSeconds: speechToTextManager.elapsedSeconds)
    }

    var supportedAttachmentImportTypes: [UTType] {
        ChatComposerSupport.supportedAttachmentImportTypes
    }

    func toggleSpeechToText() {
        Task { @MainActor in
            do {
                if speechToTextManager.isRecording {
                    if speechToTextUsesAudioAttachment {
                        let clip = try await speechToTextManager.stopAndCollectRecording()
                        let attachment = try await AttachmentImportPipeline.importRecordedAudioClip(clip)
                        draftAttachments.append(attachment)
                        isComposerFocused = true
                        return
                    }

                    let config = try await currentSpeechToTextTranscriptionConfig()
                    let text = try await speechToTextManager.stopAndTranscribe(config: config)
                    if let trimmed = text.trimmedNonEmpty {
                        if messageText.isEmpty {
                            messageText = trimmed
                        } else {
                            let separator = messageText.hasSuffix("\n") ? "\n" : "\n\n"
                            messageText += separator + trimmed
                        }
                        isComposerFocused = true
                    }
                    return
                }

                guard speechToTextPluginEnabled else { return }
                if speechToTextUsesAudioAttachment {
                    try await speechToTextManager.startRecording()
                    return
                }

                _ = try await currentSpeechToTextTranscriptionConfig() // Validate configured
                try await speechToTextManager.startRecording()
            } catch {
                speechToTextManager.cancelAndCleanup()
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}
