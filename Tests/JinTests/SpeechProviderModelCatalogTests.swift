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
                SpeechProviderModelChoice(id: "whisper-large-v3-turbo"),
                SpeechProviderModelChoice(id: "distil-whisper-large-v3-en"),
                SpeechProviderModelChoice(id: "llama-3.3-70b-versatile")
            ]
        )
        XCTAssertEqual(groqModels.map(\.id), ["distil-whisper-large-v3-en", "whisper-large-v3-turbo"])

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
}
