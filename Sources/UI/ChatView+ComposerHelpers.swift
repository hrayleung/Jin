import SwiftUI
import UniformTypeIdentifiers

// MARK: - Composer Helpers

extension ChatView {

    var trimmedMessageText: String {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedRemoteVideoInputURLText: String {
        remoteVideoInputURLText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var supportsExplicitRemoteVideoURLInput: Bool {
        supportsVideoGenerationControl && providerType == .xai
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
        if speechToTextManager.isTranscribing { return "waveform" }
        if speechToTextManager.isRecording { return "mic.fill" }
        return "mic"
    }

    var speechToTextActiveColor: Color {
        speechToTextManager.isRecording ? .red : .accentColor
    }

    var speechToTextBadgeText: String? {
        speechToTextManager.isTranscribing ? "\u{2026}" : nil
    }

    var speechToTextUsesAudioAttachment: Bool {
        sttAddRecordingAsFile && supportsAudioInput
    }

    var speechToTextReadyForCurrentMode: Bool {
        speechToTextUsesAudioAttachment || speechToTextConfigured
    }

    var speechToTextHelpText: String {
        if speechToTextManager.isTranscribing {
            return speechToTextUsesAudioAttachment ? "Attaching audio\u{2026}" : "Transcribing\u{2026}"
        }
        if speechToTextManager.isRecording {
            return speechToTextUsesAudioAttachment ? "Stop recording and attach audio" : "Stop recording"
        }
        if !speechToTextPluginEnabled { return "Speech to Text is turned off in Settings \u{2192} Plugins" }
        if speechToTextUsesAudioAttachment {
            return "Record audio and attach it to the draft message"
        }
        if sttAddRecordingAsFile && !supportsAudioInput {
            if speechToTextConfigured {
                return "Current model doesn't support audio input; using transcription fallback."
            }
            return "Current model doesn't support audio input. Configure Speech to Text for transcription fallback."
        }
        if !speechToTextConfigured { return "Configure Speech to Text in Settings \u{2192} Plugins \u{2192} Speech to Text" }
        return "Start recording"
    }

    var fileAttachmentHelpText: String {
        let base = supportsAudioInput
            ? "Attach images / videos / audio / documents"
            : "Attach images / videos / documents"
        return supportsNativePDF ? "\(base) (native PDF available)" : "\(base) (PDFs may use extraction/OCR)"
    }

    var artifactsHelpText: String {
        if conversationEntity.artifactsEnabled == true {
            return "Artifacts enabled for new replies"
        }
        return "Enable artifact generation for new replies"
    }

    var formattedRecordingDuration: String {
        let total = max(0, Int(speechToTextManager.elapsedSeconds.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    static let supportedAttachmentDocumentExtensions = [
        "docx", "doc", "odt", "rtf",
        "xlsx", "xls", "csv", "tsv",
        "pptx", "ppt",
        "txt", "md", "markdown",
        "json", "html", "htm", "xml"
    ]

    var supportedAttachmentImportTypes: [UTType] {
        var types: [UTType] = []
        var seen: Set<String> = []

        func append(_ type: UTType?) {
            guard let type, seen.insert(type.identifier).inserted else { return }
            types.append(type)
        }

        append(.image)
        append(.movie)
        append(.audio)
        append(.pdf)

        for ext in Self.supportedAttachmentDocumentExtensions {
            append(UTType(filenameExtension: ext))
        }

        return types
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
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
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
