import Foundation

enum SpeechExtensionError: Error, LocalizedError {
    case textToSpeechNotConfigured
    case speechToTextNotConfigured
    case textToSpeechProviderNotConfigured
    case speechToTextProviderNotConfigured
    case invalidTextToSpeechProvider(String)
    case invalidSpeechToTextProvider(String)
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
        case .textToSpeechProviderNotConfigured:
            return "Text to Speech provider is not configured. Select a provider in Settings → Plugins → Text to Speech."
        case .speechToTextProviderNotConfigured:
            return "Speech to Text provider is not configured. Select a provider in Settings → Plugins → Speech to Text."
        case .invalidTextToSpeechProvider(let raw):
            return "Invalid Text to Speech provider value: “\(raw)”. Re-select a provider in Settings → Plugins → Text to Speech."
        case .invalidSpeechToTextProvider(let raw):
            return "Invalid Speech to Text provider value: “\(raw)”. Re-select a provider in Settings → Plugins → Speech to Text."
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
