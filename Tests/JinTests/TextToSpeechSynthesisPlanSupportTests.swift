import XCTest
@testable import Jin

final class TextToSpeechSynthesisPlanSupportTests: XCTestCase {
    func testOpenAIPlanNormalizesFormatChunksTextAndPreservesNonBlankInstructions() throws {
        let plan = try TextToSpeechSynthesisPlanSupport.plan(
            text: "  hello\nworld  ",
            provider: .openai,
            model: "gpt-4o-mini-tts",
            responseFormat: " PCM ",
            instructions: " speak clearly "
        )

        XCTAssertEqual(plan.responseFormat, "pcm")
        XCTAssertEqual(plan.chunks, ["hello\nworld"])
        XCTAssertEqual(plan.instructions, " speak clearly ")
        XCTAssertNil(plan.streaming)
    }

    func testOpenAIPlanDropsBlankInstructions() throws {
        let plan = try TextToSpeechSynthesisPlanSupport.plan(
            text: "hello",
            provider: .openai,
            model: "gpt-4o-mini-tts",
            responseFormat: "mp3",
            instructions: " \n\t "
        )

        XCTAssertNil(plan.instructions)
    }

    func testOpenAIPlanRejectsUnsupportedPlaybackFormat() {
        XCTAssertThrowsError(
            try TextToSpeechSynthesisPlanSupport.plan(
                text: "hello",
                provider: .openai,
                model: "gpt-4o-mini-tts",
                responseFormat: " opus ",
                instructions: nil
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Invalid request: OpenAI format “opus” is not playable in Jin. Choose mp3, wav, aac, flac, or pcm."
            )
        }
    }

    /// `instructions` and `stream_format` are both rejected by the tts-1 generation.
    func testLegacyOpenAIModelDropsInstructionsAndCannotStream() throws {
        let plan = try TextToSpeechSynthesisPlanSupport.plan(
            text: "hello",
            provider: .openai,
            model: "tts-1-hd",
            responseFormat: "mp3",
            instructions: "speak calmly",
            streamingEnabled: true
        )

        XCTAssertNil(plan.instructions)
        XCTAssertNil(plan.streaming)
        XCTAssertEqual(plan.responseFormat, "mp3")
    }

    func testStreamingOverridesResponseFormatWithPCM() throws {
        let plan = try TextToSpeechSynthesisPlanSupport.plan(
            text: "hello",
            provider: .openai,
            model: "gpt-4o-mini-tts",
            responseFormat: "mp3",
            streamingEnabled: true
        )

        XCTAssertEqual(plan.responseFormat, "pcm")
        XCTAssertEqual(plan.streaming?.sampleRate, 24_000)
    }

    func testGroqPlanUsesShortChunkLimit() throws {
        let plan = try TextToSpeechSynthesisPlanSupport.plan(
            text: String(repeating: "a", count: 201),
            provider: .groq,
            model: "canopylabs/orpheus-v1-english",
            responseFormat: "wav"
        )

        XCTAssertEqual(plan.chunks.map(\.count), [200, 1])
        XCTAssertNil(plan.streaming)
    }

    /// Eleven v3 caps input at 5,000 characters where multilingual v2 allows 10,000.
    func testElevenLabsChunkLimitFollowsSelectedModel() throws {
        let v3Plan = try TextToSpeechSynthesisPlanSupport.plan(
            text: String(repeating: "a", count: 5001),
            provider: .elevenlabs,
            model: "eleven_v3",
            responseFormat: "mp3_44100_128"
        )
        XCTAssertEqual(v3Plan.chunks.map(\.count), [5000, 1])

        let multilingualPlan = try TextToSpeechSynthesisPlanSupport.plan(
            text: String(repeating: "a", count: 10001),
            provider: .elevenlabs,
            model: "eleven_multilingual_v2",
            responseFormat: "mp3_44100_128"
        )
        XCTAssertEqual(multilingualPlan.chunks.map(\.count), [10000, 1])
    }

    func testElevenLabsStreamingRequestsPCM() throws {
        let plan = try TextToSpeechSynthesisPlanSupport.plan(
            text: "hello",
            provider: .elevenlabs,
            model: "eleven_v3",
            responseFormat: "mp3_44100_128",
            streamingEnabled: true
        )

        XCTAssertEqual(plan.responseFormat, "pcm_24000")
        XCTAssertEqual(plan.streaming?.sampleRate, 24_000)
    }

    func testMiMoPlanNormalizesFormatAndChunksText() throws {
        let plan = try TextToSpeechSynthesisPlanSupport.plan(
            text: "  hello  ",
            provider: .xiaomiMiMo,
            model: MiMoModelIDs.ttsV25,
            responseFormat: " PCM16 "
        )

        XCTAssertEqual(plan.responseFormat, "pcm16")
        XCTAssertEqual(plan.chunks, ["hello"])
    }

    /// The V2.5 series dropped mp3 and raw pcm.
    func testMiMoPlanRejectsUnsupportedPlaybackFormat() {
        XCTAssertThrowsError(
            try TextToSpeechSynthesisPlanSupport.plan(
                text: "hello",
                provider: .xiaomiMiMo,
                model: MiMoModelIDs.ttsV25,
                responseFormat: "mp3"
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Invalid request: Xiaomi MiMo format “mp3” is not playable in Jin. Choose wav or pcm16."
            )
        }
    }

    /// VoiceDesign and VoiceClone deliver a single frame after inference.
    func testMiMoVoiceDesignCannotStream() throws {
        let plan = try TextToSpeechSynthesisPlanSupport.plan(
            text: "hello",
            provider: .xiaomiMiMo,
            model: MiMoModelIDs.ttsV25VoiceDesign,
            responseFormat: "wav",
            streamingEnabled: true
        )

        XCTAssertNil(plan.streaming)
        XCTAssertEqual(plan.responseFormat, "wav")
    }

    func testOpenRouterAndMistralNeverStream() throws {
        let openRouterPlan = try TextToSpeechSynthesisPlanSupport.plan(
            text: "hello",
            provider: .openRouter,
            model: "google/gemini-3.1-flash-tts-preview",
            responseFormat: "mp3",
            streamingEnabled: true
        )
        XCTAssertNil(openRouterPlan.streaming)

        let mistralPlan = try TextToSpeechSynthesisPlanSupport.plan(
            text: "hello",
            provider: .mistral,
            model: "voxtral-mini-tts-2603",
            responseFormat: "mp3",
            streamingEnabled: true
        )
        XCTAssertNil(mistralPlan.streaming)
    }
}
