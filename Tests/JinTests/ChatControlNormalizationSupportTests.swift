import XCTest
@testable import Jin

final class ChatControlNormalizationSupportTests: XCTestCase {
    func testNormalizeWebSearchControlsClearsUnsupportedWebSearch() {
        var controls = GenerationControls(
            webSearch: WebSearchControls(
                enabled: true,
                contextSize: .high,
                sources: [.web]
            )
        )

        ChatControlNormalizationSupport.normalizeWebSearchControls(
            controls: &controls,
            modelSupportsWebSearchControl: false,
            providerType: .openai
        )

        XCTAssertNil(controls.webSearch)
    }

    func testNormalizeWebSearchControlsAppliesSupportedProviderDefaults() {
        var controls = GenerationControls(
            webSearch: WebSearchControls(
                enabled: true,
                sources: [.x]
            )
        )

        ChatControlNormalizationSupport.normalizeWebSearchControls(
            controls: &controls,
            modelSupportsWebSearchControl: true,
            providerType: .openai
        )

        XCTAssertEqual(controls.webSearch?.enabled, true)
        XCTAssertEqual(controls.webSearch?.contextSize, .medium)
        XCTAssertNil(controls.webSearch?.sources)
    }

    func testNormalizeWebSearchControlsLeavesDisabledSupportedWebSearchUnchanged() {
        var controls = GenerationControls(
            webSearch: WebSearchControls(
                enabled: false,
                contextSize: .high,
                sources: [.x]
            )
        )

        ChatControlNormalizationSupport.normalizeWebSearchControls(
            controls: &controls,
            modelSupportsWebSearchControl: true,
            providerType: .openai
        )

        XCTAssertEqual(controls.webSearch?.enabled, false)
        XCTAssertEqual(controls.webSearch?.contextSize, .high)
        XCTAssertEqual(controls.webSearch?.sources, [.x])
    }

    func testNormalizeImageGenerationControlsClearsUnsupportedXAIResolution() {
        var controls = GenerationControls(
            xaiImageGeneration: XAIImageGenerationControls(
                aspectRatio: .ratio16x9,
                resolution: .res2k
            )
        )

        ChatControlNormalizationSupport.normalizeImageGenerationControls(
            controls: &controls,
            supportsImageGenerationControl: true,
            providerType: .xai,
            supportsCurrentModelImageSizeControl: false,
            supportedCurrentModelImageSizes: [],
            supportedCurrentModelImageAspectRatios: [],
            lowerModelID: "grok-imagine-image"
        )

        XCTAssertEqual(controls.xaiImageGeneration?.aspectRatio, .ratio16x9)
        XCTAssertNil(controls.xaiImageGeneration?.resolution)
    }

    func testNormalizeImageGenerationControlsKeepsImagineImage20QualityAndResolution() {
        var controls = GenerationControls(
            xaiImageGeneration: XAIImageGenerationControls(
                aspectRatio: .ratio16x9,
                resolution: .res2k,
                quality: .low
            )
        )

        ChatControlNormalizationSupport.normalizeImageGenerationControls(
            controls: &controls,
            supportsImageGenerationControl: true,
            providerType: .xai,
            supportsCurrentModelImageSizeControl: false,
            supportedCurrentModelImageSizes: [],
            supportedCurrentModelImageAspectRatios: [],
            lowerModelID: "grok-imagine-image-2.0"
        )

        XCTAssertEqual(controls.xaiImageGeneration?.aspectRatio, .ratio16x9)
        XCTAssertEqual(controls.xaiImageGeneration?.resolution, .res2k)
        XCTAssertEqual(controls.xaiImageGeneration?.quality, .low)
    }

    func testNormalizeImageGenerationControlsDropsHighQualityOnImagineImage20() {
        var controls = GenerationControls(
            xaiImageGeneration: XAIImageGenerationControls(quality: .high)
        )

        ChatControlNormalizationSupport.normalizeImageGenerationControls(
            controls: &controls,
            supportsImageGenerationControl: true,
            providerType: .xai,
            supportsCurrentModelImageSizeControl: false,
            supportedCurrentModelImageSizes: [],
            supportedCurrentModelImageAspectRatios: [],
            lowerModelID: "grok-imagine-image-2.0"
        )

        XCTAssertNil(controls.xaiImageGeneration)
    }
}
