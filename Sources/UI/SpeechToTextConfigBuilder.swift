import Foundation

struct SpeechToTextConfigBuilder {
    private typealias Preferences = SpeechPluginPreferenceSupport

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func build() throws -> SpeechToTextManager.TranscriptionConfig {
        let provider = try Preferences.resolvedSpeechToTextProvider(defaults: defaults)
        let apiKey = try configuredAPIKey(for: provider)

        switch provider {
        case .openai:
            return try openAIConfig(apiKey: apiKey)
        case .openRouter:
            return try openRouterConfig(apiKey: apiKey)
        case .groq:
            return try groqConfig(apiKey: apiKey)
        case .mistral:
            return try mistralConfig(apiKey: apiKey)
        case .elevenlabs:
            return try elevenLabsConfig(apiKey: apiKey)
        }
    }

    private func configuredAPIKey(for provider: SpeechToTextProvider) throws -> String {
        let apiKeyPreferenceKey = Preferences.speechToTextAPIKeyPreferenceKey(for: provider)
        let apiKey = Preferences.trimmed(defaults.string(forKey: apiKeyPreferenceKey))
        guard !apiKey.isEmpty else { throw SpeechExtensionError.speechToTextNotConfigured }
        return apiKey
    }

    private func normalizedModel(for provider: SpeechToTextProvider, key: String) -> String {
        SpeechProviderModelCatalog.normalizedSpeechToTextModelID(
            for: provider,
            defaults.string(forKey: key)
        )
    }

    /// Splits a comma-separated preference into the repeated list forms the API expects.
    private func commaSeparatedList(forKey key: String) -> [String]? {
        guard let raw = Preferences.normalized(defaults.string(forKey: key)) else { return nil }
        let values = raw.components(separatedBy: ",").compactMap { $0.trimmedNonEmpty }
        return values.isEmpty ? nil : values
    }

    private func openAIConfig(apiKey: String) throws -> SpeechToTextManager.TranscriptionConfig {
        let baseURL = try Preferences.resolvedBaseURL(
            defaults.string(forKey: AppPreferenceKeys.sttOpenAIBaseURL),
            fallback: OpenAIAudioClient.Constants.defaultBaseURL.absoluteString
        )
        let model = normalizedModel(for: .openai, key: AppPreferenceKeys.sttOpenAIModel)
        let capabilities = SpeechModelCapabilityRegistry.transcriptionCapabilities(
            provider: .openai,
            modelID: model
        )
        // Only whisper-1 still serves the translation endpoint.
        let translateToEnglish = capabilities.supportsTranslation
            && defaults.bool(forKey: AppPreferenceKeys.sttOpenAITranslateToEnglish)
        let language = Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.sttOpenAILanguage))
        let prompt = Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.sttOpenAIPrompt))
        let responseFormat = Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.sttOpenAIResponseFormat))
        let temperature = defaults.object(forKey: AppPreferenceKeys.sttOpenAITemperature) as? Double
        let timestampGranularities = Preferences.resolvedTimestampGranularities(
            defaults.string(forKey: AppPreferenceKeys.sttOpenAITimestampGranularitiesJSON)
        )

        return .openai(
            SpeechToTextManager.OpenAIConfig(
                apiKey: apiKey,
                baseURL: baseURL,
                model: model,
                capabilities: capabilities,
                translateToEnglish: translateToEnglish,
                language: language,
                keywords: commaSeparatedList(forKey: AppPreferenceKeys.sttOpenAIKeywords),
                prompt: prompt,
                responseFormat: responseFormat,
                temperature: temperature,
                timestampGranularities: timestampGranularities
            )
        )
    }

    private func openRouterConfig(apiKey: String) throws -> SpeechToTextManager.TranscriptionConfig {
        let baseURL = try Preferences.resolvedBaseURL(
            defaults.string(forKey: AppPreferenceKeys.sttOpenRouterBaseURL),
            fallback: OpenRouterAudioClient.Constants.defaultBaseURL.absoluteString
        )
        let model = normalizedModel(for: .openRouter, key: AppPreferenceKeys.sttOpenRouterModel)
        let capabilities = SpeechModelCapabilityRegistry.transcriptionCapabilities(
            provider: .openRouter,
            modelID: model
        )
        let language = Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.sttOpenRouterLanguage))
        let temperature = defaults.object(forKey: AppPreferenceKeys.sttOpenRouterTemperature) as? Double

        return .openRouter(
            SpeechToTextManager.OpenRouterConfig(
                apiKey: apiKey,
                baseURL: baseURL,
                model: model,
                language: language,
                temperature: temperature,
                // OpenRouter rejects text/srt/vtt on this endpoint.
                responseFormat: SpeechModelCapabilityRegistry.resolvedResponseFormat(
                    Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.sttOpenRouterResponseFormat)),
                    supported: capabilities.responseFormats,
                    fallback: "json"
                ),
                timestampGranularities: Preferences.resolvedTimestampGranularities(
                    defaults.string(forKey: AppPreferenceKeys.sttOpenRouterTimestampGranularitiesJSON)
                )
            )
        )
    }

    private func groqConfig(apiKey: String) throws -> SpeechToTextManager.TranscriptionConfig {
        let baseURL = try Preferences.resolvedBaseURL(
            defaults.string(forKey: AppPreferenceKeys.sttGroqBaseURL),
            fallback: GroqAudioClient.Constants.defaultBaseURL.absoluteString
        )
        let model = normalizedModel(for: .groq, key: AppPreferenceKeys.sttGroqModel)
        let capabilities = SpeechModelCapabilityRegistry.transcriptionCapabilities(
            provider: .groq,
            modelID: model
        )
        let translateToEnglish = capabilities.supportsTranslation
            && defaults.bool(forKey: AppPreferenceKeys.sttGroqTranslateToEnglish)
        let language = Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.sttGroqLanguage))
        let prompt = Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.sttGroqPrompt))
        let responseFormat = Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.sttGroqResponseFormat))
        let temperature = defaults.object(forKey: AppPreferenceKeys.sttGroqTemperature) as? Double
        let timestampGranularities = Preferences.resolvedTimestampGranularities(
            defaults.string(forKey: AppPreferenceKeys.sttGroqTimestampGranularitiesJSON)
        )

        return .groq(
            SpeechToTextManager.GroqConfig(
                apiKey: apiKey,
                baseURL: baseURL,
                model: model,
                capabilities: capabilities,
                translateToEnglish: translateToEnglish,
                language: language,
                prompt: prompt,
                responseFormat: responseFormat,
                temperature: temperature,
                timestampGranularities: timestampGranularities
            )
        )
    }

    private func mistralConfig(apiKey: String) throws -> SpeechToTextManager.TranscriptionConfig {
        let baseURL = try Preferences.resolvedBaseURL(
            defaults.string(forKey: AppPreferenceKeys.sttMistralBaseURL),
            fallback: ProviderType.mistral.defaultBaseURL ?? "https://api.mistral.ai/v1"
        )
        let model = normalizedModel(for: .mistral, key: AppPreferenceKeys.sttMistralModel)
        let capabilities = SpeechModelCapabilityRegistry.transcriptionCapabilities(
            provider: .mistral,
            modelID: model
        )
        let language = Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.sttMistralLanguage))
        let prompt = Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.sttMistralPrompt))
        let responseFormat = Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.sttMistralResponseFormat))
        let temperature = defaults.object(forKey: AppPreferenceKeys.sttMistralTemperature) as? Double
        let timestampGranularities = Preferences.resolvedTimestampGranularities(
            defaults.string(forKey: AppPreferenceKeys.sttMistralTimestampGranularitiesJSON)
        )

        return .mistral(
            SpeechToTextManager.MistralConfig(
                apiKey: apiKey,
                baseURL: baseURL,
                model: model,
                capabilities: capabilities,
                language: language,
                prompt: prompt,
                responseFormat: responseFormat,
                temperature: temperature,
                timestampGranularities: timestampGranularities,
                diarize: defaults.object(forKey: AppPreferenceKeys.sttMistralDiarize) as? Bool
            )
        )
    }

    private func elevenLabsConfig(apiKey: String) throws -> SpeechToTextManager.TranscriptionConfig {
        let baseURL = try Preferences.resolvedBaseURL(
            defaults.string(forKey: AppPreferenceKeys.sttElevenLabsBaseURL),
            fallback: ElevenLabsSTTClient.Constants.defaultBaseURL.absoluteString
        )
        let modelId = normalizedModel(for: .elevenlabs, key: AppPreferenceKeys.sttElevenLabsModel)
        let languageCode = Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.sttElevenLabsLanguageCode))
        let tagAudioEvents = defaults.object(forKey: AppPreferenceKeys.sttElevenLabsTagAudioEvents) as? Bool
        let numSpeakers = defaults.object(forKey: AppPreferenceKeys.sttElevenLabsNumSpeakers) as? Int
        let timestampsGranularity = Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.sttElevenLabsTimestampsGranularity))
        let diarize = defaults.object(forKey: AppPreferenceKeys.sttElevenLabsDiarize) as? Bool
        let fileFormat = Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.sttElevenLabsFileFormat))
        let temperature = defaults.object(forKey: AppPreferenceKeys.sttElevenLabsTemperature) as? Double
        let noVerbatim = defaults.object(forKey: AppPreferenceKeys.sttElevenLabsNoVerbatim) as? Bool
        let supportedNoVerbatim = modelId == "scribe_v2" ? noVerbatim : nil

        return .elevenlabs(
            SpeechToTextManager.ElevenLabsConfig(
                apiKey: apiKey,
                baseURL: baseURL,
                modelId: modelId,
                languageCode: languageCode,
                tagAudioEvents: tagAudioEvents,
                numSpeakers: numSpeakers,
                timestampsGranularity: timestampsGranularity,
                diarize: diarize,
                diarizationThreshold: (diarize ?? false)
                    ? defaults.object(forKey: AppPreferenceKeys.sttElevenLabsDiarizationThreshold) as? Double
                    : nil,
                fileFormat: fileFormat,
                temperature: temperature,
                noVerbatim: supportedNoVerbatim
            )
        )
    }
}
