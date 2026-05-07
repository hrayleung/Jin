import XCTest
@testable import Jin

final class SearchSourceEnrichmentStateTests: XCTestCase {
    func testPruneStaleResolvedSourceDataKeepsOnlyActiveSources() throws {
        let active = try XCTUnwrap(SearchSource(rawURL: "https://example.com/active", title: nil, previewText: nil))
        let stale = try XCTUnwrap(SearchSource(rawURL: "https://example.com/stale", title: nil, previewText: nil))

        var state = SearchSourceEnrichmentState()
        state.setResolvedRedirectURL("https://resolved.example.com/active", for: active)
        state.setResolvedPreviewText("Active preview", for: active)
        state.setResolvedRedirectURL("https://resolved.example.com/stale", for: stale)
        state.setResolvedPreviewText("Stale preview", for: stale)

        state.pruneStaleResolvedSourceData(for: [active])

        XCTAssertTrue(state.hasResolvedRedirectURL(for: active))
        XCTAssertTrue(state.hasResolvedPreviewText(for: active))
        XCTAssertFalse(state.hasResolvedRedirectURL(for: stale))
        XCTAssertFalse(state.hasResolvedPreviewText(for: stale))
    }

    func testRenderPresentationUsesResolvedRedirectAndPreviewText() throws {
        let source = try XCTUnwrap(
            SearchSource(
                rawURL: "https://vertexaisearch.cloud.google.com/grounding-api-redirect?q=apple",
                title: "Apple",
                previewText: nil
            )
        )

        var state = SearchSourceEnrichmentState()
        state.setResolvedRedirectURL("https://www.apple.com/newsroom/", for: source)
        state.setResolvedPreviewText("Resolved preview", for: source)

        let presentation = state.renderPresentation(for: source)

        XCTAssertEqual(presentation.urlString, "https://www.apple.com/newsroom/")
        XCTAssertEqual(presentation.hostDisplay, "apple.com")
        XCTAssertTrue(presentation.previewText.contains("Resolved preview"))
        XCTAssertEqual(state.preferredURLStrings(for: [source]), ["https://www.apple.com/newsroom/"])
    }

    func testTaskKeySortsByCanonicalURLAndSnippetPresence() {
        let sourceA = SearchSource(
            rawURL: "https://b.example/path",
            title: nil,
            previewText: nil
        )
        let sourceB = SearchSource(
            rawURL: "https://a.example/path",
            title: nil,
            previewText: "snippet"
        )

        XCTAssertEqual(
            SearchSourceEnrichmentState.taskKey(for: [sourceA, sourceB].compactMap { $0 }),
            "https://a.example/path|1|https://b.example/path|0"
        )
    }

    func testTaskKeyIgnoresProviderSnippetContentAfterPresenceIsKnown() throws {
        let sourceWithShortSnippet = try XCTUnwrap(
            SearchSource(
                rawURL: "https://example.com/path",
                title: nil,
                previewText: "short"
            )
        )
        let sourceWithLongSnippet = try XCTUnwrap(
            SearchSource(
                rawURL: "https://example.com/path",
                title: nil,
                previewText: "longer provider snippet"
            )
        )

        XCTAssertEqual(
            SearchSourceEnrichmentState.taskKey(for: [sourceWithShortSnippet]),
            SearchSourceEnrichmentState.taskKey(for: [sourceWithLongSnippet])
        )
    }

    func testPreviewURLWaitsForResolvedRedirectOnlyForGoogleGroundingRedirects() throws {
        let webSource = try XCTUnwrap(SearchSource(rawURL: "https://example.com/page", title: nil, previewText: nil))
        let redirectSource = try XCTUnwrap(
            SearchSource(
                rawURL: "https://vertexaisearch.cloud.google.com/grounding-api-redirect?q=example",
                title: "example.com",
                previewText: nil
            )
        )

        var state = SearchSourceEnrichmentState()

        XCTAssertEqual(state.previewURL(for: webSource), "https://example.com/page")
        XCTAssertNil(state.previewURL(for: redirectSource))

        state.setResolvedRedirectURL("https://example.com/resolved", for: redirectSource)

        XCTAssertEqual(state.previewURL(for: redirectSource), "https://example.com/resolved")
    }

    func testSourcesNeedingRedirectResolutionOnlyIncludesUnresolvedGroundingRedirects() throws {
        let unresolvedRedirect = try XCTUnwrap(
            SearchSource(
                rawURL: "https://vertexaisearch.cloud.google.com/grounding-api-redirect?q=one",
                title: "one.example",
                previewText: nil
            )
        )
        let resolvedRedirect = try XCTUnwrap(
            SearchSource(
                rawURL: "https://vertexaisearch.cloud.google.com/grounding-api-redirect?q=two",
                title: "two.example",
                previewText: nil
            )
        )
        let directWebSource = try XCTUnwrap(SearchSource(rawURL: "https://example.com/page", title: nil, previewText: nil))

        var state = SearchSourceEnrichmentState()
        state.setResolvedRedirectURL("https://two.example/resolved", for: resolvedRedirect)

        XCTAssertEqual(state.sourcesNeedingRedirectResolution(from: [unresolvedRedirect, resolvedRedirect, directWebSource]), [unresolvedRedirect])
    }

    func testPreviewFetchRequestSkipsIneligibleSources() throws {
        let webSource = try XCTUnwrap(SearchSource(rawURL: "https://example.com/page", title: nil, previewText: nil))
        let fetchedSource = try XCTUnwrap(SearchSource(rawURL: "https://example.com/fetched", title: nil, previewText: nil))
        let mapsSource = try XCTUnwrap(
            SearchSource(
                rawURL: "https://maps.google.com/?q=Apple+Park",
                title: "Apple Park",
                previewText: nil,
                kind: .googleMaps
            )
        )
        let unresolvedRedirect = try XCTUnwrap(
            SearchSource(
                rawURL: "https://vertexaisearch.cloud.google.com/grounding-api-redirect?q=apple",
                title: "apple.com",
                previewText: nil
            )
        )

        var state = SearchSourceEnrichmentState()
        state.setResolvedPreviewText("Already fetched", for: fetchedSource)

        XCTAssertEqual(state.previewFetchRequest(for: webSource)?.urlString, "https://example.com/page")
        XCTAssertNil(state.previewFetchRequest(for: fetchedSource))
        XCTAssertNil(state.previewFetchRequest(for: mapsSource))
        XCTAssertNil(state.previewFetchRequest(for: unresolvedRedirect))

        state.setResolvedRedirectURL("https://www.apple.com/newsroom/", for: unresolvedRedirect)

        XCTAssertEqual(state.previewFetchRequest(for: unresolvedRedirect)?.urlString, "https://www.apple.com/newsroom/")
    }

    func testShouldStopPreviewFetchingUsesConfiguredLimit() {
        let state = SearchSourceEnrichmentState()

        XCTAssertFalse(state.shouldStopPreviewFetching(successfulFetchCount: SearchSourceEnrichmentState.previewFetchLimit - 1))
        XCTAssertTrue(state.shouldStopPreviewFetching(successfulFetchCount: SearchSourceEnrichmentState.previewFetchLimit))
    }
}
