import XCTest
@testable import Jin

final class SpeechProviderModelCatalogTests: XCTestCase {
    func testModelChoiceTrimsIDAndFallsBackToIDForBlankName() {
        let choice = SpeechProviderModelChoice(id: "  custom-model\n", name: " \t ")

        XCTAssertEqual(choice.id, "custom-model")
        XCTAssertEqual(choice.name, "custom-model")
    }

    func testOpenAITextToSpeechChoicesFilterToSupportedSpeechModels() {
        let models = SpeechProviderModelCatalog.textToSpeechChoices(
            for: .openai,
            availableModels: [
                SpeechProviderModelChoice(id: "gpt-4o-mini-tts", name: "GPT-4o mini TTS"),
                SpeechProviderModelChoice(id: "tts-1"),
                SpeechProviderModelChoice(id: "gpt-4o-audio-preview"),
                SpeechProviderModelChoice(id: "whisper-1")
            ]
        )

        XCTAssertEqual(models.map(\.id), ["gpt-4o-mini-tts", "tts-1"])
    }

    func testOpenAISpeechToTextChoicesKeepTranscribeFamilies() {
        let models = SpeechProviderModelCatalog.speechToTextChoices(
            for: .openai,
            availableModels: [
                SpeechProviderModelChoice(id: "gpt-4o-mini-transcribe"),
                SpeechProviderModelChoice(id: "gpt-4o-transcribe-diarize"),
                SpeechProviderModelChoice(id: "whisper-1"),
                SpeechProviderModelChoice(id: "gpt-4o-mini-tts")
            ]
        )

        XCTAssertEqual(models.map(\.id), ["gpt-4o-mini-transcribe", "gpt-4o-transcribe-diarize", "whisper-1"])
    }

    func testGroqAndElevenLabsSpeechChoicesExcludeNonSpeechAndRealtimeModels() {
        let groqModels = SpeechProviderModelCatalog.speechToTextChoices(
            for: .groq,
            availableModels: [
                SpeechProviderModelChoice(id: "whisper-large-v3"),
                SpeechProviderModelChoice(id: "whisper-large-v3-turbo"),
                SpeechProviderModelChoice(id: "distil-whisper-large-v3-en"),
                SpeechProviderModelChoice(id: "llama-3.3-70b-versatile")
            ]
        )
        XCTAssertEqual(groqModels.map(\.id), ["whisper-large-v3", "whisper-large-v3-turbo"])

        let elevenLabsModels = SpeechProviderModelCatalog.speechToTextChoices(
            for: .elevenlabs,
            availableModels: [
                SpeechProviderModelChoice(id: "scribe_v2"),
                SpeechProviderModelChoice(id: "scribe_v1"),
                SpeechProviderModelChoice(id: "scribe_realtime_v1")
            ]
        )
        XCTAssertEqual(elevenLabsModels.map(\.id), ["scribe_v1", "scribe_v2"])
    }

    func testGroqTextToSpeechChoicesUseExactSupportedModelIDs() {
        let models = SpeechProviderModelCatalog.textToSpeechChoices(
            for: .groq,
            availableModels: [
                SpeechProviderModelChoice(id: "canopylabs/orpheus-v1-english", name: "Orpheus English"),
                SpeechProviderModelChoice(id: "canopylabs/orpheus-arabic-saudi", name: "Orpheus Arabic"),
                SpeechProviderModelChoice(id: "canopylabs/orpheus-preview", name: "Preview"),
                SpeechProviderModelChoice(id: "gpt-4o-mini-tts", name: "GPT-4o mini TTS")
            ]
        )

        XCTAssertEqual(
            models.map(\.id),
            ["canopylabs/orpheus-arabic-saudi", "canopylabs/orpheus-v1-english"]
        )
    }

    func testMiMoTextToSpeechChoicesUseExactTTSModelIDs() {
        let models = SpeechProviderModelCatalog.textToSpeechChoices(
            for: .xiaomiMiMo,
            availableModels: [
                SpeechProviderModelChoice(id: "mimo-v2.5", name: "MiMo V2.5"),
                SpeechProviderModelChoice(id: "mimo-v2.5-tts", name: "MiMo V2.5 TTS"),
                SpeechProviderModelChoice(id: "mimo-v2.5-pro", name: "MiMo V2.5 Pro"),
                SpeechProviderModelChoice(id: "mimo-v2.5-tts-voicedesign", name: "MiMo V2.5 VoiceDesign"),
                SpeechProviderModelChoice(id: "mimo-v2.5-tts-voiceclone", name: "MiMo V2.5 VoiceClone"),
                SpeechProviderModelChoice(id: "mimo-v2-tts", name: "MiMo V2 TTS")
            ]
        )

        // The V2 series went offline on 2026-06-30.
        XCTAssertEqual(
            models.map(\.id),
            [
                "mimo-v2.5-tts",
                "mimo-v2.5-tts-voiceclone",
                "mimo-v2.5-tts-voicedesign"
            ]
        )
    }

    func testMistralSpeechToTextChoicesStayConservative() {
        let models = SpeechProviderModelCatalog.speechToTextChoices(
            for: .mistral,
            availableModels: [
                SpeechProviderModelChoice(id: "voxtral-mini-latest"),
                SpeechProviderModelChoice(id: "voxtral-mini-transcribe-2509"),
                SpeechProviderModelChoice(id: "voxtral-mini-transcribe-realtime-2509"),
                SpeechProviderModelChoice(id: "mistral-medium-latest")
            ]
        )

        XCTAssertEqual(models.map(\.id), ["voxtral-mini-latest", "voxtral-mini-transcribe-2509"])
    }

    func testPresentingChoicesPrependsCurrentSelectionWhenMissing() {
        let models = SpeechProviderModelCatalog.presentingChoices(
            [
                SpeechProviderModelChoice(id: "gpt-4o-mini-tts", name: "GPT-4o mini TTS")
            ],
            selectedModelID: " custom-audio-model\n"
        )

        XCTAssertEqual(models.map(\.id), ["custom-audio-model", "gpt-4o-mini-tts"])
    }

    func testPresentingChoicesIgnoreBlankSelection() {
        let choices = [
            SpeechProviderModelChoice(id: "gpt-4o-mini-tts", name: "GPT-4o mini TTS")
        ]

        XCTAssertEqual(
            SpeechProviderModelCatalog.presentingChoices(choices, selectedModelID: " \n\t "),
            choices
        )
    }

    func testOpenRouterTextToSpeechModelNormalizationMapsLegacyAliasesToExactIDs() {
        // OpenRouter no longer serves any OpenAI TTS model — both the bare slug and the
        // dated snapshot 404.
        XCTAssertEqual(
            SpeechProviderModelCatalog.normalizedOpenRouterTextToSpeechModelID(" openai/gpt-4o-mini-tts\n"),
            SpeechProviderModelCatalog.defaultOpenRouterTextToSpeechModelID
        )
        XCTAssertEqual(
            SpeechProviderModelCatalog.normalizedOpenRouterTextToSpeechModelID("openai/gpt-4o-mini-tts-2025-12-15"),
            SpeechProviderModelCatalog.defaultOpenRouterTextToSpeechModelID
        )
        XCTAssertEqual(
            SpeechProviderModelCatalog.normalizedOpenRouterTextToSpeechModelID("GOOGLE/GEMINI-FLASH-TTS"),
            "google/gemini-3.1-flash-tts-preview"
        )
        XCTAssertEqual(
            SpeechProviderModelCatalog.normalizedOpenRouterTextToSpeechModelID("mistralai/voxtral-mini-tts"),
            "mistralai/voxtral-mini-tts-2603"
        )
        XCTAssertEqual(
            SpeechProviderModelCatalog.normalizedOpenRouterTextToSpeechModelID("custom/provider-tts"),
            "custom/provider-tts"
        )
        XCTAssertEqual(
            SpeechProviderModelCatalog.normalizedOpenRouterTextToSpeechModelID(" \n "),
            SpeechProviderModelCatalog.defaultOpenRouterTextToSpeechModelID
        )
    }

    func testDefaultSpeechChoicesProvidePickerFallbacks() {
        XCTAssertEqual(
            SpeechProviderModelCatalog.defaultSpeechToTextChoices(for: .openai).map(\.id),
            [
                "gpt-transcribe",
                "gpt-4o-transcribe-diarize",
                "whisper-1",
                "gpt-4o-transcribe",
                "gpt-4o-mini-transcribe"
            ]
        )
        XCTAssertEqual(
            SpeechProviderModelCatalog.defaultSpeechToTextChoices(for: .openRouter).map(\.id),
            [
                "openai/gpt-transcribe",
                "openai/whisper-large-v3-turbo",
                "openai/whisper-large-v3",
                "x-ai/grok-stt-1.0",
                "deepgram/nova-3",
                "microsoft/mai-transcribe-1.5",
                "mistralai/voxtral-mini-transcribe",
                "qwen/qwen3-asr-flash-2026-02-10",
                "nvidia/parakeet-tdt-0.6b-v3",
                "google/chirp-3"
            ]
        )
        XCTAssertEqual(
            SpeechProviderModelCatalog.defaultSpeechToTextChoices(for: .groq).map(\.id),
            ["whisper-large-v3-turbo", "whisper-large-v3"]
        )
        XCTAssertEqual(
            SpeechProviderModelCatalog.defaultSpeechToTextChoices(for: .mistral).map(\.id),
            ["voxtral-mini-transcribe-2602", "voxtral-mini-latest"]
        )
        // The convert endpoint's `model_id` enum is scribe_v2 only.
        XCTAssertEqual(
            SpeechProviderModelCatalog.defaultSpeechToTextChoices(for: .elevenlabs).map(\.id),
            ["scribe_v2"]
        )
    }

    func testDefaultTextToSpeechChoicesProvidePickerFallbacks() {
        XCTAssertEqual(
            SpeechProviderModelCatalog.defaultTextToSpeechChoices(for: .openai).map(\.id),
            ["gpt-4o-mini-tts", "gpt-4o-mini-tts-2025-12-15", "tts-1", "tts-1-hd"]
        )
        XCTAssertEqual(
            SpeechProviderModelCatalog.defaultTextToSpeechChoices(for: .openRouter).map(\.id),
            [
                "google/gemini-3.1-flash-tts-preview",
                "microsoft/mai-voice-2",
                "microsoft/mai-voice-2-flash",
                "mistralai/voxtral-mini-tts-2603",
                "deepgram/aura-2",
                "minimax/speech-2.8-hd",
                "minimax/speech-2.8-turbo",
                "x-ai/grok-voice-tts-1.0",
                "fish-audio/s2.1-pro",
                "qwen/qwen-audio-3.0-tts-flash",
                "hexgrad/kokoro-82m"
            ]
        )
        XCTAssertEqual(
            SpeechProviderModelCatalog.defaultTextToSpeechChoices(for: .groq).map(\.id),
            ["canopylabs/orpheus-v1-english", "canopylabs/orpheus-arabic-saudi"]
        )
        XCTAssertEqual(
            SpeechProviderModelCatalog.defaultTextToSpeechChoices(for: .mistral).map(\.id),
            ["voxtral-mini-tts-2603"]
        )
        XCTAssertEqual(
            SpeechProviderModelCatalog.defaultTextToSpeechChoices(for: .xiaomiMiMo).map(\.id),
            ["mimo-v2.5-tts", "mimo-v2.5-tts-voicedesign", "mimo-v2.5-tts-voiceclone"]
        )
        // The turbo models are deprecated in favour of the flash pair.
        XCTAssertEqual(
            SpeechProviderModelCatalog.defaultTextToSpeechChoices(for: .elevenlabs).map(\.id),
            [
                "eleven_v3",
                "eleven_multilingual_v2",
                "eleven_flash_v2_5",
                "eleven_flash_v2",
                "eleven_ttv_v3"
            ]
        )
    }

    func testOpenAISpeechToTextChoicesIncludeGPTTranscribeAndExcludeRealtimeOnlyModels() {
        let models = SpeechProviderModelCatalog.speechToTextChoices(
            for: .openai,
            availableModels: [
                SpeechProviderModelChoice(id: "gpt-transcribe"),
                SpeechProviderModelChoice(id: "gpt-live-transcribe"),
                SpeechProviderModelChoice(id: "gpt-realtime-whisper"),
                SpeechProviderModelChoice(id: "whisper-1"),
                SpeechProviderModelChoice(id: "gpt-4o")
            ]
        )

        XCTAssertEqual(models.map(\.id), ["gpt-transcribe", "whisper-1"])
    }
}
