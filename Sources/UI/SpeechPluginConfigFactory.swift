import Foundation

/// Factory for building TTS/STT configuration objects from UserDefaults.
/// Decouples speech plugin configuration from ChatView.
enum SpeechPluginConfigFactory {
    private typealias Preferences = SpeechPluginPreferenceSupport

    static func speechToTextConfig(defaults: UserDefaults = .standard) throws -> SpeechToTextManager.TranscriptionConfig {
        try SpeechToTextConfigBuilder(defaults: defaults).build()
    }

    static func textToSpeechConfig(defaults: UserDefaults = .standard) throws -> TextToSpeechPlaybackManager.SynthesisConfig {
        try TextToSpeechConfigBuilder(defaults: defaults).build()
    }

    static func currentTTSProvider(defaults: UserDefaults = .standard) throws -> TextToSpeechProvider {
        try Preferences.resolvedTextToSpeechProvider(defaults: defaults)
    }

    static func currentSTTProvider(defaults: UserDefaults = .standard) throws -> SpeechToTextProvider {
        try Preferences.resolvedSpeechToTextProvider(defaults: defaults)
    }

    static func textToSpeechErrorMessage(_ error: Error, provider: TextToSpeechProvider?) -> String {
        if let llmError = error as? LLMError, case .authenticationFailed = llmError {
            if provider == .elevenlabs {
                return "\(llmError.localizedDescription)\n\nIf your ElevenLabs key uses endpoint scopes, enable access to /v1/text-to-speech."
            }
            return llmError.localizedDescription
        }
        return error.localizedDescription
    }
}
