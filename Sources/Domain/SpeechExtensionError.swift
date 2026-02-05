import Foundation

enum SpeechExtensionError: Error, LocalizedError {
    case textToSpeechNotConfigured
    case speechToTextNotConfigured
    case missingElevenLabsVoice
    case invalidBaseURL(String)
    case microphonePermissionDenied
    case speechRecordingFailed

    var errorDescription: String? {
        switch self {
        case .textToSpeechNotConfigured:
            return "Text to Speech is not configured. Set an API key in Settings → Plugins → Text to Speech."
        case .speechToTextNotConfigured:
            return "Speech to Text is not configured. Set an API key in Settings → Plugins → Speech to Text."
        case .missingElevenLabsVoice:
            return "ElevenLabs voice is not selected. Choose a voice in Settings → Plugins → Text to Speech."
        case .invalidBaseURL(let raw):
            return "Invalid API Base URL: “\(raw)”."
        case .microphonePermissionDenied:
            return "Microphone access is denied. Enable it in System Settings → Privacy & Security → Microphone for Jin."
        case .speechRecordingFailed:
            return "Failed to record audio."
        }
    }
}
