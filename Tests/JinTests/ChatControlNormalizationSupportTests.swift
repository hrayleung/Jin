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
}
