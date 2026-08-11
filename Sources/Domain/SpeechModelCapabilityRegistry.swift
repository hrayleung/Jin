import Foundation

/// PCM streaming shape for a text-to-speech model.
///
/// Every streaming path Jin supports returns 16-bit signed little-endian mono PCM, so the
/// only things that vary are the format string to request and the sample rate of the frames.
struct SpeechStreamingCapability: Sendable, Equatable {
    /// The `response_format` / `output_format` Jin must request to receive streamable PCM.
    let responseFormat: String
    let sampleRate: Double
}

/// How a transcription model expects the spoken-language hint to be passed.
enum SpeechLanguageParameterStyle: Sendable, Equatable {
    case none
    /// Singular `language` form field.
    case single
    /// Repeated `languages[]` form fields. Sending `language` as well is rejected.
    case multiple
}

struct SpeechSynthesisCapabilities: Sendable, Equatable {
    /// `nil` means the voice list is not enumerable locally — it is fetched from the
    /// provider or typed free-form.
    let voices: [String]?
    let responseFormats: [String]
    let supportsInstructions: Bool
    let supportsSpeed: Bool
    /// Discrete stability values, when the model rejects the continuous 0...1 range.
    let stabilityValues: [Double]?
    let maxInputCharacters: Int
    let streaming: SpeechStreamingCapability?
}

struct SpeechTranscriptionCapabilities: Sendable, Equatable {
    let responseFormats: [String]
    let languageParameter: SpeechLanguageParameterStyle
    let supportsPrompt: Bool
    let supportsKeywords: Bool
    let supportsTemperature: Bool
    /// Empty means the model returns no timestamps at all.
    let timestampGranularities: [String]
    let supportsTranslation: Bool
    let supportsDiarization: Bool
    /// Mistral rejects `timestamp_granularities` and `language` in the same request.
    let timestampsConflictWithLanguage: Bool
}

/// Per-model wire constraints for the speech plugins.
///
/// This mirrors `ModelCapabilityRegistry` for chat models: anything that varies per model and
/// would otherwise produce a 400 lives here, so the settings UI and the request builders can
/// never disagree about what a model accepts.
enum SpeechModelCapabilityRegistry {

    // MARK: - Voice catalogs

    /// `gpt-4o-mini-tts` supports the full set; OpenAI recommends `marin` and `cedar`.
    static let openAIVoices: [String] = [
        "alloy",
        "ash",
        "ballad",
        "cedar",
        "coral",
        "echo",
        "fable",
        "marin",
        "nova",
        "onyx",
        "sage",
        "shimmer",
        "verse"
    ]

    /// `tts-1` / `tts-1-hd` predate the expressive voices.
    static let openAILegacyVoices: [String] = [
        "alloy",
        "ash",
        "coral",
        "echo",
        "fable",
        "nova",
        "onyx",
        "sage",
        "shimmer"
    ]

    static let groqOrpheusEnglishVoices: [String] = [
        "autumn",
        "diana",
        "hannah",
        "austin",
        "daniel",
        "troy"
    ]

    static let groqOrpheusArabicVoices: [String] = [
        "abdullah",
        "fahad",
        "sultan",
        "lulwa",
        "noura",
        "aisha"
    ]

    static let miMoVoices: [String] = [
        "mimo_default",
        "冰糖",
        "茉莉",
        "苏打",
        "白桦",
        "Mia",
        "Chloe",
        "Milo",
        "Dean"
    ]

    // MARK: - Format catalogs

    /// OpenAI also emits `opus`, but Ogg-wrapped Opus is not decodable by `AVAudioPlayer`
    /// or `AVAudioFile`, which would break playback and waveform extraction alike.
    static let openAIResponseFormats: [String] = ["mp3", "wav", "aac", "flac", "pcm"]

    static let openRouterResponseFormats: [String] = ["mp3", "pcm"]

    /// Mistral's `pcm` is raw float32 LE at an undocumented rate, not the 16-bit shape every
    /// other provider returns, so the shared normalizer would mis-frame it. Excluded until
    /// there is a documented sample rate to build a float32 container from.
    static let mistralResponseFormats: [String] = ["mp3", "wav", "flac"]

    static let elevenLabsOutputFormats: [String] = [
        "mp3_22050_32",
        "mp3_24000_48",
        "mp3_44100_32",
        "mp3_44100_64",
        "mp3_44100_96",
        "mp3_44100_128",
        "mp3_44100_192",
        "pcm_8000",
        "pcm_16000",
        "pcm_22050",
        "pcm_24000",
        "pcm_32000",
        "pcm_44100",
        "pcm_48000",
        "wav_8000",
        "wav_16000",
        "wav_22050",
        "wav_24000",
        "wav_32000",
        "wav_44100",
        "wav_48000"
    ]

    static let speechToTextResponseFormats: [String] = [
        "json",
        "text",
        "verbose_json",
        "srt",
        "vtt"
    ]

    // MARK: - Text to speech

    static func synthesisCapabilities(
        provider: TextToSpeechProvider,
        modelID: String
    ) -> SpeechSynthesisCapabilities {
        let model = modelID.trimmedLowercased

        switch provider {
        case .openai:
            return openAISynthesisCapabilities(model: model)
        case .openRouter:
            return SpeechSynthesisCapabilities(
                voices: nil,
                responseFormats: openRouterResponseFormats,
                supportsInstructions: false,
                supportsSpeed: false,
                stabilityValues: nil,
                maxInputCharacters: 4096,
                streaming: nil
            )
        case .groq:
            return groqSynthesisCapabilities(model: model)
        case .mistral:
            return SpeechSynthesisCapabilities(
                voices: nil,
                responseFormats: mistralResponseFormats,
                supportsInstructions: false,
                supportsSpeed: false,
                stabilityValues: nil,
                maxInputCharacters: 4096,
                streaming: nil
            )
        case .elevenlabs:
            return elevenLabsSynthesisCapabilities(model: model)
        case .xiaomiMiMo:
            return miMoSynthesisCapabilities(model: model)
        }
    }

    private static func openAISynthesisCapabilities(model: String) -> SpeechSynthesisCapabilities {
        // `instructions` and `stream_format` are both rejected by the tts-1 generation,
        // including its dated snapshots (`tts-1-1106`, `tts-1-hd-1106`).
        let isLegacy = model == "tts-1" || model == "tts-1-hd" || model.hasPrefix("tts-1-")

        return SpeechSynthesisCapabilities(
            voices: isLegacy ? openAILegacyVoices : openAIVoices,
            responseFormats: openAIResponseFormats,
            supportsInstructions: !isLegacy,
            supportsSpeed: true,
            stabilityValues: nil,
            maxInputCharacters: 4096,
            streaming: isLegacy
                ? nil
                : SpeechStreamingCapability(responseFormat: "pcm", sampleRate: 24_000)
        )
    }

    private static func groqSynthesisCapabilities(model: String) -> SpeechSynthesisCapabilities {
        let voices = model == "canopylabs/orpheus-arabic-saudi"
            ? groqOrpheusArabicVoices
            : groqOrpheusEnglishVoices

        return SpeechSynthesisCapabilities(
            voices: voices,
            responseFormats: ["wav"],
            supportsInstructions: false,
            supportsSpeed: false,
            stabilityValues: nil,
            maxInputCharacters: 200,
            streaming: nil
        )
    }

    private static func elevenLabsSynthesisCapabilities(model: String) -> SpeechSynthesisCapabilities {
        // v3 rejects `speed` and only accepts three discrete stability values.
        let isV3 = model == "eleven_v3" || model == "eleven_ttv_v3"

        return SpeechSynthesisCapabilities(
            voices: nil,
            responseFormats: elevenLabsOutputFormats,
            supportsInstructions: false,
            supportsSpeed: !isV3,
            stabilityValues: isV3 ? [0.0, 0.5, 1.0] : nil,
            maxInputCharacters: elevenLabsMaxInputCharacters(model: model),
            streaming: SpeechStreamingCapability(responseFormat: "pcm_24000", sampleRate: 24_000)
        )
    }

    private static func elevenLabsMaxInputCharacters(model: String) -> Int {
        switch model {
        case "eleven_flash_v2_5": return 40_000
        case "eleven_flash_v2": return 30_000
        case "eleven_multilingual_v2": return 10_000
        case "eleven_v3", "eleven_ttv_v3": return 5_000
        default: return 5_000
        }
    }

    private static func miMoSynthesisCapabilities(model: String) -> SpeechSynthesisCapabilities {
        // VoiceDesign and VoiceClone derive the voice from a prompt or a sample, and the
        // platform documents streaming as degraded (single delivery) for both.
        let usesPresetVoice = model == MiMoModelIDs.ttsV25

        return SpeechSynthesisCapabilities(
            voices: usesPresetVoice ? miMoVoices : nil,
            responseFormats: MiMoModelIDs.textToSpeechResponseFormats,
            supportsInstructions: false,
            supportsSpeed: false,
            stabilityValues: nil,
            maxInputCharacters: 4096,
            streaming: usesPresetVoice
                ? SpeechStreamingCapability(responseFormat: "pcm16", sampleRate: 24_000)
                : nil
        )
    }

    // MARK: - Speech to text

    static func transcriptionCapabilities(
        provider: SpeechToTextProvider,
        modelID: String
    ) -> SpeechTranscriptionCapabilities {
        let model = modelID.trimmedLowercased

        switch provider {
        case .openai:
            return openAITranscriptionCapabilities(model: model)
        case .openRouter:
            // OpenRouter rejects text/srt/vtt on the transcription endpoint.
            return SpeechTranscriptionCapabilities(
                responseFormats: ["json", "verbose_json"],
                languageParameter: .single,
                supportsPrompt: false,
                supportsKeywords: false,
                supportsTemperature: true,
                timestampGranularities: ["segment", "word"],
                supportsTranslation: false,
                supportsDiarization: false,
                timestampsConflictWithLanguage: false
            )
        case .groq:
            return SpeechTranscriptionCapabilities(
                responseFormats: ["json", "text", "verbose_json"],
                languageParameter: .single,
                supportsPrompt: true,
                supportsKeywords: false,
                supportsTemperature: true,
                timestampGranularities: ["segment", "word"],
                supportsTranslation: true,
                supportsDiarization: false,
                timestampsConflictWithLanguage: false
            )
        case .mistral:
            return SpeechTranscriptionCapabilities(
                responseFormats: ["json", "text", "verbose_json"],
                languageParameter: .single,
                supportsPrompt: true,
                supportsKeywords: false,
                supportsTemperature: true,
                timestampGranularities: ["segment", "word"],
                supportsTranslation: false,
                supportsDiarization: true,
                timestampsConflictWithLanguage: true
            )
        case .elevenlabs:
            // ElevenLabs has its own client and parameter names; the shared fields do not apply.
            return SpeechTranscriptionCapabilities(
                responseFormats: [],
                languageParameter: .single,
                supportsPrompt: false,
                supportsKeywords: false,
                supportsTemperature: true,
                timestampGranularities: ["word", "character"],
                supportsTranslation: false,
                supportsDiarization: true,
                timestampsConflictWithLanguage: false
            )
        }
    }

    private static func openAITranscriptionCapabilities(
        model: String
    ) -> SpeechTranscriptionCapabilities {
        if model == "whisper-1" {
            return SpeechTranscriptionCapabilities(
                responseFormats: speechToTextResponseFormats,
                languageParameter: .single,
                supportsPrompt: true,
                supportsKeywords: false,
                supportsTemperature: true,
                timestampGranularities: ["segment", "word"],
                supportsTranslation: true,
                supportsDiarization: false,
                timestampsConflictWithLanguage: false
            )
        }

        if model == "gpt-4o-transcribe-diarize" || model.hasPrefix("gpt-4o-transcribe-diarize-") {
            return SpeechTranscriptionCapabilities(
                responseFormats: ["json", "text", "diarized_json"],
                languageParameter: .single,
                supportsPrompt: true,
                supportsKeywords: false,
                supportsTemperature: false,
                timestampGranularities: [],
                supportsTranslation: false,
                supportsDiarization: true,
                timestampsConflictWithLanguage: false
            )
        }

        if isGPTTranscribeModelID(model) {
            // Takes `languages[]` and `keywords[]`; sending `language` alongside is rejected,
            // and it returns neither timestamps nor subtitle formats.
            return SpeechTranscriptionCapabilities(
                responseFormats: ["json"],
                languageParameter: .multiple,
                supportsPrompt: true,
                supportsKeywords: true,
                supportsTemperature: false,
                timestampGranularities: [],
                supportsTranslation: false,
                supportsDiarization: false,
                timestampsConflictWithLanguage: false
            )
        }

        // gpt-4o-transcribe / gpt-4o-mini-transcribe: json only, singular language hint.
        return SpeechTranscriptionCapabilities(
            responseFormats: ["json"],
            languageParameter: .single,
            supportsPrompt: true,
            supportsKeywords: false,
            supportsTemperature: true,
            timestampGranularities: [],
            supportsTranslation: false,
            supportsDiarization: false,
            timestampsConflictWithLanguage: false
        )
    }

    /// `gpt-transcribe` and its dated snapshots, but not the `gpt-4o-*` generation.
    static func isGPTTranscribeModelID(_ modelID: String) -> Bool {
        let model = modelID.trimmedLowercased
        return model == "gpt-transcribe" || model.hasPrefix("gpt-transcribe-")
    }

    // MARK: - Normalisation helpers

    /// Clamps a stored selection to something the model actually accepts, so a stale
    /// preference can never produce a 400.
    static func resolvedResponseFormat(
        _ responseFormat: String?,
        supported: [String],
        fallback: String
    ) -> String? {
        guard !supported.isEmpty else { return nil }
        guard let value = responseFormat?.trimmedNonEmpty?.lowercased() else { return fallback }
        return supported.contains(value) ? value : fallback
    }

    /// Matches case-insensitively but returns the catalog's own spelling — several catalogs
    /// are mixed case (`Mia`, `Zephyr`) and the wire value has to be exact.
    static func resolvedVoice(_ voice: String?, capabilities: SpeechSynthesisCapabilities) -> String? {
        guard let voices = capabilities.voices, !voices.isEmpty else {
            return voice?.trimmedNonEmpty
        }
        guard let value = voice?.trimmedNonEmpty else { return voices.first }
        return canonicalVoice(value, in: voices) ?? voices.first
    }

    /// The catalog entry matching `voice` case-insensitively, or `nil` when it is unsupported.
    static func canonicalVoice(_ voice: String, in voices: [String]) -> String? {
        voices.first { $0.caseInsensitiveCompare(voice) == .orderedSame }
    }
}
