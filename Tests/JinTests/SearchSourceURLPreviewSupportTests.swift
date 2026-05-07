import XCTest
@testable import Jin

final class SearchSourceURLPreviewSupportTests: XCTestCase {
    func testPreviewTextCombinesSnippetWithPathWhenDistinct() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/docs/search-source?q=swift"))

        XCTAssertEqual(
            SearchSourceURLPreviewSupport.previewText(
                snippet: "Provider summary",
                url: url,
                fallbackURLString: "https://example.com/docs/search-source?q=swift",
                usesGoogleGroundingRedirect: false
            ),
            "Provider summary · docs/search source · q=swift"
        )
        XCTAssertEqual(
            SearchSourceURLPreviewSupport.previewText(
                snippet: "Provider summary mentions docs/search source",
                url: url,
                fallbackURLString: "https://example.com/docs/search-source?q=swift",
                usesGoogleGroundingRedirect: false
            ),
            "Provider summary mentions docs/search source · docs/search source · q=swift"
        )
        XCTAssertEqual(
            SearchSourceURLPreviewSupport.previewText(
                snippet: "Provider summary mentions docs/search source · q=swift",
                url: url,
                fallbackURLString: "https://example.com/docs/search-source?q=swift",
                usesGoogleGroundingRedirect: false
            ),
            "Provider summary mentions docs/search source · q=swift"
        )
    }

    func testPreviewTextUsesGoogleRedirectQueryHintBeforePath() throws {
        let url = try XCTUnwrap(URL(string: "https://vertexaisearch.cloud.google.com/grounding-api-redirect?q=apple"))

        XCTAssertEqual(
            SearchSourceURLPreviewSupport.previewText(
                snippet: nil,
                url: url,
                fallbackURLString: url.absoluteString,
                usesGoogleGroundingRedirect: true
            ),
            "apple"
        )
    }

    func testPreviewTextUsesTargetURLHintForGoogleRedirects() throws {
        let targetURL = "https%3A%2F%2Fdeveloper.apple.com%2Fdocumentation%2Fswiftui%3Ftopic%3Dlayout"
        let url = try XCTUnwrap(
            URL(
                string: "https://vertexaisearch.cloud.google.com/grounding-api-redirect?url=\(targetURL)"
            )
        )

        XCTAssertEqual(
            SearchSourceURLPreviewSupport.previewText(
                snippet: nil,
                url: url,
                fallbackURLString: url.absoluteString,
                usesGoogleGroundingRedirect: true
            ),
            "documentation/swiftui · topic=layout"
        )
    }

    func testPreviewTextFallsBackToTargetURLWhenGoogleRedirectTargetHasNoPath() throws {
        let targetURL = "https%3A%2F%2Fwww.apple.com"
        let url = try XCTUnwrap(
            URL(
                string: "https://vertexaisearch.cloud.google.com/grounding-api-redirect?url=\(targetURL)"
            )
        )

        XCTAssertEqual(
            SearchSourceURLPreviewSupport.previewText(
                snippet: nil,
                url: url,
                fallbackURLString: url.absoluteString,
                usesGoogleGroundingRedirect: true
            ),
            "https://www.apple.com"
        )
    }

    func testPreviewTextFallsBackToURLWhenNoSnippetOrCompactURLPreview() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))

        XCTAssertEqual(
            SearchSourceURLPreviewSupport.previewText(
                snippet: nil,
                url: url,
                fallbackURLString: "https://example.com",
                usesGoogleGroundingRedirect: false
            ),
            "https://example.com"
        )
    }
}
