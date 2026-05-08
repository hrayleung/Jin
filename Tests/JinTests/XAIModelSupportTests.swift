import XCTest
@testable import Jin

final class XAIModelSupportTests: XCTestCase {
    func testKnownImageAndVideoIDsUseExactSets() {
        XCTAssertTrue(XAIModelSupport.isImageGenerationModelID("grok-imagine-image"))
        XCTAssertTrue(XAIModelSupport.isImageGenerationModelID("grok-imagine-image-quality"))
        XCTAssertTrue(XAIModelSupport.isImageGenerationModelID("GROK-IMAGINE-IMAGE-PRO"))
        XCTAssertTrue(XAIModelSupport.isVideoGenerationModelID("grok-imagine-video"))

        XCTAssertFalse(XAIModelSupport.isImageGenerationModelID("grok-imagine-image-custom"))
        XCTAssertFalse(XAIModelSupport.isVideoGenerationModelID("grok-imagine-video-custom"))
    }

    func testSupportsImageResolutionControlOnlyForQualityAndProTiers() {
        XCTAssertTrue(XAIModelSupport.supportsImageResolutionControl("grok-imagine-image-quality"))
        XCTAssertTrue(XAIModelSupport.supportsImageResolutionControl("GROK-IMAGINE-IMAGE-PRO"))

        XCTAssertFalse(XAIModelSupport.supportsImageResolutionControl("grok-imagine-image"))
        XCTAssertFalse(XAIModelSupport.supportsImageResolutionControl("grok-2-image-1212"))
        XCTAssertFalse(XAIModelSupport.supportsImageResolutionControl("grok-4"))
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
