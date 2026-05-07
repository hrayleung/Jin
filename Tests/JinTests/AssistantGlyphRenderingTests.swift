import XCTest
@testable import Jin

final class AssistantGlyphRenderingTests: XCTestCase {
    func testNormalizedGlyphTrimsWhitespaceAndNewlines() {
        XCTAssertEqual(AssistantGlyphRendering.normalizedGlyph(" \n sparkles\t "), "sparkles")
    }

    func testNormalizedGlyphReturnsEmptyStringForNilAndBlankGlyphs() {
        XCTAssertEqual(AssistantGlyphRendering.normalizedGlyph(nil), "")
        XCTAssertEqual(AssistantGlyphRendering.normalizedGlyph(" \n\t "), "")
    }
}
