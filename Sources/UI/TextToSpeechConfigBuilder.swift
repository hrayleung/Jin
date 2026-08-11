import Foundation

struct TextToSpeechConfigBuilder {
    private typealias Preferences = SpeechPluginPreferenceSupport

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func build() throws -> TextToSpeechPlaybackManager.SynthesisConfig {
        let provider = try Preferences.resolvedTextToSpeechProvider(defaults: defaults)
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
        case .xiaomiMiMo:
            return try miMoConfig(apiKey: apiKey)
        case .elevenlabs:
            return try elevenLabsConfig(apiKey: apiKey)
        }
    }

    /// Defaults to on; the plan layer still falls back to a buffered request whenever the
    /// selected model cannot stream.
    private var streamingEnabled: Bool {
        defaults.object(forKey: AppPreferenceKeys.ttsLowLatencyStreaming) as? Bool ?? true
    }

    private func normalizedModel(
        for provider: TextToSpeechProvider,
        key: String
    ) -> String {
        SpeechProviderModelCatalog.normalizedTextToSpeechModelID(
            for: provider,
            defaults.string(forKey: key)
        )
    }

    private func configuredAPIKey(for provider: TextToSpeechProvider) throws -> String {
        let apiKeyPreferenceKey = Preferences.textToSpeechAPIKeyPreferenceKey(for: provider)
        let apiKey = Preferences.trimmed(defaults.string(forKey: apiKeyPreferenceKey))
        guard !apiKey.isEmpty else { throw SpeechExtensionError.textToSpeechNotConfigured }
        return apiKey
    }

    private func openAIConfig(apiKey: String) throws -> TextToSpeechPlaybackManager.SynthesisConfig {
        let baseURL = try Preferences.resolvedBaseURL(
            defaults.string(forKey: AppPreferenceKeys.ttsOpenAIBaseURL),
            fallback: OpenAIAudioClient.Constants.defaultBaseURL.absoluteString
        )

        let model = normalizedModel(for: .openai, key: AppPreferenceKeys.ttsOpenAIModel)
        let capabilities = SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: .openai,
            modelID: model
        )

        return .openai(
            TextToSpeechPlaybackManager.OpenAIConfig(
                apiKey: apiKey,
                baseURL: baseURL,
                model: model,
                voice: SpeechModelCapabilityRegistry.resolvedVoice(
                    defaults.string(forKey: AppPreferenceKeys.ttsOpenAIVoice),
                    capabilities: capabilities
                ) ?? "alloy",
                responseFormat: defaults.string(forKey: AppPreferenceKeys.ttsOpenAIResponseFormat) ?? "mp3",
                speed: capabilities.supportsSpeed
                    ? defaults.object(forKey: AppPreferenceKeys.ttsOpenAISpeed) as? Double
                    : nil,
                instructions: defaults.string(forKey: AppPreferenceKeys.ttsOpenAIInstructions),
                streamingEnabled: streamingEnabled
            )
        )
    }

    private func openRouterConfig(apiKey: String) throws -> TextToSpeechPlaybackManager.SynthesisConfig {
        let baseURL = try Preferences.resolvedBaseURL(
            defaults.string(forKey: AppPreferenceKeys.ttsOpenRouterBaseURL),
            fallback: OpenRouterAudioClient.Constants.defaultBaseURL.absoluteString
        )

        return .openRouter(
            TextToSpeechPlaybackManager.OpenRouterConfig(
                apiKey: apiKey,
                baseURL: baseURL,
                model: normalizedModel(for: .openRouter, key: AppPreferenceKeys.ttsOpenRouterModel),
                voice: defaults.string(forKey: AppPreferenceKeys.ttsOpenRouterVoice) ?? "",
                responseFormat: defaults.string(forKey: AppPreferenceKeys.ttsOpenRouterResponseFormat) ?? "mp3"
            )
        )
    }

    private func mistralConfig(apiKey: String) throws -> TextToSpeechPlaybackManager.SynthesisConfig {
        let baseURL = try Preferences.resolvedBaseURL(
            defaults.string(forKey: AppPreferenceKeys.ttsMistralBaseURL),
            fallback: MistralTTSClient.Constants.defaultBaseURL.absoluteString
        )
        let voiceId = defaults.string(forKey: AppPreferenceKeys.ttsMistralVoiceID) ?? ""
        guard voiceId.trimmedNonEmpty != nil else {
            throw SpeechExtensionError.missingMistralVoice
        }

        return .mistral(
            TextToSpeechPlaybackManager.MistralConfig(
                apiKey: apiKey,
                baseURL: baseURL,
                model: normalizedModel(for: .mistral, key: AppPreferenceKeys.ttsMistralModel),
                voiceId: voiceId,
                responseFormat: defaults.string(forKey: AppPreferenceKeys.ttsMistralResponseFormat)
                    ?? MistralTTSClient.Constants.defaultResponseFormat
            )
        )
    }

    private func groqConfig(apiKey: String) throws -> TextToSpeechPlaybackManager.SynthesisConfig {
        let baseURL = try Preferences.resolvedBaseURL(
            defaults.string(forKey: AppPreferenceKeys.ttsGroqBaseURL),
            fallback: GroqAudioClient.Constants.defaultBaseURL.absoluteString
        )

        let model = normalizedModel(for: .groq, key: AppPreferenceKeys.ttsGroqModel)
        let capabilities = SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: .groq,
            modelID: model
        )

        return .groq(
            TextToSpeechPlaybackManager.GroqConfig(
                apiKey: apiKey,
                baseURL: baseURL,
                model: model,
                // The English and Arabic models have disjoint voice catalogs.
                voice: SpeechModelCapabilityRegistry.resolvedVoice(
                    defaults.string(forKey: AppPreferenceKeys.ttsGroqVoice),
                    capabilities: capabilities
                ) ?? "troy",
                responseFormat: defaults.string(forKey: AppPreferenceKeys.ttsGroqResponseFormat) ?? "wav"
            )
        )
    }

    private func miMoConfig(apiKey: String) throws -> TextToSpeechPlaybackManager.SynthesisConfig {
        let baseURL = try Preferences.resolvedBaseURL(
            defaults.string(forKey: AppPreferenceKeys.ttsMiMoBaseURL),
            fallback: MiMoAudioClient.Constants.defaultBaseURL.absoluteString
        )
        let model = normalizedModel(for: .xiaomiMiMo, key: AppPreferenceKeys.ttsMiMoModel)
        let capabilities = SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: .xiaomiMiMo,
            modelID: model
        )
        let voiceCloneSamplePath = Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.ttsMiMoVoiceCloneSamplePath))
        let storedFormat = defaults.string(forKey: AppPreferenceKeys.ttsMiMoResponseFormat)

        return .mimo(
            TextToSpeechPlaybackManager.MiMoConfig(
                apiKey: apiKey,
                baseURL: baseURL,
                model: model,
                voice: SpeechModelCapabilityRegistry.resolvedVoice(
                    Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.ttsMiMoVoice)),
                    capabilities: capabilities
                ),
                // The V2.5 series dropped the mp3/pcm formats the V2 models accepted.
                responseFormat: SpeechModelCapabilityRegistry.resolvedResponseFormat(
                    storedFormat,
                    supported: capabilities.responseFormats,
                    fallback: MiMoAudioClient.Constants.defaultResponseFormat
                ) ?? MiMoAudioClient.Constants.defaultResponseFormat,
                styleInstruction: Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.ttsMiMoStyleInstruction)),
                voiceCloneSampleURL: voiceCloneSamplePath.map(URL.init(fileURLWithPath:)),
                streamingEnabled: streamingEnabled
            )
        )
    }

    private func elevenLabsConfig(apiKey: String) throws -> TextToSpeechPlaybackManager.SynthesisConfig {
        let baseURL = try Preferences.resolvedBaseURL(
            defaults.string(forKey: AppPreferenceKeys.ttsElevenLabsBaseURL),
            fallback: ElevenLabsTTSClient.Constants.defaultBaseURL.absoluteString
        )
        let voiceId = defaults.string(forKey: AppPreferenceKeys.ttsElevenLabsVoiceID) ?? ""
        guard voiceId.trimmedNonEmpty != nil else {
            throw SpeechExtensionError.missingElevenLabsVoice
        }

        let modelId = normalizedModel(for: .elevenlabs, key: AppPreferenceKeys.ttsElevenLabsModelID)
        let capabilities = SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: .elevenlabs,
            modelID: modelId
        )

        let voiceSettings = ElevenLabsTTSClient.VoiceSettings(
            stability: resolvedStability(capabilities: capabilities),
            similarityBoost: defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsSimilarityBoost) as? Double,
            style: defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsStyle) as? Double,
            useSpeakerBoost: defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsUseSpeakerBoost) as? Bool,
            // v3 rejects `speed`.
            speed: capabilities.supportsSpeed
                ? defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsSpeed) as? Double
                : nil
        )

        return .elevenlabs(
            TextToSpeechPlaybackManager.ElevenLabsConfig(
                apiKey: apiKey,
                baseURL: baseURL,
                voiceId: voiceId,
                modelId: modelId,
                outputFormat: defaults.string(forKey: AppPreferenceKeys.ttsElevenLabsOutputFormat),
                optimizeStreamingLatency: defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsOptimizeStreamingLatency) as? Int,
                enableLogging: defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsEnableLogging) as? Bool,
                voiceSettings: voiceSettings,
                streamingEnabled: streamingEnabled
            )
        )
    }

    /// v3 accepts only the three named stability modes, so snap a continuous preference to the
    /// nearest one rather than letting the request fail.
    private func resolvedStability(
        capabilities: SpeechSynthesisCapabilities
    ) -> Double? {
        guard let stored = defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsStability) as? Double else {
            return nil
        }
        guard let allowed = capabilities.stabilityValues, !allowed.isEmpty else { return stored }
        return allowed.min { abs($0 - stored) < abs($1 - stored) }
    }
}
