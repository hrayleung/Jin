import XCTest
@testable import Jin

final class GenerationControlsResolverTests: XCTestCase {
    func testResolvedForRequestAppliesAssistantDefaultsWhenUnset() {
        let base = GenerationControls()

        let resolved = GenerationControlsResolver.resolvedForRequest(
            base: base,
            assistantTemperature: 0.1,
            assistantMaxOutputTokens: 2048
        )

        XCTAssertEqual(resolved.temperature, 0.1)
        XCTAssertEqual(resolved.maxTokens, 2048)
    }

    func testResolvedForRequestKeepsExplicitOverrides() {
        var base = GenerationControls()
        base.temperature = 0.7
        base.maxTokens = 512

        let resolved = GenerationControlsResolver.resolvedForRequest(
            base: base,
            assistantTemperature: 0.1,
            assistantMaxOutputTokens: 2048
        )

        XCTAssertEqual(resolved.temperature, 0.7)
        XCTAssertEqual(resolved.maxTokens, 512)
    }
}
