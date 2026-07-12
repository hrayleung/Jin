import XCTest
@testable import Jin

final class XAIVideoModeResolutionTests: XCTestCase {
    func testAutoWithMultipleImagesUsesReferenceToVideo() throws {
        let resolved = try XAIVideoModeResolution.resolve(
            modelID: "grok-imagine-video",
            controls: nil,
            imageURLs: [
                "https://example.com/a.png",
                "https://example.com/b.png",
            ],
            videoURL: nil
        )

        XCTAssertEqual(resolved.mode, .referenceToVideo)
        XCTAssertNil(resolved.imageURL)
        XCTAssertEqual(resolved.referenceImageURLs.count, 2)
        XCTAssertNil(resolved.videoURL)
    }

    func testAutoWithSingleImageUsesImageToVideo() throws {
        let resolved = try XAIVideoModeResolution.resolve(
            modelID: "grok-imagine-video",
            controls: nil,
            imageURLs: ["https://example.com/a.png"],
            videoURL: nil
        )

        XCTAssertEqual(resolved.mode, .imageToVideo)
        XCTAssertEqual(resolved.imageURL, "https://example.com/a.png")
        XCTAssertTrue(resolved.referenceImageURLs.isEmpty)
    }

    func testAutoWithVideoPrefersEdit() throws {
        let resolved = try XAIVideoModeResolution.resolve(
            modelID: "grok-imagine-video",
            controls: nil,
            imageURLs: ["https://example.com/a.png"],
            videoURL: "https://example.com/clip.mp4"
        )

        XCTAssertEqual(resolved.mode, .editVideo)
        XCTAssertEqual(resolved.videoURL, "https://example.com/clip.mp4")
        XCTAssertNil(resolved.imageURL)
        XCTAssertTrue(resolved.referenceImageURLs.isEmpty)
    }

    func testExplicitExtendUsesExtensionMode() throws {
        let resolved = try XAIVideoModeResolution.resolve(
            modelID: "grok-imagine-video",
            controls: XAIVideoGenerationControls(mode: .extendVideo),
            imageURLs: [],
            videoURL: "https://example.com/clip.mp4"
        )

        XCTAssertEqual(resolved.mode, .extendVideo)
        XCTAssertEqual(resolved.videoURL, "https://example.com/clip.mp4")
    }

    func testExplicitReferenceRequiresImages() {
        XCTAssertThrowsError(
            try XAIVideoModeResolution.resolve(
                modelID: "grok-imagine-video",
                controls: XAIVideoGenerationControls(mode: .referenceToVideo),
                imageURLs: [],
                videoURL: nil
            )
        )
    }

    func testTextToVideoRejectedOn15Models() {
        XCTAssertThrowsError(
            try XAIVideoModeResolution.resolve(
                modelID: "grok-imagine-video-1.5",
                controls: XAIVideoGenerationControls(mode: .textToVideo),
                imageURLs: [],
                videoURL: nil
            )
        )
    }

    func testReferenceRejectedOn15Models() {
        XCTAssertThrowsError(
            try XAIVideoModeResolution.resolve(
                modelID: "grok-imagine-video-1.5",
                controls: XAIVideoGenerationControls(mode: .referenceToVideo),
                imageURLs: ["https://example.com/a.png", "https://example.com/b.png"],
                videoURL: nil
            )
        )
    }

    func testExtendRejectedOn15Models() {
        XCTAssertThrowsError(
            try XAIVideoModeResolution.resolve(
                modelID: "grok-imagine-video-1.5",
                controls: XAIVideoGenerationControls(mode: .extendVideo),
                imageURLs: [],
                videoURL: "https://example.com/clip.mp4"
            )
        )
    }

    func testImage15StillSupportsImageToVideo() throws {
        let resolved = try XAIVideoModeResolution.resolve(
            modelID: "grok-imagine-video-1.5",
            controls: nil,
            imageURLs: ["https://example.com/a.png"],
            videoURL: nil
        )
        XCTAssertEqual(resolved.mode, .imageToVideo)
    }

    func testAvailableModesForBaseAnd15Models() {
        let base = XAIModelSupport.availableVideoModes(for: "grok-imagine-video")
        XCTAssertTrue(base.contains(.textToVideo))
        XCTAssertTrue(base.contains(.referenceToVideo))
        XCTAssertTrue(base.contains(.editVideo))
        XCTAssertTrue(base.contains(.extendVideo))

        let v15 = XAIModelSupport.availableVideoModes(for: "grok-imagine-video-1.5")
        XCTAssertFalse(v15.contains(.textToVideo))
        XCTAssertFalse(v15.contains(.referenceToVideo))
        XCTAssertFalse(v15.contains(.editVideo))
        XCTAssertFalse(v15.contains(.extendVideo))
        XCTAssertTrue(v15.contains(.imageToVideo))
        XCTAssertTrue(v15.contains(.auto))
    }
}
