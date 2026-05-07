import XCTest
@testable import Jin

final class ResponsesAPITypesTests: XCTestCase {
    func testOutputAnnotationTrimsDirectTypeAndFallsBackForNestedCitation() throws {
        let json = """
        [
          {
            "type": "output_text",
            "text": "Read the docs.",
            "annotations": [
              {
                "type": "  custom_annotation  ",
                "url": "https://example.com/direct"
              },
              {
                "type": "   ",
                "url_citation": {
                  "url": "https://example.com/nested",
                  "title": "Nested"
                }
              }
            ]
          }
        ]
        """

        let content = try JSONDecoder().decode(
            [ResponsesAPIOutputContent].self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )

        XCTAssertEqual(content.first?.annotations?.first?.type, "custom_annotation")
        XCTAssertEqual(content.first?.annotations?.last?.type, "url_citation")
    }

    func testCitationArgumentsTrimAndDeduplicateAnnotationSources() throws {
        let json = """
        [
          {
            "type": "output_text",
            "text": "Read the docs.",
            "annotations": [
              {
                "type": "url_citation",
                "url": " https://example.com/docs ",
                "title": " Docs "
              },
              {
                "type": "url_citation",
                "url": "https://example.com/docs",
                "title": "Ignored duplicate"
              },
              {
                "type": "url_citation",
                "url": "   ",
                "title": "Ignored blank URL"
              }
            ]
          }
        ]
        """
        let content = try JSONDecoder().decode(
            [ResponsesAPIOutputContent].self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )

        let arguments = ResponsesAPIResponse.citationArguments(from: content)
        let sources = try XCTUnwrap(arguments["sources"]?.value as? [[String: Any]])

        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?["url"] as? String, "https://example.com/docs")
        XCTAssertEqual(sources.first?["title"] as? String, "Docs")
        XCTAssertEqual(arguments["url"]?.value as? String, "https://example.com/docs")
        XCTAssertEqual(arguments["title"]?.value as? String, "Docs")
    }

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
