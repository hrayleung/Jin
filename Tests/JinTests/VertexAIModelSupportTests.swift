import XCTest
@testable import Jin

final class VertexAIModelSupportTests: XCTestCase {
    func testMakeModelInfoConfiguresGemini25FlashCapabilities() {
        let support = VertexAIModelSupport()

        let info = support.makeModelInfo(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash", contextWindow: 1_048_576)

        XCTAssertTrue(info.capabilities.contains(ModelCapability.streaming))
        XCTAssertTrue(info.capabilities.contains(ModelCapability.toolCalling))
        XCTAssertTrue(info.capabilities.contains(ModelCapability.promptCaching))
        XCTAssertTrue(info.capabilities.contains(ModelCapability.vision))
        XCTAssertTrue(info.capabilities.contains(ModelCapability.audio))
        XCTAssertTrue(info.capabilities.contains(ModelCapability.reasoning))
        XCTAssertEqual(info.reasoningConfig?.type, .budget)
        XCTAssertEqual(info.reasoningConfig?.defaultBudget, 2048)
    }

    func testMakeModelInfoConfiguresGemini15ModelCapabilitiesFromExactIDs() {
        let support = VertexAIModelSupport()

        let pro = support.makeModelInfo(id: "gemini-1.5-pro", displayName: "Gemini 1.5 Pro", contextWindow: 2_097_152)
        let flash = support.makeModelInfo(id: "gemini-1.5-flash", displayName: "Gemini 1.5 Flash", contextWindow: 1_048_576)

        for info in [pro, flash] {
            XCTAssertTrue(info.capabilities.contains(.streaming))
            XCTAssertTrue(info.capabilities.contains(.toolCalling))
            XCTAssertTrue(info.capabilities.contains(.promptCaching))
            XCTAssertTrue(info.capabilities.contains(.vision))
            XCTAssertTrue(info.capabilities.contains(.audio))
            XCTAssertTrue(info.capabilities.contains(.reasoning))
            XCTAssertEqual(info.reasoningConfig?.type, .effort)
            XCTAssertEqual(info.reasoningConfig?.defaultEffort, .medium)
        }
    }

    func testThinkingConfigSupportExcludesGemini3ImagePreviewModels() {
        let support = VertexAIModelSupport()

        XCTAssertTrue(support.supportsThinking("gemini-3-pro-image-preview"))
        XCTAssertFalse(support.supportsThinkingConfig("gemini-3-pro-image-preview"))
        XCTAssertFalse(support.supportsThinkingConfig("gemini-3.1-flash-image-preview"))
    }

    func testKnownImagenModelsAreClassifiedExplicitly() {
        let support = VertexAIModelSupport()

        let imagen = try? XCTUnwrap(support.knownModels.first(where: { $0.id == "imagen-4.0-generate-preview-06-06" }))
        XCTAssertEqual(imagen?.name, "Imagen 4.0")

        let info = support.makeModelInfo(id: "imagen-4.0-generate-preview-06-06", displayName: "Imagen 4.0", contextWindow: 0)

        XCTAssertTrue(info.capabilities.contains(.imageGeneration))
        XCTAssertFalse(info.capabilities.contains(.streaming))
        XCTAssertFalse(info.capabilities.contains(.toolCalling))
        XCTAssertFalse(info.capabilities.contains(.promptCaching))
        XCTAssertFalse(info.capabilities.contains(.vision))
        XCTAssertNil(info.reasoningConfig)
    }

    func testUnknownImagenIDsRemainConservative() {
        let support = VertexAIModelSupport()

        let info = support.makeModelInfo(id: "imagen-custom-experiment", displayName: "Imagen Custom", contextWindow: 0)

        XCTAssertFalse(info.capabilities.contains(.imageGeneration))
        XCTAssertFalse(info.capabilities.contains(.streaming))
        XCTAssertFalse(info.capabilities.contains(.toolCalling))
        XCTAssertFalse(info.capabilities.contains(.promptCaching))
        XCTAssertFalse(info.capabilities.contains(.vision))
        XCTAssertNil(info.reasoningConfig)
    }

    func testExactSharedGeminiIDsDoNotFallBackToConservativeMetadata() {
        let support = VertexAIModelSupport()

        let ids = ["gemini-3", "gemini-3-pro", "gemini-2.5"]

        for id in ids {
            let info = support.makeModelInfo(id: id, displayName: id, contextWindow: 1_048_576)

            XCTAssertTrue(info.capabilities.contains(.streaming), "Expected streaming for \(id)")
            XCTAssertTrue(info.capabilities.contains(.toolCalling), "Expected tool calling for \(id)")
            XCTAssertTrue(info.capabilities.contains(.promptCaching), "Expected prompt caching for \(id)")
            XCTAssertTrue(info.capabilities.contains(.vision), "Expected vision for \(id)")
            XCTAssertTrue(info.capabilities.contains(.audio), "Expected audio for \(id)")
            XCTAssertTrue(info.capabilities.contains(.reasoning), "Expected reasoning for \(id)")
        }
    }

    func testExactSharedGeminiIDsDriveCapabilityQueries() {
        let support = VertexAIModelSupport()

        for id in ["gemini-3", "gemini-3-pro", "gemini-2.5"] {
            XCTAssertFalse(support.supportsImageGeneration(id), "Did not expect image generation for \(id)")
            XCTAssertTrue(support.supportsFunctionCalling(id), "Expected function calling for \(id)")
            XCTAssertTrue(support.supportsThinking(id), "Expected thinking for \(id)")
            XCTAssertTrue(support.supportsThinkingConfig(id), "Expected thinking config for \(id)")
            XCTAssertTrue(support.supportsThinkingLevel(id), "Expected thinking level for \(id)")
        }
    }

    func testUnknownImagenIDsDoNotGuessRequestCapabilities() {
        let support = VertexAIModelSupport()

        XCTAssertFalse(support.supportsImageGeneration("imagen-custom-experiment"))
        XCTAssertFalse(support.supportsFunctionCalling("imagen-custom-experiment"))
        XCTAssertFalse(support.supportsThinking("imagen-custom-experiment"))
        XCTAssertFalse(support.supportsThinkingConfig("imagen-custom-experiment"))
        XCTAssertFalse(support.supportsThinkingLevel("imagen-custom-experiment"))
    }

    func testGemini35FlashIsKnownAndSupportsFullCapabilitySet() {
        let support = VertexAIModelSupport()

        XCTAssertTrue(support.knownModels.contains { $0.id == "gemini-3.5-flash" })

        XCTAssertFalse(support.supportsImageGeneration("gemini-3.5-flash"))
        XCTAssertTrue(support.supportsFunctionCalling("gemini-3.5-flash"))
        XCTAssertTrue(support.supportsThinking("gemini-3.5-flash"))
        XCTAssertTrue(support.supportsThinkingConfig("gemini-3.5-flash"))
        XCTAssertTrue(support.supportsThinkingLevel("gemini-3.5-flash"))
        XCTAssertTrue(support.supportsNativePDF("gemini-3.5-flash"))
        XCTAssertTrue(support.supportsCodeExecution("gemini-3.5-flash"))
        XCTAssertTrue(support.supportsGoogleMaps("gemini-3.5-flash"))
        XCTAssertTrue(support.supportsGoogleMaps("gemini-3-flash-preview"))

        let info = support.makeModelInfo(id: "gemini-3.5-flash", displayName: "Gemini 3.5 Flash", contextWindow: 1_048_576)
        XCTAssertTrue(info.capabilities.contains(.streaming))
        XCTAssertTrue(info.capabilities.contains(.toolCalling))
        XCTAssertTrue(info.capabilities.contains(.vision))
        XCTAssertTrue(info.capabilities.contains(.audio))
        XCTAssertTrue(info.capabilities.contains(.reasoning))
        XCTAssertTrue(info.capabilities.contains(.promptCaching))
        XCTAssertTrue(info.capabilities.contains(.nativePDF))
        XCTAssertTrue(info.capabilities.contains(.codeExecution))
        XCTAssertFalse(info.capabilities.contains(.imageGeneration))
        XCTAssertEqual(info.reasoningConfig?.type, .effort)
        XCTAssertEqual(info.reasoningConfig?.defaultEffort, .medium)
    }

    func testGemini36FlashAnd35FlashLiteAreKnownAndFullySupportedOnVertex() {
        let support = VertexAIModelSupport()

        for id in ["gemini-3.6-flash", "gemini-3.5-flash-lite"] {
            XCTAssertTrue(support.knownModels.contains { $0.id == id }, id)
            XCTAssertFalse(support.supportsImageGeneration(id), id)
            XCTAssertTrue(support.supportsFunctionCalling(id), id)
            XCTAssertTrue(support.supportsThinking(id), id)
            XCTAssertTrue(support.supportsThinkingConfig(id), id)
            XCTAssertTrue(support.supportsThinkingLevel(id), id)
            XCTAssertTrue(support.supportsNativePDF(id), id)
            XCTAssertTrue(support.supportsCodeExecution(id), id)
            XCTAssertTrue(support.supportsGoogleMaps(id), id)
            XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: id), id)
        }

        let flash36 = support.makeModelInfo(
            id: "gemini-3.6-flash",
            displayName: "Gemini 3.6 Flash",
            contextWindow: 1_048_576
        )
        XCTAssertEqual(flash36.reasoningConfig?.defaultEffort, .medium)
        XCTAssertTrue(flash36.capabilities.contains(.codeExecution))
        XCTAssertTrue(flash36.capabilities.contains(.nativePDF))

        let flashLite35 = support.makeModelInfo(
            id: "gemini-3.5-flash-lite",
            displayName: "Gemini 3.5 Flash-Lite",
            contextWindow: 1_048_576
        )
        XCTAssertEqual(flashLite35.reasoningConfig?.defaultEffort, .minimal)
        XCTAssertTrue(flashLite35.capabilities.contains(.codeExecution))
        XCTAssertTrue(flashLite35.capabilities.contains(.nativePDF))
    }

    func testStableGemini31FlashLiteIsExposedForVertexAI() {
        let support = VertexAIModelSupport()

        // Stable Flash-Lite is preferred over the retired preview ID (shut down 2026-05-25).
        XCTAssertTrue(support.knownModels.contains { $0.id == "gemini-3.1-flash-lite" })
        XCTAssertTrue(support.knownModels.contains { $0.id == "gemini-3.1-flash-lite-preview" })

        let info = support.makeModelInfo(
            id: "gemini-3.1-flash-lite",
            displayName: "Gemini 3.1 Flash-Lite",
            contextWindow: 1_048_576
        )

        XCTAssertTrue(info.capabilities.contains(.streaming))
        XCTAssertTrue(info.capabilities.contains(.toolCalling))
        XCTAssertTrue(info.capabilities.contains(.reasoning))
        XCTAssertEqual(info.reasoningConfig?.defaultEffort, .minimal)
        XCTAssertTrue(support.supportsFunctionCalling("gemini-3.1-flash-lite"))
        XCTAssertTrue(support.supportsThinking("gemini-3.1-flash-lite"))
        XCTAssertTrue(support.supportsNativePDF("gemini-3.1-flash-lite"))
        XCTAssertTrue(support.supportsGoogleMaps("gemini-3.1-flash-lite"))
    }
}
