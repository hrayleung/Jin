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

    func testGeminiOmniFlashStripsUndocumentedVeoParameters() throws {
        XCTAssertTrue(GoogleVideoGenerationCore.isOmniFlashModel("gemini-omni-1.1-flash"))
        XCTAssertFalse(GoogleVideoGenerationCore.isOmniFlashModel("gemini-omni-1.1-flash-custom"))
        XCTAssertFalse(GoogleVideoGenerationCore.isVideoGenerationModel("gemini-omni-1.1-flash"))
        XCTAssertTrue(GoogleVideoGenerationCore.isGeminiAPIVideoGenerationModel("gemini-omni-1.1-flash"))

        XCTAssertEqual(
            GoogleVideoGenerationCore.supportedResolutions(for: "gemini-omni-1.1-flash"),
            [.res360p, .res720p, .res1080p, .res4k]
        )
        XCTAssertEqual(
            GoogleVideoGenerationCore.supportedAspectRatios(for: "gemini-omni-1.1-flash"),
            [.ratio16x9, .ratio9x16]
        )
        XCTAssertFalse(GoogleVideoGenerationCore.supportsDurationControl("gemini-omni-1.1-flash"))
        XCTAssertFalse(GoogleVideoGenerationCore.supportsPersonGenerationControl("gemini-omni-1.1-flash"))
        XCTAssertTrue(GoogleVideoGenerationCore.omniUsesURIDelivery(resolution: .res1080p))
        XCTAssertFalse(GoogleVideoGenerationCore.omniUsesURIDelivery(resolution: .res720p))

        let sanitized = GoogleVideoGenerationCore.sanitizedGoogleVideoControls(
            GoogleVideoGenerationControls(
                durationSeconds: 8,
                aspectRatio: .ratio1x1,
                resolution: .res360p,
                negativePrompt: "blurry",
                generateAudio: true,
                personGeneration: .allowAll,
                seed: 3
            ),
            modelID: "gemini-omni-1.1-flash"
        )
        XCTAssertEqual(sanitized?.resolution, .res360p)
        XCTAssertNil(sanitized?.durationSeconds)
        XCTAssertNil(sanitized?.aspectRatio)
        XCTAssertNil(sanitized?.negativePrompt)
        XCTAssertNil(sanitized?.generateAudio)
        XCTAssertNil(sanitized?.personGeneration)
        XCTAssertNil(sanitized?.seed)

        let body = GeminiOmniVideoRequestSupport.makeBody(
            modelID: "gemini-omni-1.1-flash",
            prompt: "A marble rolling",
            images: [],
            videos: [],
            controls: sanitized
        )
        let format = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "video")
        XCTAssertEqual(format["resolution"] as? String, "360p")
        XCTAssertNil(format["aspect_ratio"])
        XCTAssertNil(format["delivery"])
        XCTAssertNil(body["instances"])
    }

    func testGeminiOmniFileIDParsing() {
        XCTAssertEqual(
            GeminiOmniVideoRequestSupport.fileID(
                fromURI: "https://generativelanguage.googleapis.com/v1beta/files/abc-123:download?alt=media"
            ),
            "abc-123"
        )
        XCTAssertEqual(
            GeminiOmniVideoRequestSupport.fileID(fromURI: "files/xyz"),
            "xyz"
        )
        XCTAssertNil(GeminiOmniVideoRequestSupport.fileID(fromURI: ""))
    }

    func testGeminiOmniOnlyTreatsTrustedHostsAsGeminiFiles() {
        let apiBase = "https://generativelanguage.googleapis.com/v1beta"
        XCTAssertEqual(
            GeminiOmniVideoRequestSupport.geminiFileID(fromURI: "files/xyz", apiBaseURL: apiBase),
            "xyz"
        )
        XCTAssertEqual(
            GeminiOmniVideoRequestSupport.geminiFileID(
                fromURI: "https://generativelanguage.googleapis.com/v1beta/files/abc-123:download?alt=media",
                apiBaseURL: apiBase
            ),
            "abc-123"
        )
        XCTAssertNil(
            GeminiOmniVideoRequestSupport.geminiFileID(
                fromURI: "https://evil.example/files/abc-123",
                apiBaseURL: apiBase
            )
        )
        XCTAssertFalse(
            GeminiOmniVideoRequestSupport.isTrustedGeminiAPIURL(
                URL(string: "https://evil.example/files/abc-123")!,
                apiBaseURL: apiBase
            )
        )
        XCTAssertFalse(
            RemoteMediaURLPolicy.isAllowedForAutomaticFetch(URL(string: "http://127.0.0.1/video.mp4")!)
        )
    }

    func testGoogleMapsControlsTreatBlankLanguageCodeAsEmpty() {
        XCTAssertTrue(GoogleMapsControls(languageCode: " \n\t ").isEmpty)
        XCTAssertFalse(GoogleMapsControls(languageCode: " en_US ").isEmpty)
    }
}
