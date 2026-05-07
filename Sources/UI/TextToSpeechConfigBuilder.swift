import Foundation

struct TextToSpeechConfigBuilder {
    private typealias Preferences = SpeechPluginPreferenceSupport

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func build() throws -> TextToSpeechPlaybackManager.SynthesisConfig {
        let provider = try Preferences.resolvedTextToSpeechProvider(defaults: defaults)

        if case .whisperKit = provider {
            return ttsKitConfig()
        }

        let apiKey = try configuredAPIKey(for: provider)

        switch provider {
        case .openai:
            return try openAIConfig(apiKey: apiKey)
        case .groq:
            return try groqConfig(apiKey: apiKey)
        case .xiaomiMiMo:
            return try miMoConfig(apiKey: apiKey)
        case .elevenlabs:
            return try elevenLabsConfig(apiKey: apiKey)
        case .whisperKit:
            fatalError("TTSKit config should be handled before this switch")
        }
    }

    private func configuredAPIKey(for provider: TextToSpeechProvider) throws -> String {
        let apiKeyPreferenceKey = Preferences.textToSpeechAPIKeyPreferenceKey(for: provider)
        let apiKey = Preferences.trimmed(defaults.string(forKey: apiKeyPreferenceKey))
        guard !apiKey.isEmpty else { throw SpeechExtensionError.textToSpeechNotConfigured }
        return apiKey
    }

    private func ttsKitConfig() -> TextToSpeechPlaybackManager.SynthesisConfig {
        let model = TTSKitModelCatalog.normalizedModelID(
            defaults.string(forKey: AppPreferenceKeys.ttsTTSKitModel)
        )
        let voice = Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.ttsTTSKitVoice))
        let language = Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.ttsTTSKitLanguage))
        let styleInstruction = TTSKitModelCatalog.preset(for: model)?.supportsStyleInstruction == true
            ? Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.ttsTTSKitStyleInstruction))
            : nil
        let playbackMode = TTSKitPlaybackMode.resolved(
            defaults.string(forKey: AppPreferenceKeys.ttsTTSKitPlaybackMode)
        )

        return .ttsKit(
            TextToSpeechPlaybackManager.TTSKitConfig(
                model: model,
                voice: voice,
                language: language,
                styleInstruction: styleInstruction,
                playbackMode: playbackMode
            )
        )
    }

    private func openAIConfig(apiKey: String) throws -> TextToSpeechPlaybackManager.SynthesisConfig {
        let baseURL = try Preferences.resolvedBaseURL(
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
    }

    private func groqConfig(apiKey: String) throws -> TextToSpeechPlaybackManager.SynthesisConfig {
        let baseURL = try Preferences.resolvedBaseURL(
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
    }

    private func miMoConfig(apiKey: String) throws -> TextToSpeechPlaybackManager.SynthesisConfig {
        let baseURL = try Preferences.resolvedBaseURL(
            defaults.string(forKey: AppPreferenceKeys.ttsMiMoBaseURL),
            fallback: MiMoAudioClient.Constants.defaultBaseURL.absoluteString
        )
        let model = defaults.string(forKey: AppPreferenceKeys.ttsMiMoModel)
            ?? MiMoAudioClient.Constants.defaultModel
        let voiceCloneSamplePath = Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.ttsMiMoVoiceCloneSamplePath))

        return .mimo(
            TextToSpeechPlaybackManager.MiMoConfig(
                apiKey: apiKey,
                baseURL: baseURL,
                model: model,
                voice: Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.ttsMiMoVoice)),
                responseFormat: defaults.string(forKey: AppPreferenceKeys.ttsMiMoResponseFormat)
                    ?? MiMoAudioClient.Constants.defaultResponseFormat,
                styleInstruction: Preferences.normalized(defaults.string(forKey: AppPreferenceKeys.ttsMiMoStyleInstruction)),
                voiceCloneSampleURL: voiceCloneSamplePath.map(URL.init(fileURLWithPath:))
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
