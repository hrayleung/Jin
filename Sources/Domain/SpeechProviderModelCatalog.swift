import Foundation

struct SpeechProviderModelChoice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String

    init(id: String, name: String? = nil) {
        let trimmedID = id.trimmed
        self.id = trimmedID
        self.name = name?.trimmedNonEmpty ?? trimmedID
    }
}

enum SpeechProviderModelCatalog {

    // MARK: - Default selections

    static let defaultOpenAITextToSpeechModelID = "gpt-4o-mini-tts"
    /// OpenRouter no longer serves any OpenAI TTS model.
    static let defaultOpenRouterTextToSpeechModelID = "google/gemini-3.1-flash-tts-preview"
    static let defaultGroqTextToSpeechModelID = "canopylabs/orpheus-v1-english"
    static let defaultMistralTextToSpeechModelID = "voxtral-mini-tts-2603"
    static let defaultElevenLabsTextToSpeechModelID = "eleven_v3"

    static let defaultOpenAISpeechToTextModelID = "gpt-transcribe"
    static let defaultOpenRouterSpeechToTextModelID = "openai/gpt-transcribe"
    static let defaultGroqSpeechToTextModelID = "whisper-large-v3-turbo"
    /// Mistral's batch transcription model. `voxtral-mini-transcribe-2602` is OpenRouter's
    /// canonical slug for the same model and is not a valid ID on api.mistral.ai.
    static let defaultMistralSpeechToTextModelID = "voxtral-mini-2602"
    static let defaultElevenLabsSpeechToTextModelID = "scribe_v2"

    static func defaultTextToSpeechModelID(for provider: TextToSpeechProvider) -> String {
        switch provider {
        case .openai: return defaultOpenAITextToSpeechModelID
        case .openRouter: return defaultOpenRouterTextToSpeechModelID
        case .groq: return defaultGroqTextToSpeechModelID
        case .mistral: return defaultMistralTextToSpeechModelID
        case .elevenlabs: return defaultElevenLabsTextToSpeechModelID
        case .xiaomiMiMo: return MiMoModelIDs.ttsV25
        }
    }

    static func defaultSpeechToTextModelID(for provider: SpeechToTextProvider) -> String {
        switch provider {
        case .openai: return defaultOpenAISpeechToTextModelID
        case .openRouter: return defaultOpenRouterSpeechToTextModelID
        case .groq: return defaultGroqSpeechToTextModelID
        case .mistral: return defaultMistralSpeechToTextModelID
        case .elevenlabs: return defaultElevenLabsSpeechToTextModelID
        }
    }

    // MARK: - Retired model aliases

    /// Model IDs the provider no longer serves, mapped to their live replacements. Applied
    /// defensively at request-build time so a stale preference can never reach the wire.
    private static let legacyTextToSpeechModelIDMap: [TextToSpeechProvider: [String: String]] = [
        .openRouter: [
            "openai/gpt-4o-mini-tts": defaultOpenRouterTextToSpeechModelID,
            "openai/gpt-4o-mini-tts-2025-12-15": defaultOpenRouterTextToSpeechModelID,
            "openai/gpt-4o-mini-tts-2025-03-20": defaultOpenRouterTextToSpeechModelID,
            "openai/tts-1": defaultOpenRouterTextToSpeechModelID,
            "openai/tts-1-hd": defaultOpenRouterTextToSpeechModelID,
            "google/gemini-flash-tts": defaultOpenRouterTextToSpeechModelID,
            "mistralai/voxtral-mini-tts": "mistralai/voxtral-mini-tts-2603"
        ],
        .elevenlabs: [
            "eleven_turbo_v2_5": "eleven_flash_v2_5",
            "eleven_turbo_v2": "eleven_flash_v2",
            "eleven_monolingual_v1": defaultElevenLabsTextToSpeechModelID,
            "eleven_multilingual_v1": defaultElevenLabsTextToSpeechModelID
        ],
        .xiaomiMiMo: [
            MiMoModelIDs.retiredTTSV2: MiMoModelIDs.ttsV25
        ]
    ]

    private static let legacySpeechToTextModelIDMap: [SpeechToTextProvider: [String: String]] = [
        .elevenlabs: [
            "scribe_v1": defaultElevenLabsSpeechToTextModelID
        ],
        .groq: [
            "distil-whisper-large-v3-en": defaultGroqSpeechToTextModelID
        ],
        .mistral: [
            // OpenRouter's slug for the same model; api.mistral.ai rejects it.
            "voxtral-mini-transcribe-2602": defaultMistralSpeechToTextModelID
        ]
    ]

    private static let groqTextToSpeechModelIDs: Set<String> = [
        "canopylabs/orpheus-v1-english",
        "canopylabs/orpheus-arabic-saudi"
    ]

    private static let groqSpeechToTextModelIDs: Set<String> = [
        "whisper-large-v3",
        "whisper-large-v3-turbo"
    ]

    // MARK: - Remote list filtering

    static func textToSpeechChoices(
        for provider: TextToSpeechProvider,
        availableModels: [SpeechProviderModelChoice]
    ) -> [SpeechProviderModelChoice] {
        switch provider {
        case .openai:
            return filteredChoices(availableModels, matches: matchesOpenAITextToSpeechModelID)
        case .openRouter:
            return filteredChoices(availableModels) { _ in true }
        case .groq:
            return filteredChoices(availableModels, matches: matchesGroqTextToSpeechModelID)
        case .mistral:
            return filteredChoices(availableModels, matches: matchesMistralTextToSpeechModelID)
        case .xiaomiMiMo:
            return filteredChoices(availableModels, matches: matchesMiMoTextToSpeechModelID)
        case .elevenlabs:
            return []
        }
    }

    static func speechToTextChoices(
        for provider: SpeechToTextProvider,
        availableModels: [SpeechProviderModelChoice]
    ) -> [SpeechProviderModelChoice] {
        switch provider {
        case .openai:
            return filteredChoices(availableModels, matches: matchesOpenAISpeechToTextModelID)
        case .openRouter:
            return filteredChoices(availableModels) { _ in true }
        case .groq:
            return filteredChoices(availableModels, matches: matchesGroqSpeechToTextModelID)
        case .mistral:
            return filteredChoices(availableModels, matches: matchesMistralSpeechToTextModelID)
        case .elevenlabs:
            return filteredChoices(availableModels, matches: matchesElevenLabsSpeechToTextModelID)
        }
    }

    static func presentingChoices(
        _ choices: [SpeechProviderModelChoice],
        selectedModelID: String
    ) -> [SpeechProviderModelChoice] {
        guard let trimmedSelection = selectedModelID.trimmedNonEmpty else { return choices }
        guard !choices.contains(where: { $0.id == trimmedSelection }) else { return choices }
        return [SpeechProviderModelChoice(id: trimmedSelection)] + choices
    }

    // MARK: - Normalisation

    static func normalizedTextToSpeechModelID(
        for provider: TextToSpeechProvider,
        _ modelID: String?
    ) -> String {
        let trimmedModelID = modelID?.trimmedNonEmpty ?? defaultTextToSpeechModelID(for: provider)
        let aliases = legacyTextToSpeechModelIDMap[provider] ?? [:]
        return aliases[trimmedModelID.lowercased()] ?? trimmedModelID
    }

    static func normalizedSpeechToTextModelID(
        for provider: SpeechToTextProvider,
        _ modelID: String?
    ) -> String {
        let trimmedModelID = modelID?.trimmedNonEmpty ?? defaultSpeechToTextModelID(for: provider)
        let aliases = legacySpeechToTextModelIDMap[provider] ?? [:]
        return aliases[trimmedModelID.lowercased()] ?? trimmedModelID
    }

    static func normalizedOpenRouterTextToSpeechModelID(_ modelID: String?) -> String {
        normalizedTextToSpeechModelID(for: .openRouter, modelID)
    }

    // MARK: - Picker fallbacks

    static func defaultTextToSpeechChoices(
        for provider: TextToSpeechProvider
    ) -> [SpeechProviderModelChoice] {
        switch provider {
        case .openai:
            return [
                SpeechProviderModelChoice(id: defaultOpenAITextToSpeechModelID, name: "GPT-4o mini TTS"),
                SpeechProviderModelChoice(id: "gpt-4o-mini-tts-2025-12-15", name: "GPT-4o mini TTS (2025-12-15)"),
                SpeechProviderModelChoice(id: "tts-1", name: "TTS-1"),
                SpeechProviderModelChoice(id: "tts-1-hd", name: "TTS-1 HD")
            ]
        case .openRouter:
            return [
                SpeechProviderModelChoice(id: defaultOpenRouterTextToSpeechModelID, name: "Google Gemini 3.1 Flash TTS Preview"),
                SpeechProviderModelChoice(id: "microsoft/mai-voice-2", name: "Microsoft MAI-Voice-2"),
                SpeechProviderModelChoice(id: "microsoft/mai-voice-2-flash", name: "Microsoft MAI-Voice-2 Flash"),
                SpeechProviderModelChoice(id: "mistralai/voxtral-mini-tts-2603", name: "Mistral Voxtral Mini TTS"),
                SpeechProviderModelChoice(id: "deepgram/aura-2", name: "Deepgram Aura-2"),
                SpeechProviderModelChoice(id: "minimax/speech-2.8-hd", name: "MiniMax Speech 2.8 HD"),
                SpeechProviderModelChoice(id: "minimax/speech-2.8-turbo", name: "MiniMax Speech 2.8 Turbo"),
                SpeechProviderModelChoice(id: "x-ai/grok-voice-tts-1.0", name: "Grok Voice TTS 1.0"),
                SpeechProviderModelChoice(id: "fish-audio/s2.1-pro", name: "Fish Audio S2.1 Pro"),
                SpeechProviderModelChoice(id: "qwen/qwen-audio-3.0-tts-flash", name: "Qwen Audio 3.0 TTS Flash"),
                SpeechProviderModelChoice(id: "hexgrad/kokoro-82m", name: "Kokoro 82M")
            ]
        case .groq:
            return [
                SpeechProviderModelChoice(id: defaultGroqTextToSpeechModelID, name: "Orpheus English"),
                SpeechProviderModelChoice(id: "canopylabs/orpheus-arabic-saudi", name: "Orpheus Arabic Saudi")
            ]
        case .mistral:
            return [
                SpeechProviderModelChoice(id: defaultMistralTextToSpeechModelID, name: "Voxtral Mini TTS")
            ]
        case .xiaomiMiMo:
            return [
                SpeechProviderModelChoice(id: MiMoModelIDs.ttsV25, name: "MiMo V2.5 TTS"),
                SpeechProviderModelChoice(id: MiMoModelIDs.ttsV25VoiceDesign, name: "MiMo V2.5 TTS VoiceDesign"),
                SpeechProviderModelChoice(id: MiMoModelIDs.ttsV25VoiceClone, name: "MiMo V2.5 TTS VoiceClone")
            ]
        case .elevenlabs:
            return [
                SpeechProviderModelChoice(id: defaultElevenLabsTextToSpeechModelID, name: "Eleven v3"),
                SpeechProviderModelChoice(id: "eleven_multilingual_v2", name: "Eleven Multilingual v2"),
                SpeechProviderModelChoice(id: "eleven_flash_v2_5", name: "Eleven Flash v2.5"),
                SpeechProviderModelChoice(id: "eleven_flash_v2", name: "Eleven Flash v2"),
                SpeechProviderModelChoice(id: "eleven_ttv_v3", name: "Eleven TTV v3")
            ]
        }
    }

    static func defaultSpeechToTextChoices(
        for provider: SpeechToTextProvider
    ) -> [SpeechProviderModelChoice] {
        switch provider {
        case .openai:
            return [
                SpeechProviderModelChoice(id: defaultOpenAISpeechToTextModelID, name: "GPT Transcribe"),
                SpeechProviderModelChoice(id: "gpt-4o-transcribe-diarize", name: "GPT-4o Transcribe Diarize"),
                SpeechProviderModelChoice(id: "whisper-1", name: "Whisper-1"),
                SpeechProviderModelChoice(id: "gpt-4o-transcribe", name: "GPT-4o Transcribe"),
                SpeechProviderModelChoice(id: "gpt-4o-mini-transcribe", name: "GPT-4o mini Transcribe")
            ]
        case .openRouter:
            return [
                SpeechProviderModelChoice(id: defaultOpenRouterSpeechToTextModelID, name: "OpenAI GPT Transcribe"),
                SpeechProviderModelChoice(id: "openai/whisper-large-v3-turbo", name: "OpenAI Whisper Large v3 Turbo"),
                SpeechProviderModelChoice(id: "openai/whisper-large-v3", name: "OpenAI Whisper Large v3"),
                SpeechProviderModelChoice(id: "x-ai/grok-stt-1.0", name: "Grok STT 1.0"),
                SpeechProviderModelChoice(id: "deepgram/nova-3", name: "Deepgram Nova-3"),
                SpeechProviderModelChoice(id: "microsoft/mai-transcribe-1.5", name: "Microsoft MAI-Transcribe 1.5"),
                SpeechProviderModelChoice(id: "mistralai/voxtral-mini-transcribe", name: "Mistral Voxtral Mini Transcribe"),
                SpeechProviderModelChoice(id: "qwen/qwen3-asr-flash-2026-02-10", name: "Qwen3 ASR Flash"),
                SpeechProviderModelChoice(id: "nvidia/parakeet-tdt-0.6b-v3", name: "NVIDIA Parakeet TDT 0.6B v3"),
                SpeechProviderModelChoice(id: "google/chirp-3", name: "Google Chirp 3")
            ]
        case .groq:
            return [
                SpeechProviderModelChoice(id: defaultGroqSpeechToTextModelID, name: "Whisper Large v3 Turbo"),
                SpeechProviderModelChoice(id: "whisper-large-v3", name: "Whisper Large v3")
            ]
        case .mistral:
            return [
                SpeechProviderModelChoice(id: defaultMistralSpeechToTextModelID, name: "Voxtral Mini Transcribe 2"),
                // On the transcription endpoint this alias resolves to voxtral-mini-2602.
                SpeechProviderModelChoice(id: "voxtral-mini-latest", name: "Voxtral Mini Latest")
            ]
        case .elevenlabs:
            return [
                SpeechProviderModelChoice(id: defaultElevenLabsSpeechToTextModelID, name: "Scribe v2")
            ]
        }
    }

    private static func filteredChoices(
        _ choices: [SpeechProviderModelChoice],
        matches: (String) -> Bool
    ) -> [SpeechProviderModelChoice] {
        var seenIDs = Set<String>()

        return choices
            .filter { choice in
                guard let modelID = choice.id.trimmedNonEmpty else { return false }
                guard matches(modelID.lowercased()) else { return false }
                guard seenIDs.insert(modelID).inserted else { return false }
                return true
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private static func matchesOpenAITextToSpeechModelID(_ modelID: String) -> Bool {
        modelID == "tts-1"
            || modelID == "tts-1-hd"
            || modelID == "gpt-4o-mini-tts"
            || modelID.hasPrefix("gpt-4o-mini-tts-")
    }

    private static func matchesOpenAISpeechToTextModelID(_ modelID: String) -> Bool {
        // Realtime-only models cannot transcribe an uploaded file.
        guard !modelID.contains("realtime"), !modelID.hasPrefix("gpt-live-") else { return false }

        return modelID == "whisper-1"
            || SpeechModelCapabilityRegistry.isGPTTranscribeModelID(modelID)
            || modelID == "gpt-4o-transcribe"
            || modelID.hasPrefix("gpt-4o-transcribe-")
            || modelID == "gpt-4o-mini-transcribe"
            || modelID.hasPrefix("gpt-4o-mini-transcribe-")
    }

    private static func matchesGroqTextToSpeechModelID(_ modelID: String) -> Bool {
        groqTextToSpeechModelIDs.contains(modelID)
    }

    private static func matchesMistralTextToSpeechModelID(_ modelID: String) -> Bool {
        modelID.contains("voxtral") && modelID.contains("tts")
    }

    private static func matchesMiMoTextToSpeechModelID(_ modelID: String) -> Bool {
        MiMoModelIDs.textToSpeechModelIDs.contains(modelID)
    }

    private static func matchesGroqSpeechToTextModelID(_ modelID: String) -> Bool {
        groqSpeechToTextModelIDs.contains(modelID)
    }

    /// Deliberately conservative: `/models` also lists the Voxtral *chat* models
    /// (`voxtral-mini-2507`, `voxtral-small-*`), which cannot transcribe.
    private static func matchesMistralSpeechToTextModelID(_ modelID: String) -> Bool {
        guard !modelID.contains("realtime") else { return false }

        return modelID == "voxtral-mini-latest"
            || modelID == defaultMistralSpeechToTextModelID
            || (modelID.contains("voxtral") && modelID.contains("transcribe"))
    }

    private static func matchesElevenLabsSpeechToTextModelID(_ modelID: String) -> Bool {
        modelID.hasPrefix("scribe_") && !modelID.contains("realtime")
    }
}
