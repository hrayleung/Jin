import XCTest
@testable import Jin

final class TextToSpeechSynthesisPlanSupportTests: XCTestCase {
    func testOpenAIPlanNormalizesFormatChunksTextAndPreservesNonBlankInstructions() throws {
        let plan = try TextToSpeechSynthesisPlanSupport.openAIPlan(
            text: "  hello\nworld  ",
            responseFormat: " PCM ",
            instructions: " speak clearly "
        )

        XCTAssertEqual(plan.responseFormat, "pcm")
        XCTAssertEqual(plan.chunks, ["hello\nworld"])
        XCTAssertEqual(plan.instructions, " speak clearly ")
    }

    func testOpenAIPlanDropsBlankInstructions() throws {
        let plan = try TextToSpeechSynthesisPlanSupport.openAIPlan(
            text: "hello",
            responseFormat: "mp3",
            instructions: " \n\t "
        )

        XCTAssertNil(plan.instructions)
    }

    func testOpenAIPlanRejectsUnsupportedPlaybackFormat() {
        XCTAssertThrowsError(
            try TextToSpeechSynthesisPlanSupport.openAIPlan(
                text: "hello",
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

    func testGroqPlanUsesShortChunkLimit() {
        let plan = TextToSpeechSynthesisPlanSupport.groqPlan(
            text: String(repeating: "a", count: 201)
        )

        XCTAssertEqual(plan.chunks.map(\.count), [200, 1])
    }

    func testElevenLabsPlanUsesLargeChunkLimit() {
        let plan = TextToSpeechSynthesisPlanSupport.elevenLabsPlan(
            text: String(repeating: "a", count: 6001)
        )

        XCTAssertEqual(plan.chunks.map(\.count), [6000, 1])
    }

    func testMiMoPlanNormalizesFormatAndChunksText() throws {
        let plan = try TextToSpeechSynthesisPlanSupport.miMoPlan(
            text: "  hello  ",
            responseFormat: " PCM16 "
        )

        XCTAssertEqual(plan.responseFormat, "pcm16")
        XCTAssertEqual(plan.chunks, ["hello"])
    }

    func testMiMoPlanRejectsUnsupportedPlaybackFormat() {
        XCTAssertThrowsError(
            try TextToSpeechSynthesisPlanSupport.miMoPlan(
                text: "hello",
                responseFormat: "aac"
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Invalid request: MiMo format “aac” is not playable in Jin. Choose wav, mp3, pcm, or pcm16."
            )
        }
    }
}
