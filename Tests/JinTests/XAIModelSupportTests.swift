import XCTest
@testable import Jin

final class XAIModelSupportTests: XCTestCase {
    func testKnownImageAndVideoIDsUseExactSets() {
        XCTAssertTrue(XAIModelSupport.isImageGenerationModelID("grok-imagine-image"))
        XCTAssertTrue(XAIModelSupport.isImageGenerationModelID("grok-imagine-image-2.0"))
        XCTAssertTrue(XAIModelSupport.isImageGenerationModelID("GROK-IMAGINE-IMAGE-2.0"))
        XCTAssertTrue(XAIModelSupport.isImageGenerationModelID("grok-imagine-image-quality"))
        XCTAssertTrue(XAIModelSupport.isImageGenerationModelID("GROK-IMAGINE-IMAGE-PRO"))
        XCTAssertTrue(XAIModelSupport.isVideoGenerationModelID("grok-imagine-video"))
        XCTAssertTrue(XAIModelSupport.isVideoGenerationModelID("grok-imagine-video-1.5"))
        XCTAssertTrue(XAIModelSupport.isVideoGenerationModelID("grok-imagine-video-1.5-preview"))
        XCTAssertTrue(XAIModelSupport.isVideoGenerationModelID("GROK-IMAGINE-VIDEO-1.5-PREVIEW"))
        XCTAssertTrue(XAIModelSupport.isVideoGenerationModelID("grok-imagine-video-1.5-2026-05-30"))

        XCTAssertFalse(XAIModelSupport.isImageGenerationModelID("grok-imagine-image-custom"))
        XCTAssertFalse(XAIModelSupport.isImageGenerationModelID("grok-imagine-image-2.0-custom"))
        XCTAssertFalse(XAIModelSupport.isVideoGenerationModelID("grok-imagine-video-custom"))
    }

    func testImageRequiredVideoModelsRejectTextToVideo() {
        // grok-imagine-video-1.5 is image-to-video only (API rejects text-only).
        XCTAssertTrue(XAIModelSupport.requiresImageInputForVideoGeneration("grok-imagine-video-1.5"))
        XCTAssertTrue(XAIModelSupport.requiresImageInputForVideoGeneration("grok-imagine-video-1.5-preview"))
        XCTAssertTrue(XAIModelSupport.requiresImageInputForVideoGeneration("GROK-IMAGINE-VIDEO-1.5-PREVIEW"))
        XCTAssertTrue(XAIModelSupport.requiresImageInputForVideoGeneration("grok-imagine-video-1.5-2026-05-30"))

        // Base model supports text-to-video, so it must NOT require an image.
        XCTAssertFalse(XAIModelSupport.requiresImageInputForVideoGeneration("grok-imagine-video"))
    }

    func testFullHDVideoResolutionOnlyOn15Family() {
        XCTAssertTrue(XAIModelSupport.supportsFullHDVideoResolution("grok-imagine-video-1.5"))
        XCTAssertTrue(XAIModelSupport.supportsFullHDVideoResolution("grok-imagine-video-1.5-preview"))
        XCTAssertFalse(XAIModelSupport.supportsFullHDVideoResolution("grok-imagine-video"))
        XCTAssertEqual(
            XAIModelSupport.availableVideoResolutions(for: "grok-imagine-video-1.5"),
            [.res480p, .res720p, .res1080p]
        )
        XCTAssertEqual(
            XAIModelSupport.availableVideoResolutions(for: "grok-imagine-video"),
            [.res480p, .res720p]
        )
    }

    func testSupportsImageResolutionControlOnlyForQualityAndProTiers() {
        XCTAssertTrue(XAIModelSupport.supportsImageResolutionControl("grok-imagine-image-quality"))
        XCTAssertTrue(XAIModelSupport.supportsImageResolutionControl("GROK-IMAGINE-IMAGE-PRO"))
        XCTAssertTrue(XAIModelSupport.supportsImageResolutionControl("grok-imagine-image-2.0"))

        XCTAssertFalse(XAIModelSupport.supportsImageResolutionControl("grok-imagine-image"))
        XCTAssertFalse(XAIModelSupport.supportsImageResolutionControl("grok-2-image-1212"))
        XCTAssertFalse(XAIModelSupport.supportsImageResolutionControl("grok-4"))
    }

    func testSupportsImageQualityControlOnlyForImagineImage20() {
        XCTAssertTrue(XAIModelSupport.supportsImageQualityControl("grok-imagine-image-2.0"))
        XCTAssertTrue(XAIModelSupport.supportsImageQualityControl("GROK-IMAGINE-IMAGE-2.0"))
        XCTAssertEqual(
            XAIModelSupport.supportedImageQualities(for: "grok-imagine-image-2.0"),
            [.low, .medium]
        )

        XCTAssertFalse(XAIModelSupport.supportsImageQualityControl("grok-imagine-image"))
        XCTAssertFalse(XAIModelSupport.supportsImageQualityControl("grok-imagine-image-quality"))
        XCTAssertFalse(XAIModelSupport.supportsImageQualityControl("grok-imagine-image-pro"))
        XCTAssertTrue(XAIModelSupport.supportedImageQualities(for: "grok-imagine-image").isEmpty)
    }

    func testInferredCapabilitiesPreferVideoAndImageOutputModels() {
        XCTAssertEqual(
            XAIModelSupport.inferredCapabilities(
                for: XAIModelData(
                    id: "api-video-model",
                    outputModalities: ["text", "video"],
                    contextWindow: 42_000
                )
            ),
            [.videoGeneration]
        )

        XCTAssertEqual(
            XAIModelSupport.inferredCapabilities(
                for: XAIModelData(
                    id: "api-image-model",
                    modalities: ["image"],
                    contextWindow: 42_000
                )
            ),
            [.imageGeneration]
        )
    }

    func testInferredChatCapabilitiesUseVisionReasoningAndNativePDFMetadata() {
        let capabilities = XAIModelSupport.inferredCapabilities(
            for: XAIModelData(
                id: "grok-4.20",
                inputModalities: ["text", "image"],
                outputModalities: ["text"]
            )
        )

        XCTAssertTrue(capabilities.contains(.streaming))
        XCTAssertTrue(capabilities.contains(.toolCalling))
        XCTAssertTrue(capabilities.contains(.promptCaching))
        XCTAssertTrue(capabilities.contains(.vision))
        XCTAssertTrue(capabilities.contains(.reasoning))
        XCTAssertTrue(capabilities.contains(.nativePDF))
        XCTAssertFalse(capabilities.contains(.imageGeneration))
        XCTAssertFalse(capabilities.contains(.videoGeneration))
    }

    func testModelInfoUsesContextWindowFallback() {
        let info = XAIModelSupport.modelInfo(
            from: XAIModelData(id: "unknown-chat-model")
        )

        XCTAssertEqual(info.id, "unknown-chat-model")
        XCTAssertEqual(info.name, "unknown-chat-model")
        XCTAssertEqual(info.contextWindow, 128_000)
        XCTAssertEqual(info.capabilities, [.streaming, .toolCalling, .promptCaching])
        XCTAssertNil(info.reasoningConfig)
    }
}
