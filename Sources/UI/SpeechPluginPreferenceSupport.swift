import Foundation

enum SpeechPluginPreferenceSupport {
    static func trimmed(_ value: String?) -> String {
        (value ?? "").trimmed
    }

    static func normalized(_ raw: String?) -> String? {
        raw?.trimmedNonEmpty
    }

    static func resolvedBaseURL(_ stored: String?, fallback: String) throws -> URL {
        let urlString = normalized(stored) ?? fallback
        guard let url = URL(string: urlString) else {
            throw SpeechExtensionError.invalidBaseURL(urlString)
        }
        return url
    }

    static func resolvedTimestampGranularities(_ json: String?) -> [String]? {
        let timestamps = AppPreferences.decodeStringArrayJSON(json ?? "[]")
        return timestamps.isEmpty ? nil : timestamps
    }

    static func resolvedSpeechToTextProvider(defaults: UserDefaults) throws -> SpeechToTextProvider {
        try resolvedProvider(
            defaults: defaults,
            preferenceKey: AppPreferenceKeys.sttProvider,
            missingError: .speechToTextProviderNotConfigured,
            invalidError: SpeechExtensionError.invalidSpeechToTextProvider
        )
    }

    static func resolvedTextToSpeechProvider(defaults: UserDefaults) throws -> TextToSpeechProvider {
        try resolvedProvider(
            defaults: defaults,
            preferenceKey: AppPreferenceKeys.ttsProvider,
            missingError: .textToSpeechProviderNotConfigured,
            invalidError: SpeechExtensionError.invalidTextToSpeechProvider
        )
    }

    static func speechToTextAPIKeyPreferenceKey(for provider: SpeechToTextProvider) -> String {
        switch provider {
        case .openai: return AppPreferenceKeys.sttOpenAIAPIKey
        case .openRouter: return AppPreferenceKeys.sttOpenRouterAPIKey
        case .groq: return AppPreferenceKeys.sttGroqAPIKey
        case .mistral: return AppPreferenceKeys.sttMistralAPIKey
        case .elevenlabs: return AppPreferenceKeys.sttElevenLabsAPIKey
        }
    }

    static func textToSpeechAPIKeyPreferenceKey(for provider: TextToSpeechProvider) -> String {
        switch provider {
        case .elevenlabs: return AppPreferenceKeys.ttsElevenLabsAPIKey
        case .openai: return AppPreferenceKeys.ttsOpenAIAPIKey
        case .openRouter: return AppPreferenceKeys.ttsOpenRouterAPIKey
        case .groq: return AppPreferenceKeys.ttsGroqAPIKey
        case .xiaomiMiMo: return AppPreferenceKeys.ttsMiMoAPIKey
        }
    }

    /// Rewrites legacy on-device provider raws so users upgrading from a build that still had
    /// WhisperKit / TTSKit don't land on an "unknown provider" state. Defaults match the
    /// `@AppStorage` fallbacks in the settings views (Groq for STT, OpenAI for TTS).
    static func migrateLegacyOnDeviceProviderSelections(defaults: UserDefaults = .standard) {
        let legacyRaw = "whisperKit"
        if defaults.string(forKey: AppPreferenceKeys.sttProvider) == legacyRaw {
            defaults.set(SpeechToTextProvider.groq.rawValue, forKey: AppPreferenceKeys.sttProvider)
        }
        if defaults.string(forKey: AppPreferenceKeys.ttsProvider) == legacyRaw {
            defaults.set(TextToSpeechProvider.openai.rawValue, forKey: AppPreferenceKeys.ttsProvider)
        }
    }

    private static func resolvedProvider<Provider: RawRepresentable>(
        defaults: UserDefaults,
        preferenceKey: String,
        missingError: SpeechExtensionError,
        invalidError: (String) -> SpeechExtensionError
    ) throws -> Provider where Provider.RawValue == String {
        let raw = trimmed(defaults.string(forKey: preferenceKey))
        guard !raw.isEmpty else {
            throw missingError
        }
        guard let provider = Provider(rawValue: raw) else {
            throw invalidError(raw)
        }
        return provider
    }
}
