import XCTest
@testable import Jin

final class XAIMediaRequestSupportTests: XCTestCase {
    func testImageGenerationComponentsClampCountAndMapDeprecatedSize() {
        let components = XAIMediaRequestSupport.imageRequestComponents(
            modelID: "grok-imagine-image",
            prompt: "A city skyline",
            imageURL: nil,
            controls: XAIImageGenerationControls(
                count: 12,
                size: .size1536x1024,
                user: " tester "
            )
        )

        XCTAssertEqual(components.endpoint, "images/generations")
        XCTAssertEqual(components.body["model"] as? String, "grok-imagine-image")
        XCTAssertEqual(components.body["prompt"] as? String, "A city skyline")
        XCTAssertEqual(components.body["n"] as? Int, 10)
        XCTAssertEqual(components.body["aspect_ratio"] as? String, "3:2")
        XCTAssertEqual(components.body["response_format"] as? String, "b64_json")
        XCTAssertEqual(components.body["user"] as? String, "tester")
    }

    func testImageEditComponentsIncludeImageAndOmitAspectRatio() throws {
        let components = XAIMediaRequestSupport.imageRequestComponents(
            modelID: "grok-imagine-image",
            prompt: "Edit this",
            imageURL: "https://example.com/input.png",
            controls: XAIImageGenerationControls(aspectRatio: .ratio16x9)
        )

        XCTAssertEqual(components.endpoint, "images/edits")
        XCTAssertNil(components.body["aspect_ratio"])

        let image = try XCTUnwrap(components.body["image"] as? [String: Any])
        XCTAssertEqual(image["url"] as? String, "https://example.com/input.png")
    }

    func testImageGenerationComponentsOmitResolutionForUnsupportedImageModel() {
        let components = XAIMediaRequestSupport.imageRequestComponents(
            modelID: "grok-imagine-image",
            prompt: "A city skyline",
            imageURL: nil,
            controls: XAIImageGenerationControls(resolution: .res2k)
        )

        XCTAssertNil(components.body["resolution"])
    }

    func testVideoGenerationComponentsClampDurationAndIncludeSupportedControls() {
        let components = XAIMediaRequestSupport.videoRequestComponents(
            modelID: "grok-imagine-video",
            prompt: "A cat playing piano",
            imageURL: "https://example.com/input.png",
            videoURL: nil,
            controls: XAIVideoGenerationControls(
                duration: 20,
                aspectRatio: .ratio16x9,
                resolution: .res720p
            )
        )

        XCTAssertEqual(components.endpoint, "videos/generations")
        XCTAssertEqual(components.body["duration"] as? Int, 15)
        XCTAssertEqual(components.body["aspect_ratio"] as? String, "16:9")
        XCTAssertEqual(components.body["resolution"] as? String, "720p")
        XCTAssertNil(components.body["video"])
        XCTAssertEqual((components.body["image"] as? [String: Any])?["url"] as? String, "https://example.com/input.png")
    }

    func testGrokImagineVideo15PreviewUsesGenerationEndpointAndControls() {
        let components = XAIMediaRequestSupport.videoRequestComponents(
            modelID: "grok-imagine-video-1.5-preview",
            prompt: "A neon city at night",
            imageURL: "https://example.com/still.png",
            videoURL: nil,
            controls: XAIVideoGenerationControls(
                duration: 10,
                aspectRatio: .ratio9x16,
                resolution: .res720p
            )
        )

        XCTAssertEqual(components.endpoint, "videos/generations")
        XCTAssertEqual(components.body["model"] as? String, "grok-imagine-video-1.5-preview")
        XCTAssertEqual(components.body["duration"] as? Int, 10)
        XCTAssertEqual(components.body["aspect_ratio"] as? String, "9:16")
        XCTAssertEqual(components.body["resolution"] as? String, "720p")
        XCTAssertEqual((components.body["image"] as? [String: Any])?["url"] as? String, "https://example.com/still.png")
    }

    func testGrokImagineVideo15Allows1080pWithImageInput() {
        let components = XAIMediaRequestSupport.videoRequestComponents(
            modelID: "grok-imagine-video-1.5",
            prompt: "Animate this still",
            imageURL: "https://example.com/still.png",
            videoURL: nil,
            controls: XAIVideoGenerationControls(resolution: .res1080p)
        )
        XCTAssertEqual(components.body["resolution"] as? String, "1080p")
    }

    func testBaseVideoModelDrops1080pResolution() {
        let components = XAIMediaRequestSupport.videoRequestComponents(
            modelID: "grok-imagine-video",
            prompt: "A cat",
            imageURL: nil,
            videoURL: nil,
            controls: XAIVideoGenerationControls(resolution: .res1080p)
        )
        XCTAssertNil(components.body["resolution"])
    }

    func testReferenceToVideoUsesGenerationsAndReferenceImages() throws {
        let components = XAIMediaRequestSupport.videoRequestComponents(
            modelID: "grok-imagine-video",
            prompt: "Model walks the runway",
            imageURL: nil,
            referenceImageURLs: [
                "https://example.com/a.png",
                "https://example.com/b.png",
            ],
            videoURL: nil,
            mode: .referenceToVideo,
            controls: XAIVideoGenerationControls(
                duration: 10,
                aspectRatio: .ratio16x9,
                resolution: .res720p
            )
        )

        XCTAssertEqual(components.endpoint, "videos/generations")
        XCTAssertNil(components.body["image"])
        XCTAssertNil(components.body["video"])
        XCTAssertEqual(components.body["duration"] as? Int, 10)
        XCTAssertEqual(components.body["aspect_ratio"] as? String, "16:9")
        XCTAssertEqual(components.body["resolution"] as? String, "720p")

        let refs = try XCTUnwrap(components.body["reference_images"] as? [[String: Any]])
        XCTAssertEqual(refs.count, 2)
        XCTAssertEqual(refs[0]["url"] as? String, "https://example.com/a.png")
        XCTAssertEqual(refs[1]["url"] as? String, "https://example.com/b.png")
    }

    func testReferenceToVideoClampsDurationTo10Seconds() {
        let components = XAIMediaRequestSupport.videoRequestComponents(
            modelID: "grok-imagine-video",
            prompt: "Model walks the runway",
            imageURL: nil,
            referenceImageURLs: ["https://example.com/a.png"],
            videoURL: nil,
            mode: .referenceToVideo,
            controls: XAIVideoGenerationControls(duration: 15)
        )
        XCTAssertEqual(components.body["duration"] as? Int, 10)
    }

    func testExtendVideoUsesExtensionsEndpointAndDurationOnly() {
        let components = XAIMediaRequestSupport.videoRequestComponents(
            modelID: "grok-imagine-video",
            prompt: "Camera pans over the shoulder",
            imageURL: nil,
            referenceImageURLs: nil,
            videoURL: "https://example.com/clip.mp4",
            mode: .extendVideo,
            controls: XAIVideoGenerationControls(
                duration: 6,
                aspectRatio: .ratio16x9,
                resolution: .res720p
            )
        )

        XCTAssertEqual(components.endpoint, "videos/extensions")
        XCTAssertEqual((components.body["video"] as? [String: Any])?["url"] as? String, "https://example.com/clip.mp4")
        XCTAssertEqual(components.body["duration"] as? Int, 6)
        // Extend does not accept aspect/resolution overrides.
        XCTAssertNil(components.body["aspect_ratio"])
        XCTAssertNil(components.body["resolution"])
        XCTAssertNil(components.body["image"])
        XCTAssertNil(components.body["reference_images"])
    }

    func testExtendVideoClampsDurationTo2Through10() {
        let tooLow = XAIMediaRequestSupport.videoRequestComponents(
            modelID: "grok-imagine-video",
            prompt: "continue",
            imageURL: nil,
            referenceImageURLs: nil,
            videoURL: "https://example.com/clip.mp4",
            mode: .extendVideo,
            controls: XAIVideoGenerationControls(duration: 1)
        )
        XCTAssertEqual(tooLow.body["duration"] as? Int, 2)

        let tooHigh = XAIMediaRequestSupport.videoRequestComponents(
            modelID: "grok-imagine-video",
            prompt: "continue",
            imageURL: nil,
            referenceImageURLs: nil,
            videoURL: "https://example.com/clip.mp4",
            mode: .extendVideo,
            controls: XAIVideoGenerationControls(duration: 15)
        )
        XCTAssertEqual(tooHigh.body["duration"] as? Int, 10)
    }

    func testEditVideoOmitsShapeControls() {
        let components = XAIMediaRequestSupport.videoRequestComponents(
            modelID: "grok-imagine-video",
            prompt: "Add sunglasses",
            imageURL: "https://example.com/ignored.png",
            referenceImageURLs: ["https://example.com/ref.png"],
            videoURL: "https://example.com/clip.mp4",
            mode: .editVideo,
            controls: XAIVideoGenerationControls(
                duration: 8,
                aspectRatio: .ratio9x16,
                resolution: .res720p
            )
        )

        XCTAssertEqual(components.endpoint, "videos/edits")
        XCTAssertEqual((components.body["video"] as? [String: Any])?["url"] as? String, "https://example.com/clip.mp4")
        XCTAssertNil(components.body["duration"])
        XCTAssertNil(components.body["aspect_ratio"])
        XCTAssertNil(components.body["resolution"])
        XCTAssertNil(components.body["image"])
        XCTAssertNil(components.body["reference_images"])
    }

    func testVideoEditComponentsIncludeVideoAndOmitGenerationOnlyControls() {
        let components = XAIMediaRequestSupport.videoRequestComponents(
            modelID: "grok-imagine-video",
            prompt: "Stylize this video",
            imageURL: "https://example.com/input.png",
            videoURL: "https://example.com/input.mp4",
            controls: XAIVideoGenerationControls(
                duration: 5,
                aspectRatio: .ratio16x9,
                resolution: .res720p
            )
        )

        XCTAssertEqual(components.endpoint, "videos/edits")
        XCTAssertNil(components.body["duration"])
        XCTAssertNil(components.body["aspect_ratio"])
        XCTAssertNil(components.body["resolution"])
        XCTAssertNil(components.body["image"])
        XCTAssertEqual((components.body["video"] as? [String: Any])?["url"] as? String, "https://example.com/input.mp4")
    }

    func testVideoGenerationOmitsUnsupportedAspectRatio() {
        let components = XAIMediaRequestSupport.videoRequestComponents(
            modelID: "grok-imagine-video",
            prompt: "A vertical product shot",
            imageURL: nil,
            videoURL: nil,
            controls: XAIVideoGenerationControls(
                duration: 0,
                aspectRatio: .ratio4x5,
                resolution: .res480p
            )
        )

        XCTAssertEqual(components.body["duration"] as? Int, 1)
        XCTAssertNil(components.body["aspect_ratio"])
        XCTAssertEqual(components.body["resolution"] as? String, "480p")
    }
}
