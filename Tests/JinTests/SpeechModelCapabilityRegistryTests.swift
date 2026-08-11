import XCTest
@testable import Jin

final class SpeechModelCapabilityRegistryTests: XCTestCase {

    // MARK: - Transcription

    /// The recommended file-transcription model takes `languages[]` and `keywords[]` and
    /// returns neither timestamps nor subtitle formats.
    func testGPTTranscribeCapabilities() {
        let capabilities = SpeechModelCapabilityRegistry.transcriptionCapabilities(
            provider: .openai,
            modelID: "gpt-transcribe"
        )

        XCTAssertEqual(capabilities.responseFormats, ["json"])
        XCTAssertEqual(capabilities.languageParameter, .multiple)
        XCTAssertTrue(capabilities.supportsKeywords)
        XCTAssertTrue(capabilities.supportsPrompt)
        XCTAssertFalse(capabilities.supportsTemperature)
        XCTAssertTrue(capabilities.timestampGranularities.isEmpty)
        XCTAssertFalse(capabilities.supportsTranslation)
        XCTAssertFalse(capabilities.supportsDiarization)
    }

    /// whisper-1 remains the only OpenAI model that emits subtitles, timestamps and
    /// translations.
    func testWhisperRemainsTheFullFeaturedTranscriptionModel() {
        let capabilities = SpeechModelCapabilityRegistry.transcriptionCapabilities(
            provider: .openai,
            modelID: "whisper-1"
        )

        XCTAssertEqual(capabilities.responseFormats, ["json", "text", "verbose_json", "srt", "vtt"])
        XCTAssertEqual(capabilities.languageParameter, .single)
        XCTAssertTrue(capabilities.supportsTemperature)
        XCTAssertEqual(capabilities.timestampGranularities, ["segment", "word"])
        XCTAssertTrue(capabilities.supportsTranslation)
    }

    func testDiarizeModelExposesDiarizedJSONOnly() {
        let capabilities = SpeechModelCapabilityRegistry.transcriptionCapabilities(
            provider: .openai,
            modelID: "gpt-4o-transcribe-diarize"
        )

        XCTAssertEqual(capabilities.responseFormats, ["json", "text", "diarized_json"])
        XCTAssertTrue(capabilities.supportsDiarization)
        XCTAssertTrue(capabilities.timestampGranularities.isEmpty)
    }

    func testGPT4oTranscribeGenerationIsJSONOnly() {
        for model in ["gpt-4o-transcribe", "gpt-4o-mini-transcribe"] {
            let capabilities = SpeechModelCapabilityRegistry.transcriptionCapabilities(
                provider: .openai,
                modelID: model
            )
            XCTAssertEqual(capabilities.responseFormats, ["json"], model)
            XCTAssertEqual(capabilities.languageParameter, .single, model)
        }
    }

    /// Groq and OpenRouter both reject subtitle formats on the transcription endpoint.
    func testProvidersWithoutSubtitleSupport() {
        XCTAssertEqual(
            SpeechModelCapabilityRegistry.transcriptionCapabilities(
                provider: .groq,
                modelID: "whisper-large-v3-turbo"
            ).responseFormats,
            ["json", "text", "verbose_json"]
        )

        XCTAssertEqual(
            SpeechModelCapabilityRegistry.transcriptionCapabilities(
                provider: .openRouter,
                modelID: "openai/gpt-transcribe"
            ).responseFormats,
            ["json", "verbose_json"]
        )
    }

    func testMistralFlagsTimestampLanguageConflict() {
        let capabilities = SpeechModelCapabilityRegistry.transcriptionCapabilities(
            provider: .mistral,
            modelID: "voxtral-mini-2602"
        )

        XCTAssertTrue(capabilities.timestampsConflictWithLanguage)
        XCTAssertTrue(capabilities.supportsDiarization)
    }

    func testIsGPTTranscribeModelIDExcludesTheGPT4oGeneration() {
        XCTAssertTrue(SpeechModelCapabilityRegistry.isGPTTranscribeModelID("gpt-transcribe"))
        XCTAssertTrue(SpeechModelCapabilityRegistry.isGPTTranscribeModelID("gpt-transcribe-20260805"))
        XCTAssertFalse(SpeechModelCapabilityRegistry.isGPTTranscribeModelID("gpt-4o-transcribe"))
        XCTAssertFalse(SpeechModelCapabilityRegistry.isGPTTranscribeModelID("gpt-live-transcribe"))
    }

    // MARK: - Synthesis

    /// `instructions` and `stream_format` are both rejected by the tts-1 generation, which
    /// also predates the expressive voices.
    func testLegacyOpenAITTSModelsAreRestricted() {
        let legacy = SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: .openai,
            modelID: "tts-1-hd"
        )

        XCTAssertFalse(legacy.supportsInstructions)
        XCTAssertNil(legacy.streaming)
        XCTAssertEqual(legacy.voices, SpeechModelCapabilityRegistry.openAILegacyVoices)
        XCTAssertFalse(legacy.voices?.contains("marin") ?? true)

        let current = SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: .openai,
            modelID: "gpt-4o-mini-tts"
        )
        XCTAssertTrue(current.supportsInstructions)
        XCTAssertEqual(current.streaming?.responseFormat, "pcm")
        XCTAssertEqual(current.voices?.count, 13)
    }

    /// v3 rejects `speed` and only accepts three discrete stability values.
    func testElevenLabsV3RejectsSpeedAndQuantizesStability() {
        let v3 = SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: .elevenlabs,
            modelID: "eleven_v3"
        )
        XCTAssertFalse(v3.supportsSpeed)
        XCTAssertEqual(v3.stabilityValues, [0.0, 0.5, 1.0])
        XCTAssertEqual(v3.maxInputCharacters, 5_000)

        let flash = SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: .elevenlabs,
            modelID: "eleven_flash_v2_5"
        )
        XCTAssertTrue(flash.supportsSpeed)
        XCTAssertNil(flash.stabilityValues)
        XCTAssertEqual(flash.maxInputCharacters, 40_000)
    }

    func testGroqVoiceCatalogsAreDisjointPerModel() {
        let english = SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: .groq,
            modelID: "canopylabs/orpheus-v1-english"
        )
        let arabic = SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: .groq,
            modelID: "canopylabs/orpheus-arabic-saudi"
        )

        XCTAssertEqual(english.voices, ["autumn", "diana", "hannah", "austin", "daniel", "troy"])
        XCTAssertEqual(arabic.voices, ["abdullah", "fahad", "sultan", "lulwa", "noura", "aisha"])
        XCTAssertEqual(english.maxInputCharacters, 200)
        XCTAssertEqual(english.responseFormats, ["wav"])
    }

    /// Only the preset-voice model streams incrementally.
    func testMiMoStreamingIsPresetVoiceModelOnly() {
        XCTAssertEqual(
            SpeechModelCapabilityRegistry.synthesisCapabilities(
                provider: .xiaomiMiMo,
                modelID: MiMoModelIDs.ttsV25
            ).streaming?.responseFormat,
            "pcm16"
        )
        XCTAssertNil(
            SpeechModelCapabilityRegistry.synthesisCapabilities(
                provider: .xiaomiMiMo,
                modelID: MiMoModelIDs.ttsV25VoiceClone
            ).streaming
        )
    }

    func testResolvedVoiceFallsBackWhenStoredValueIsUnsupported() {
        let arabic = SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: .groq,
            modelID: "canopylabs/orpheus-arabic-saudi"
        )

        XCTAssertEqual(SpeechModelCapabilityRegistry.resolvedVoice("troy", capabilities: arabic), "abdullah")
        XCTAssertEqual(SpeechModelCapabilityRegistry.resolvedVoice("noura", capabilities: arabic), "noura")
    }

    /// Several catalogs are mixed case (`Mia`, `Zephyr`), and the wire value has to match the
    /// catalog spelling exactly — so match loosely but return the canonical entry.
    func testResolvedVoiceMatchesCaseInsensitivelyAndReturnsCanonicalSpelling() {
        let openAI = SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: .openai,
            modelID: "gpt-4o-mini-tts"
        )
        XCTAssertEqual(SpeechModelCapabilityRegistry.resolvedVoice("Alloy", capabilities: openAI), "alloy")

        let miMo = SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: .xiaomiMiMo,
            modelID: MiMoModelIDs.ttsV25
        )
        XCTAssertEqual(SpeechModelCapabilityRegistry.resolvedVoice("mia", capabilities: miMo), "Mia")
    }

    /// The dated snapshots reject `instructions` and `stream_format: "sse"` just like the
    /// bare `tts-1` IDs.
    func testVersionedLegacyOpenAITTSSnapshotsAreTreatedAsLegacy() {
        for model in ["tts-1-1106", "tts-1-hd-1106"] {
            let capabilities = SpeechModelCapabilityRegistry.synthesisCapabilities(
                provider: .openai,
                modelID: model
            )
            XCTAssertFalse(capabilities.supportsInstructions, model)
            XCTAssertNil(capabilities.streaming, model)
        }
    }

    /// Mistral's `pcm` is float32 LE at an undocumented rate, which the shared 16-bit
    /// normalizer would mis-frame.
    func testMistralFormatsExcludeRawPCM() {
        XCTAssertFalse(SpeechModelCapabilityRegistry.mistralResponseFormats.contains("pcm"))
        XCTAssertEqual(SpeechModelCapabilityRegistry.mistralResponseFormats, ["mp3", "wav", "flac"])
    }

    func testResolvedResponseFormatClampsToSupportedValues() {
        XCTAssertEqual(
            SpeechModelCapabilityRegistry.resolvedResponseFormat(
                "srt",
                supported: ["json"],
                fallback: "json"
            ),
            "json"
        )
        XCTAssertEqual(
            SpeechModelCapabilityRegistry.resolvedResponseFormat(
                "VERBOSE_JSON",
                supported: ["json", "verbose_json"],
                fallback: "json"
            ),
            "verbose_json"
        )
        XCTAssertNil(
            SpeechModelCapabilityRegistry.resolvedResponseFormat(
                "json",
                supported: [],
                fallback: "json"
            )
        )
    }

    /// Ogg-wrapped Opus is not decodable by AVFoundation, so it must never reach the picker.
    func testPlayableFormatCatalogsExcludeOpus() {
        XCTAssertFalse(SpeechModelCapabilityRegistry.openAIResponseFormats.contains("opus"))
        XCTAssertFalse(SpeechModelCapabilityRegistry.mistralResponseFormats.contains("opus"))
        XCTAssertFalse(SpeechModelCapabilityRegistry.elevenLabsOutputFormats.contains { $0.hasPrefix("opus") })
        XCTAssertTrue(SpeechModelCapabilityRegistry.elevenLabsOutputFormats.contains("wav_44100"))
    }
}
