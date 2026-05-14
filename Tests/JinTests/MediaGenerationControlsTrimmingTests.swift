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

    func testGoogleVideoVeo31Supports4KResolution() {
        let resolutions = GoogleVideoGenerationCore.supportedResolutions(
            for: "veo-3.1-generate-preview"
        )
        XCTAssertTrue(resolutions.contains(.res4k))

        let parameters = GoogleVideoGenerationCore.buildGeminiParameters(
            controls: GoogleVideoGenerationControls(resolution: .res4k),
            modelID: "veo-3.1-generate-preview"
        )
        XCTAssertEqual(parameters["resolution"] as? String, "4k")
    }

    func testGoogleVideoVeo30DoesNotOffer4KResolution() {
        let resolutions = GoogleVideoGenerationCore.supportedResolutions(
            for: "veo-3.0-generate-001"
        )
        XCTAssertEqual(resolutions, [.res720p, .res1080p])
    }

    func testGoogleMapsControlsTreatBlankLanguageCodeAsEmpty() {
        XCTAssertTrue(GoogleMapsControls(languageCode: " \n\t ").isEmpty)
        XCTAssertFalse(GoogleMapsControls(languageCode: " en_US ").isEmpty)
    }
}
