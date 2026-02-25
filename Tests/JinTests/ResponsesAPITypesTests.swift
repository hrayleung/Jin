import XCTest
@testable import Jin

final class ResponsesAPITypesTests: XCTestCase {
    func testCitationPreviewSnippetSupportsSingleCharacterRange() {
        let snippet = citationPreviewSnippet(
            text: "abc",
            startIndex: 1,
            endIndex: 1
        )

        XCTAssertEqual(snippet, "abc")
    }

    func testCitationPreviewSnippetUsesCharacterOffsetsWithEmojiPrefix() {
        let prefix = String(repeating: "🙂", count: 120)
        let suffix = String(repeating: "x", count: 120)
        let text = prefix + "TARGET" + suffix

        let snippet = citationPreviewSnippet(
            text: text,
            startIndex: 120,
            endIndex: 125
        )

        XCTAssertNotNil(snippet)
        XCTAssertTrue(snippet?.contains("TARGET") == true)
    }
}
