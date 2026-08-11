import Foundation

/// Rewrites stored speech model selections that providers have retired or superseded.
///
/// Version-gated so it runs exactly once. Without the gate a user who deliberately picks
/// `eleven_flash_v2_5` after upgrading would have it silently rewritten to `eleven_v3` on the
/// next launch, forever.
enum SpeechModelPreferenceMigration {
    /// Bump when a new wave of retirements needs another one-shot pass.
    static let currentVersion = 1

    static func run(defaults: UserDefaults = .standard) {
        let storedVersion = defaults.integer(forKey: AppPreferenceKeys.speechModelMigrationVersion)
        guard storedVersion < currentVersion else { return }

        migrateTextToSpeech(defaults: defaults)
        migrateSpeechToText(defaults: defaults)

        defaults.set(currentVersion, forKey: AppPreferenceKeys.speechModelMigrationVersion)
    }

    // MARK: - Text to speech

    private static func migrateTextToSpeech(defaults: UserDefaults) {
        migrateOpenAITextToSpeech(defaults: defaults)
        migrateOpenRouterTextToSpeech(defaults: defaults)
        migrateGroqTextToSpeech(defaults: defaults)
        migrateMiMoTextToSpeech(defaults: defaults)
        migrateElevenLabsTextToSpeech(defaults: defaults)
    }

    private static func migrateOpenAITextToSpeech(defaults: UserDefaults) {
        guard let model = storedModel(defaults, AppPreferenceKeys.ttsOpenAIModel) else { return }

        // The tts-1 generation predates instructions, streaming and the expressive voices.
        if model == "tts-1" || model == "tts-1-hd" {
            defaults.set(
                SpeechProviderModelCatalog.defaultOpenAITextToSpeechModelID,
                forKey: AppPreferenceKeys.ttsOpenAIModel
            )
        }

        clampVoice(
            defaults,
            key: AppPreferenceKeys.ttsOpenAIVoice,
            provider: .openai,
            model: storedModel(defaults, AppPreferenceKeys.ttsOpenAIModel) ?? model
        )
    }

    private static func migrateOpenRouterTextToSpeech(defaults: UserDefaults) {
        guard let model = storedModel(defaults, AppPreferenceKeys.ttsOpenRouterModel) else { return }
        let migrated = SpeechProviderModelCatalog.normalizedTextToSpeechModelID(for: .openRouter, model)
        guard migrated != model else { return }

        defaults.set(migrated, forKey: AppPreferenceKeys.ttsOpenRouterModel)

        // OpenRouter dropped every OpenAI TTS model, so `alloy` and friends are no longer
        // valid anywhere in its catalog.
        if migrated == SpeechProviderModelCatalog.defaultOpenRouterTextToSpeechModelID {
            defaults.set(defaultOpenRouterVoice, forKey: AppPreferenceKeys.ttsOpenRouterVoice)
        }
    }

    private static func migrateGroqTextToSpeech(defaults: UserDefaults) {
        guard let model = storedModel(defaults, AppPreferenceKeys.ttsGroqModel) else { return }
        clampVoice(
            defaults,
            key: AppPreferenceKeys.ttsGroqVoice,
            provider: .groq,
            model: model
        )
    }

    private static func migrateMiMoTextToSpeech(defaults: UserDefaults) {
        guard let model = storedModel(defaults, AppPreferenceKeys.ttsMiMoModel) else { return }
        let migrated = SpeechProviderModelCatalog.normalizedTextToSpeechModelID(for: .xiaomiMiMo, model)
        if migrated != model {
            defaults.set(migrated, forKey: AppPreferenceKeys.ttsMiMoModel)
        }

        clampVoice(
            defaults,
            key: AppPreferenceKeys.ttsMiMoVoice,
            provider: .xiaomiMiMo,
            model: migrated
        )

        // The V2.5 series dropped mp3 and raw pcm.
        let capabilities = SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: .xiaomiMiMo,
            modelID: migrated
        )
        clampFormat(
            defaults,
            key: AppPreferenceKeys.ttsMiMoResponseFormat,
            supported: capabilities.responseFormats,
            fallback: MiMoAudioClient.Constants.defaultResponseFormat
        )
    }

    private static func migrateElevenLabsTextToSpeech(defaults: UserDefaults) {
        guard let model = storedModel(defaults, AppPreferenceKeys.ttsElevenLabsModelID) else { return }

        // Every in-catalog model is superseded by the v3 flagship.
        let migrated = model == "eleven_ttv_v3"
            ? model
            : SpeechProviderModelCatalog.defaultElevenLabsTextToSpeechModelID
        if migrated != model {
            defaults.set(migrated, forKey: AppPreferenceKeys.ttsElevenLabsModelID)
        }

        // v3 accepts only three discrete stability values.
        let capabilities = SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: .elevenlabs,
            modelID: migrated
        )
        guard let allowed = capabilities.stabilityValues,
              let stored = defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsStability) as? Double,
              !allowed.contains(stored),
              let nearest = allowed.min(by: { abs($0 - stored) < abs($1 - stored) }) else {
            return
        }
        defaults.set(nearest, forKey: AppPreferenceKeys.ttsElevenLabsStability)
    }

    // MARK: - Speech to text

    private static func migrateSpeechToText(defaults: UserDefaults) {
        migrateOpenAISpeechToText(defaults: defaults)
        migrateOpenRouterSpeechToText(defaults: defaults)
        migrateMistralSpeechToText(defaults: defaults)
        migrateElevenLabsSpeechToText(defaults: defaults)

        // Groq's model list is unchanged, but its response format never accepted srt/vtt.
        clampTranscriptionResponseFormat(
            defaults,
            key: AppPreferenceKeys.sttGroqResponseFormat,
            provider: .groq,
            model: storedModel(defaults, AppPreferenceKeys.sttGroqModel)
                ?? SpeechProviderModelCatalog.defaultGroqSpeechToTextModelID
        )
    }

    private static func migrateOpenAISpeechToText(defaults: UserDefaults) {
        guard let model = storedModel(defaults, AppPreferenceKeys.sttOpenAIModel) else { return }
        // Diarize is a deliberate capability choice, not a stale default, so leave it alone.
        let isSuperseded = model == "whisper-1"
            || (model.hasPrefix("gpt-4o-transcribe") && !model.contains("diarize"))
            || model.hasPrefix("gpt-4o-mini-transcribe")

        if isSuperseded {
            defaults.set(
                SpeechProviderModelCatalog.defaultOpenAISpeechToTextModelID,
                forKey: AppPreferenceKeys.sttOpenAIModel
            )
        }

        let migrated = storedModel(defaults, AppPreferenceKeys.sttOpenAIModel) ?? model
        let capabilities = SpeechModelCapabilityRegistry.transcriptionCapabilities(
            provider: .openai,
            modelID: migrated
        )

        clampFormat(
            defaults,
            key: AppPreferenceKeys.sttOpenAIResponseFormat,
            supported: capabilities.responseFormats,
            fallback: "json"
        )
        if capabilities.timestampGranularities.isEmpty {
            defaults.set("[]", forKey: AppPreferenceKeys.sttOpenAITimestampGranularitiesJSON)
        }
        if !capabilities.supportsTranslation {
            defaults.set(false, forKey: AppPreferenceKeys.sttOpenAITranslateToEnglish)
        }
    }

    private static func migrateOpenRouterSpeechToText(defaults: UserDefaults) {
        guard let model = storedModel(defaults, AppPreferenceKeys.sttOpenRouterModel) else { return }
        let isSuperseded = model.hasPrefix("openai/whisper")
            || (model.hasPrefix("openai/gpt-4o") && model.contains("transcribe"))

        if isSuperseded {
            defaults.set(
                SpeechProviderModelCatalog.defaultOpenRouterSpeechToTextModelID,
                forKey: AppPreferenceKeys.sttOpenRouterModel
            )
        }

        clampTranscriptionResponseFormat(
            defaults,
            key: AppPreferenceKeys.sttOpenRouterResponseFormat,
            provider: .openRouter,
            model: storedModel(defaults, AppPreferenceKeys.sttOpenRouterModel) ?? model
        )
    }

    private static func migrateMistralSpeechToText(defaults: UserDefaults) {
        guard let model = storedModel(defaults, AppPreferenceKeys.sttMistralModel) else { return }
        if model == "voxtral-mini-latest" {
            defaults.set(
                SpeechProviderModelCatalog.defaultMistralSpeechToTextModelID,
                forKey: AppPreferenceKeys.sttMistralModel
            )
        }

        clampTranscriptionResponseFormat(
            defaults,
            key: AppPreferenceKeys.sttMistralResponseFormat,
            provider: .mistral,
            model: storedModel(defaults, AppPreferenceKeys.sttMistralModel) ?? model
        )
    }

    private static func migrateElevenLabsSpeechToText(defaults: UserDefaults) {
        guard let model = storedModel(defaults, AppPreferenceKeys.sttElevenLabsModel) else { return }
        let migrated = SpeechProviderModelCatalog.normalizedSpeechToTextModelID(for: .elevenlabs, model)
        guard migrated != model else { return }
        defaults.set(migrated, forKey: AppPreferenceKeys.sttElevenLabsModel)
    }

    // MARK: - Helpers

    /// First voice of the OpenRouter default model's published catalog.
    private static let defaultOpenRouterVoice = "Zephyr"

    /// `nil` when the provider was never configured — an install with nothing stored has
    /// nothing to migrate, and writing defaults for it would materialise keys the settings
    /// views own.
    private static func storedModel(_ defaults: UserDefaults, _ key: String) -> String? {
        guard let raw = defaults.string(forKey: key)?.trimmedNonEmpty else { return nil }
        return raw.lowercased()
    }

    private static func clampVoice(
        _ defaults: UserDefaults,
        key: String,
        provider: TextToSpeechProvider,
        model: String
    ) {
        let capabilities = SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: provider,
            modelID: model
        )
        guard let voices = capabilities.voices, !voices.isEmpty else { return }
        guard let stored = defaults.string(forKey: key)?.trimmedNonEmpty else { return }

        // Match case-insensitively so a valid selection is never discarded over spelling,
        // but write back the catalog's own casing — the wire value has to be exact.
        guard let canonical = SpeechModelCapabilityRegistry.canonicalVoice(stored, in: voices) else {
            defaults.set(voices[0], forKey: key)
            return
        }
        if canonical != stored {
            defaults.set(canonical, forKey: key)
        }
    }

    private static func clampFormat(
        _ defaults: UserDefaults,
        key: String,
        supported: [String],
        fallback: String
    ) {
        guard !supported.isEmpty else { return }
        guard let stored = defaults.string(forKey: key)?.trimmedNonEmpty else { return }
        guard !supported.contains(stored.lowercased()) else { return }
        defaults.set(fallback, forKey: key)
    }

    private static func clampTranscriptionResponseFormat(
        _ defaults: UserDefaults,
        key: String,
        provider: SpeechToTextProvider,
        model: String
    ) {
        let capabilities = SpeechModelCapabilityRegistry.transcriptionCapabilities(
            provider: provider,
            modelID: model
        )
        clampFormat(defaults, key: key, supported: capabilities.responseFormats, fallback: "json")
    }
}
