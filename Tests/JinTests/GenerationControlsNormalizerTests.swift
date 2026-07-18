import XCTest
@testable import Jin

final class GenerationControlsNormalizerTests: XCTestCase {
    func testClampsMaxTokensToModelLimit() {
        var controls = GenerationControls(maxTokens: 200_000)
        GenerationControlsNormalizer.normalizeMaxTokensForModel(
            controls: &controls,
            modelMaxOutputTokens: 128_000
        )
        XCTAssertEqual(controls.maxTokens, 128_000)
    }

    func testMediaGenerationStripsChatOnlyControls() {
        var controls = GenerationControls(
            reasoning: ReasoningControls(enabled: true, effort: .medium),
            webSearch: WebSearchControls(enabled: true),
            searchPlugin: SearchPluginControls(preferJinSearch: true),
            mcpTools: MCPToolsControls(enabled: true)
        )
        GenerationControlsNormalizer.normalizeMediaGenerationOverrides(
            controls: &controls,
            supportsMediaGenerationControl: true,
            supportsReasoningControl: false,
            supportsWebSearchControl: false
        )
        XCTAssertNil(controls.reasoning)
        XCTAssertNil(controls.webSearch)
        XCTAssertNil(controls.searchPlugin)
        XCTAssertNil(controls.mcpTools)
    }

    func testResolverClampsAssistantMaxTokens() {
        let resolved = GenerationControlsResolver.resolvedForRequest(
            base: GenerationControls(maxTokens: 500_000),
            assistantTemperature: nil,
            assistantMaxOutputTokens: nil,
            modelMaxOutputTokens: 32_000
        )
        XCTAssertEqual(resolved.maxTokens, 32_000)
    }
}
