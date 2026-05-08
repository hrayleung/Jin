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
