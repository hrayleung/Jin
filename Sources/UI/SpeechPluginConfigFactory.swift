import Foundation

/// Factory for building TTS/STT configuration objects from UserDefaults.
/// Decouples speech plugin configuration from ChatView.
enum SpeechPluginConfigFactory {

    // MARK: - Speech-to-Text

    static func speechToTextConfig(defaults: UserDefaults = .standard) throws -> SpeechToTextManager.TranscriptionConfig {
        let provider = SpeechToTextProvider(
            rawValue: defaults.string(forKey: AppPreferenceKeys.sttProvider) ?? SpeechToTextProvider.groq.rawValue
        ) ?? .groq

        let apiKeyPreferenceKey: String = {
            switch provider {
            case .openai: return AppPreferenceKeys.sttOpenAIAPIKey
            case .groq:   return AppPreferenceKeys.sttGroqAPIKey
            }
        }()

        let apiKey = trimmed(defaults.string(forKey: apiKeyPreferenceKey))
        guard !apiKey.isEmpty else { throw SpeechExtensionError.speechToTextNotConfigured }

        switch provider {
        case .openai:
            let baseURL = try resolvedBaseURL(
                defaults.string(forKey: AppPreferenceKeys.sttOpenAIBaseURL),
                fallback: OpenAIAudioClient.Constants.defaultBaseURL.absoluteString
            )
            let model = defaults.string(forKey: AppPreferenceKeys.sttOpenAIModel) ?? "gpt-4o-mini-transcribe"
            let translateToEnglish = defaults.bool(forKey: AppPreferenceKeys.sttOpenAITranslateToEnglish)
            let language = normalized(defaults.string(forKey: AppPreferenceKeys.sttOpenAILanguage))
            let prompt = normalized(defaults.string(forKey: AppPreferenceKeys.sttOpenAIPrompt))
            let responseFormat = normalized(defaults.string(forKey: AppPreferenceKeys.sttOpenAIResponseFormat))
            let temperature = defaults.object(forKey: AppPreferenceKeys.sttOpenAITemperature) as? Double
            let timestampGranularities = resolvedTimestampGranularities(
                defaults.string(forKey: AppPreferenceKeys.sttOpenAITimestampGranularitiesJSON)
            )

            return .openai(
                SpeechToTextManager.OpenAIConfig(
                    apiKey: apiKey,
                    baseURL: baseURL,
                    model: model,
                    translateToEnglish: translateToEnglish,
                    language: language,
                    prompt: prompt,
                    responseFormat: responseFormat,
                    temperature: temperature,
                    timestampGranularities: timestampGranularities
                )
            )

        case .groq:
            let baseURL = try resolvedBaseURL(
                defaults.string(forKey: AppPreferenceKeys.sttGroqBaseURL),
                fallback: GroqAudioClient.Constants.defaultBaseURL.absoluteString
            )
            let model = defaults.string(forKey: AppPreferenceKeys.sttGroqModel) ?? "whisper-large-v3-turbo"
            let translateToEnglish = defaults.bool(forKey: AppPreferenceKeys.sttGroqTranslateToEnglish)
            let language = normalized(defaults.string(forKey: AppPreferenceKeys.sttGroqLanguage))
            let prompt = normalized(defaults.string(forKey: AppPreferenceKeys.sttGroqPrompt))
            let responseFormat = normalized(defaults.string(forKey: AppPreferenceKeys.sttGroqResponseFormat))
            let temperature = defaults.object(forKey: AppPreferenceKeys.sttGroqTemperature) as? Double
            let timestampGranularities = resolvedTimestampGranularities(
                defaults.string(forKey: AppPreferenceKeys.sttGroqTimestampGranularitiesJSON)
            )

            return .groq(
                SpeechToTextManager.GroqConfig(
                    apiKey: apiKey,
                    baseURL: baseURL,
                    model: model,
                    translateToEnglish: translateToEnglish,
                    language: language,
                    prompt: prompt,
                    responseFormat: responseFormat,
                    temperature: temperature,
                    timestampGranularities: timestampGranularities
                )
            )
        }
    }

    // MARK: - Text-to-Speech

    static func textToSpeechConfig(defaults: UserDefaults = .standard) throws -> TextToSpeechPlaybackManager.SynthesisConfig {
        let provider = TextToSpeechProvider(
            rawValue: defaults.string(forKey: AppPreferenceKeys.ttsProvider) ?? TextToSpeechProvider.openai.rawValue
        ) ?? .openai

        let apiKeyPreferenceKey: String = {
            switch provider {
            case .elevenlabs: return AppPreferenceKeys.ttsElevenLabsAPIKey
            case .openai:     return AppPreferenceKeys.ttsOpenAIAPIKey
            case .groq:       return AppPreferenceKeys.ttsGroqAPIKey
            }
        }()

        let apiKey = trimmed(defaults.string(forKey: apiKeyPreferenceKey))
        guard !apiKey.isEmpty else { throw SpeechExtensionError.textToSpeechNotConfigured }

        switch provider {
        case .openai:
            let baseURL = try resolvedBaseURL(
                defaults.string(forKey: AppPreferenceKeys.ttsOpenAIBaseURL),
                fallback: OpenAIAudioClient.Constants.defaultBaseURL.absoluteString
            )
            return .openai(
                TextToSpeechPlaybackManager.OpenAIConfig(
                    apiKey: apiKey,
                    baseURL: baseURL,
                    model: defaults.string(forKey: AppPreferenceKeys.ttsOpenAIModel) ?? "gpt-4o-mini-tts",
                    voice: defaults.string(forKey: AppPreferenceKeys.ttsOpenAIVoice) ?? "alloy",
                    responseFormat: defaults.string(forKey: AppPreferenceKeys.ttsOpenAIResponseFormat) ?? "mp3",
                    speed: defaults.object(forKey: AppPreferenceKeys.ttsOpenAISpeed) as? Double,
                    instructions: defaults.string(forKey: AppPreferenceKeys.ttsOpenAIInstructions)
                )
            )

        case .groq:
            let baseURL = try resolvedBaseURL(
                defaults.string(forKey: AppPreferenceKeys.ttsGroqBaseURL),
                fallback: GroqAudioClient.Constants.defaultBaseURL.absoluteString
            )
            return .groq(
                TextToSpeechPlaybackManager.GroqConfig(
                    apiKey: apiKey,
                    baseURL: baseURL,
                    model: defaults.string(forKey: AppPreferenceKeys.ttsGroqModel) ?? "canopylabs/orpheus-v1-english",
                    voice: defaults.string(forKey: AppPreferenceKeys.ttsGroqVoice) ?? "troy",
                    responseFormat: defaults.string(forKey: AppPreferenceKeys.ttsGroqResponseFormat) ?? "wav"
                )
            )

        case .elevenlabs:
            let baseURL = try resolvedBaseURL(
                defaults.string(forKey: AppPreferenceKeys.ttsElevenLabsBaseURL),
                fallback: ElevenLabsTTSClient.Constants.defaultBaseURL.absoluteString
            )
            let voiceId = defaults.string(forKey: AppPreferenceKeys.ttsElevenLabsVoiceID) ?? ""
            guard !voiceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SpeechExtensionError.missingElevenLabsVoice
            }

            let voiceSettings = ElevenLabsTTSClient.VoiceSettings(
                stability: defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsStability) as? Double,
                similarityBoost: defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsSimilarityBoost) as? Double,
                style: defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsStyle) as? Double,
                useSpeakerBoost: defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsUseSpeakerBoost) as? Bool
            )

            return .elevenlabs(
                TextToSpeechPlaybackManager.ElevenLabsConfig(
                    apiKey: apiKey,
                    baseURL: baseURL,
                    voiceId: voiceId,
                    modelId: defaults.string(forKey: AppPreferenceKeys.ttsElevenLabsModelID),
                    outputFormat: defaults.string(forKey: AppPreferenceKeys.ttsElevenLabsOutputFormat),
                    optimizeStreamingLatency: defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsOptimizeStreamingLatency) as? Int,
                    enableLogging: defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsEnableLogging) as? Bool,
                    voiceSettings: voiceSettings
                )
            )
        }
    }

    // MARK: - Helpers

    static func currentTTSProvider(defaults: UserDefaults = .standard) -> TextToSpeechProvider {
        TextToSpeechProvider(
            rawValue: defaults.string(forKey: AppPreferenceKeys.ttsProvider) ?? TextToSpeechProvider.openai.rawValue
        ) ?? .openai
    }

    static func textToSpeechErrorMessage(_ error: Error, provider: TextToSpeechProvider) -> String {
        if let llmError = error as? LLMError, case .authenticationFailed = llmError {
            if provider == .elevenlabs {
                return "\(llmError.localizedDescription)\n\nIf your ElevenLabs key uses endpoint scopes, enable access to /v1/text-to-speech."
            }
            return llmError.localizedDescription
        }
        return error.localizedDescription
    }

    // MARK: - Private Helpers

    private static func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ raw: String?) -> String? {
        let value = trimmed(raw)
        return value.isEmpty ? nil : value
    }

    private static func resolvedBaseURL(_ stored: String?, fallback: String) throws -> URL {
        let urlString = trimmed(stored).isEmpty ? fallback : trimmed(stored)
        guard let url = URL(string: urlString) else {
            throw SpeechExtensionError.invalidBaseURL(urlString)
        }
        return url
    }

    private static func resolvedTimestampGranularities(_ json: String?) -> [String]? {
        let timestamps = AppPreferences.decodeStringArrayJSON(json ?? "[]")
        return timestamps.isEmpty ? nil : timestamps
    }
}
