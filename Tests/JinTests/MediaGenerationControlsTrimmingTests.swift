import XCTest
@testable import Jin

final class MediaGenerationControlsTrimmingTests: XCTestCase {
    func testOpenAIImageControlsTreatBlankUserAsEmpty() {
        XCTAssertTrue(OpenAIImageGenerationControls(user: " \n\t ").isEmpty)
        XCTAssertFalse(OpenAIImageGenerationControls(user: " user-123 ").isEmpty)
    }

    func testOpenAIImageSizeTrimsAndLowercasesRawValue() {
        XCTAssertEqual(OpenAIImageSize(rawValue: " 2048X1152\n").rawValue, "2048x1152")
    }

    func testXAIImageControlsTreatBlankUserAsEmpty() {
        XCTAssertTrue(XAIImageGenerationControls(user: " \n\t ").isEmpty)
        XCTAssertFalse(XAIImageGenerationControls(user: " user-123 ").isEmpty)
    }

    func testGoogleVideoControlsTreatBlankNegativePromptAsEmpty() {
        XCTAssertTrue(GoogleVideoGenerationControls(negativePrompt: " \n\t ").isEmpty)
        XCTAssertFalse(GoogleVideoGenerationControls(negativePrompt: " low contrast ").isEmpty)
    }

    func testGoogleVideoParametersTrimNegativePrompt() {
        let controls = GoogleVideoGenerationControls(
            durationSeconds: 8,
            negativePrompt: " low contrast ",
            generateAudio: true
        )

        let gemini = GoogleVideoGenerationCore.buildGeminiParameters(
            controls: controls,
            modelID: "veo-3.0-generate-preview"
        )
        XCTAssertEqual(gemini["negativePrompt"] as? String, "low contrast")
        XCTAssertNil(gemini["generateAudio"])

        let vertex = GoogleVideoGenerationCore.buildVertexParameters(
            controls: controls,
            modelID: "veo-3.0-generate-preview"
        )
        XCTAssertEqual(vertex["negativePrompt"] as? String, "low contrast")
        XCTAssertEqual(vertex["generateAudio"] as? Bool, true)
    }

    func testGoogleMapsControlsTreatBlankLanguageCodeAsEmpty() {
        XCTAssertTrue(GoogleMapsControls(languageCode: " \n\t ").isEmpty)
        XCTAssertFalse(GoogleMapsControls(languageCode: " en_US ").isEmpty)
    }
}
