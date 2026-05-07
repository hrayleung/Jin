import XCTest
@testable import Jin

final class SearchSourcePresentationSupportTests: XCTestCase {
    func testRenderPresentationUsesResolvedURLAndPreviewText() throws {
        let source = try XCTUnwrap(
            SearchSource(
                rawURL: "https://vertexaisearch.cloud.google.com/grounding-api-redirect?q=apple",
                title: "Apple",
                previewText: "Provider preview"
            )
        )

        let presentation = SearchSourcePresentationSupport.renderPresentation(
            for: source,
            resolvedURLString: "https://www.apple.com/newsroom/",
            resolvedPreviewText: "Resolved preview"
        )

        XCTAssertEqual(presentation.urlString, "https://www.apple.com/newsroom/")
        XCTAssertEqual(presentation.openURL?.absoluteString, "https://www.apple.com/newsroom/")
        XCTAssertEqual(presentation.displayTitle, "Apple")
        XCTAssertEqual(presentation.host, "www.apple.com")
        XCTAssertEqual(presentation.hostDisplay, "apple.com")
        XCTAssertEqual(presentation.hostDisplayInitial, "A")
        XCTAssertEqual(presentation.previewText, "Resolved preview · newsroom")
    }

    func testRenderPresentationFallsBackToCanonicalSourceAndMapsInitial() throws {
        let source = try XCTUnwrap(
            SearchSource(
                rawURL: "https://maps.google.com/?q=Apple+Park",
                title: nil,
                previewText: nil,
                kind: .googleMaps
            )
        )

        let presentation = SearchSourcePresentationSupport.renderPresentation(
            for: source,
            resolvedURLString: nil,
            resolvedPreviewText: nil
        )

        XCTAssertEqual(presentation.urlString, "https://maps.google.com/?q=Apple+Park")
        XCTAssertEqual(presentation.displayTitle, "Google Maps")
        XCTAssertEqual(presentation.hostDisplay, "Google Maps")
        XCTAssertEqual(presentation.hostDisplayInitial, "M")
        XCTAssertEqual(presentation.previewText, "q=Apple+Park")
    }

    func testNormalizeSnippetCondensesWhitespaceAndTruncatesLongText() {
        XCTAssertEqual(
            SearchSourcePresentationSupport.normalizeSnippet("  One\n\nTwo\tThree  "),
            "One Two Three"
        )
        XCTAssertNil(SearchSourcePresentationSupport.normalizeSnippet(" \n\t "))

        let longSnippet = String(repeating: "a", count: 421)
        XCTAssertEqual(
            SearchSourcePresentationSupport.normalizeSnippet(longSnippet),
            String(repeating: "a", count: 420) + "…"
        )
    }

    func testPreferredSnippetUsesLongerCandidateWhenPresent() {
        XCTAssertEqual(
            SearchSourcePresentationSupport.preferredSnippet(existing: "short", candidate: "longer preview"),
            "longer preview"
        )
        XCTAssertEqual(
            SearchSourcePresentationSupport.preferredSnippet(existing: "existing preview", candidate: "short"),
            "existing preview"
        )
        XCTAssertEqual(
            SearchSourcePresentationSupport.preferredSnippet(existing: "existing", candidate: nil),
            "existing"
        )
    }

    func testPreferredRenderSnippetPrefersResolvedPreview() {
        XCTAssertEqual(
            SearchSourcePresentationSupport.preferredRenderSnippet(
                providerSnippet: "Provider preview",
                resolvedSnippet: " Resolved\npreview "
            ),
            "Resolved preview"
        )
        XCTAssertEqual(
            SearchSourcePresentationSupport.preferredRenderSnippet(
                providerSnippet: " Provider\npreview ",
                resolvedSnippet: " "
            ),
            "Provider preview"
        )
    }

}
