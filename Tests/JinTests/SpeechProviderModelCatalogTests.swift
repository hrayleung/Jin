import XCTest
@testable import Jin

final class SpeechProviderModelCatalogTests: XCTestCase {
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
            selectedModelID: "custom-audio-model"
        )

        XCTAssertEqual(models.map(\.id), ["custom-audio-model", "gpt-4o-mini-tts"])
    }

    func testDefaultSpeechChoicesProvidePickerFallbacks() {
        XCTAssertEqual(
            SpeechProviderModelCatalog.defaultSpeechToTextChoices(for: .openai).map(\.id),
            ["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "gpt-4o-transcribe-diarize", "whisper-1"]
        )
        XCTAssertEqual(
            SpeechProviderModelCatalog.defaultSpeechToTextChoices(for: .groq).map(\.id),
            ["whisper-large-v3-turbo", "whisper-large-v3"]
        )
        XCTAssertEqual(
            SpeechProviderModelCatalog.defaultSpeechToTextChoices(for: .mistral).map(\.id),
            ["voxtral-mini-latest"]
        )
        XCTAssertEqual(
            SpeechProviderModelCatalog.defaultSpeechToTextChoices(for: .elevenlabs).map(\.id),
            ["scribe_v2", "scribe_v1"]
        )
    }

    func testDefaultTextToSpeechChoicesProvidePickerFallbacks() {
        XCTAssertEqual(
            SpeechProviderModelCatalog.defaultTextToSpeechChoices(for: .openai).map(\.id),
            ["gpt-4o-mini-tts", "tts-1", "tts-1-hd"]
        )
        XCTAssertEqual(
            SpeechProviderModelCatalog.defaultTextToSpeechChoices(for: .groq).map(\.id),
            ["canopylabs/orpheus-v1-english", "canopylabs/orpheus-arabic-saudi"]
        )
        XCTAssertEqual(
            SpeechProviderModelCatalog.defaultTextToSpeechChoices(for: .elevenlabs).map(\.id),
            [
                "eleven_multilingual_v2",
                "eleven_flash_v2_5",
                "eleven_flash_v2",
                "eleven_turbo_v2_5",
                "eleven_turbo_v2",
                "eleven_v3"
            ]
        )
    }
}
