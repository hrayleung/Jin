import Foundation

extension ChatComposerSupport {
    static func speechToTextUsesAudioAttachment(addRecordingAsFile: Bool, supportsAudioInput: Bool) -> Bool {
        addRecordingAsFile && supportsAudioInput
    }

    static func speechToTextReadyForCurrentMode(usesAudioAttachment: Bool, isConfigured: Bool) -> Bool {
        usesAudioAttachment || isConfigured
    }

    static func speechToTextSystemImageName(isRecording: Bool, isTranscribing: Bool) -> String {
        if isTranscribing { return "waveform" }
        if isRecording { return "mic.fill" }
        return "mic"
    }

    static func speechToTextBadgeText(isTranscribing: Bool) -> String? {
        isTranscribing ? "\u{2026}" : nil
    }

    static func speechToTextHelpText(
        isRecording: Bool,
        isTranscribing: Bool,
        usesAudioAttachment: Bool,
        isPluginEnabled: Bool,
        addRecordingAsFile: Bool,
        supportsAudioInput: Bool,
        isConfigured: Bool
    ) -> String {
        if isTranscribing {
            return transcribingStatusText(usesAudioAttachment: usesAudioAttachment)
        }
        if isRecording {
            return usesAudioAttachment ? "Stop recording and attach audio" : "Stop recording"
        }
        if !isPluginEnabled { return "Speech to Text is turned off in Settings \u{2192} Plugins" }
        if usesAudioAttachment {
            return "Record audio and attach it to the draft message"
        }
        if addRecordingAsFile && !supportsAudioInput {
            if isConfigured {
                return "Current model doesn't support audio input; using transcription fallback."
            }
            return "Current model doesn't support audio input. Configure Speech to Text for transcription fallback."
        }
        if !isConfigured { return "Configure Speech to Text in Settings \u{2192} Plugins \u{2192} Speech to Text" }
        return "Start recording"
    }

    static func transcribingStatusText(usesAudioAttachment: Bool) -> String {
        usesAudioAttachment ? "Attaching audio\u{2026}" : "Transcribing\u{2026}"
    }

    static func artifactsHelpText(isEnabled: Bool) -> String {
        isEnabled ? "Artifacts enabled for new replies" : "Enable artifact generation for new replies"
    }

    static func formattedRecordingDuration(elapsedSeconds: TimeInterval) -> String {
        let total = max(0, Int(elapsedSeconds.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
