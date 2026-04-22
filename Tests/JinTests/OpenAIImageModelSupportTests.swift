import XCTest
@testable import Jin

final class OpenAIImageModelSupportTests: XCTestCase {
    func testGPTImage2SizeValidationAcceptsDocumentedCustomSizes() {
        XCTAssertNil(
            OpenAIImageModelSupport.validate(
                size: OpenAIImageSize(rawValue: "2048x1152"),
                for: "gpt-image-2"
            )
        )
        XCTAssertNil(
            OpenAIImageModelSupport.validate(
                size: OpenAIImageSize(rawValue: "3840x2160"),
                for: "gpt-image-2-2026-04-21"
            )
        )
    }

    func testGPTImage2SizeValidationRejectsUnsupportedSizes() {
        XCTAssertEqual(
            OpenAIImageModelSupport.validate(
                size: OpenAIImageSize(rawValue: "1025x1025"),
                for: "gpt-image-2"
            ),
            "Width and height must both be multiples of 16."
        )
        XCTAssertEqual(
            OpenAIImageModelSupport.validate(
                size: OpenAIImageSize(rawValue: "4096x1024"),
                for: "gpt-image-2"
            ),
            "The largest side cannot exceed 3840 pixels."
        )
        XCTAssertEqual(
            OpenAIImageModelSupport.validate(
                size: OpenAIImageSize(rawValue: "1024x256"),
                for: "gpt-image-2"
            ),
            "Aspect ratio cannot exceed 3:1."
        )
    }

    func testNormalizeOpenAIImageControlsClearsUnsupportedGPTImage2Fields() {
        var controls = OpenAIImageGenerationControls(
            size: OpenAIImageSize(rawValue: "1025x1025"),
            quality: .high,
            background: .transparent,
            outputFormat: .jpeg,
            outputCompression: 75,
            moderation: .low,
            inputFidelity: .high
        )

        ChatControlNormalizationSupport.normalizeOpenAIImageControls(
            &controls,
            lowerModelID: "gpt-image-2"
        )

        XCTAssertNil(controls.size)
        XCTAssertEqual(controls.quality, .high)
        XCTAssertNil(controls.background)
        XCTAssertEqual(controls.outputFormat, .jpeg)
        XCTAssertEqual(controls.outputCompression, 75)
        XCTAssertEqual(controls.moderation, .low)
        XCTAssertNil(controls.inputFidelity)
    }

    func testNormalizeOpenAIImageControlsKeepsSupportedGPTImage2CustomSize() {
        var controls = OpenAIImageGenerationControls(
            size: OpenAIImageSize(rawValue: "2048x1152"),
            quality: .medium,
            background: .opaque,
            outputFormat: .webp,
            outputCompression: 50,
            moderation: .auto
        )

        ChatControlNormalizationSupport.normalizeOpenAIImageControls(
            &controls,
            lowerModelID: "gpt-image-2"
        )

        XCTAssertEqual(controls.size, OpenAIImageSize(rawValue: "2048x1152"))
        XCTAssertEqual(controls.background, .opaque)
        XCTAssertEqual(controls.outputFormat, .webp)
        XCTAssertEqual(controls.outputCompression, 50)
    }
}
