import XCTest
@testable import Jin

final class SearchSourceEnrichmentResolverTests: XCTestCase {
    func testResolvePrunesStaleDataAndUsesResolvedRedirectForPreviewFetch() async throws {
        let staleSource = try XCTUnwrap(
            SearchSource(rawURL: "https://example.com/stale", title: nil, previewText: nil)
        )
        let redirectSource = try XCTUnwrap(
            SearchSource(
                rawURL: "https://vertexaisearch.cloud.google.com/grounding-api-redirect?q=apple",
                title: "apple.com",
                previewText: nil
            )
        )

        var initialState = SearchSourceEnrichmentState()
        initialState.setResolvedRedirectURL("https://stale.example.com", for: staleSource)
        initialState.setResolvedPreviewText("Stale preview", for: staleSource)

        var previewRequests: [String] = []
        let resolver = SearchSourceEnrichmentResolver(
            redirectURL: { rawURL in
                XCTAssertEqual(rawURL, redirectSource.canonicalURLString)
                return "https://www.apple.com/newsroom/"
            },
            previewText: { rawURL in
                previewRequests.append(rawURL)
                return "Resolved preview"
            }
        )

        let state = await resolver.resolve(
            sources: [redirectSource],
            state: initialState
        )

        XCTAssertTrue(state.hasResolvedRedirectURL(for: redirectSource))
        XCTAssertTrue(state.hasResolvedPreviewText(for: redirectSource))
        XCTAssertFalse(state.hasResolvedRedirectURL(for: staleSource))
        XCTAssertFalse(state.hasResolvedPreviewText(for: staleSource))
        XCTAssertEqual(previewRequests, ["https://www.apple.com/newsroom/"])
    }

    func testResolveSkipsAlreadyResolvedRedirectsAndPreviewText() async throws {
        let source = try XCTUnwrap(
            SearchSource(
                rawURL: "https://vertexaisearch.cloud.google.com/grounding-api-redirect?q=swift",
                title: "developer.apple.com",
                previewText: nil
            )
        )

        var initialState = SearchSourceEnrichmentState()
        initialState.setResolvedRedirectURL("https://developer.apple.com/documentation/swift", for: source)
        initialState.setResolvedPreviewText("Existing preview", for: source)

        var redirectCallCount = 0
        var previewCallCount = 0
        let resolver = SearchSourceEnrichmentResolver(
            redirectURL: { _ in
                redirectCallCount += 1
                return nil
            },
            previewText: { _ in
                previewCallCount += 1
                return nil
            }
        )

        let state = await resolver.resolve(
            sources: [source],
            state: initialState
        )

        XCTAssertEqual(redirectCallCount, 0)
        XCTAssertEqual(previewCallCount, 0)
        XCTAssertEqual(state, initialState)
    }

    func testResolveStopsPreviewFetchingAtSuccessfulFetchLimit() async throws {
        let sources = try (0...SearchSourceEnrichmentState.previewFetchLimit).map { index in
            try XCTUnwrap(
                SearchSource(
                    rawURL: "https://example.com/page-\(index)",
                    title: nil,
                    previewText: nil
                )
            )
        }

        var previewRequests: [String] = []
        let resolver = SearchSourceEnrichmentResolver(
            redirectURL: { _ in nil },
            previewText: { rawURL in
                previewRequests.append(rawURL)
                return "Preview for \(rawURL)"
            }
        )

        let state = await resolver.resolve(
            sources: sources,
            state: SearchSourceEnrichmentState()
        )

        XCTAssertEqual(previewRequests.count, SearchSourceEnrichmentState.previewFetchLimit)
        XCTAssertTrue(state.hasResolvedPreviewText(for: sources[SearchSourceEnrichmentState.previewFetchLimit - 1]))
        XCTAssertFalse(state.hasResolvedPreviewText(for: sources[SearchSourceEnrichmentState.previewFetchLimit]))
    }

    func testResolveDoesNotCountFailedPreviewFetchesAgainstSuccessfulFetchLimit() async throws {
        let sources = try (0...SearchSourceEnrichmentState.previewFetchLimit).map { index in
            try XCTUnwrap(
                SearchSource(
                    rawURL: "https://example.com/page-\(index)",
                    title: nil,
                    previewText: nil
                )
            )
        }

        var previewRequests: [String] = []
        let resolver = SearchSourceEnrichmentResolver(
            redirectURL: { _ in nil },
            previewText: { rawURL in
                previewRequests.append(rawURL)
                return rawURL.hasSuffix("page-0") ? nil : "Preview for \(rawURL)"
            }
        )

        let state = await resolver.resolve(
            sources: sources,
            state: SearchSourceEnrichmentState()
        )

        XCTAssertEqual(previewRequests.count, SearchSourceEnrichmentState.previewFetchLimit + 1)
        XCTAssertFalse(state.hasResolvedPreviewText(for: sources[0]))
        XCTAssertTrue(state.hasResolvedPreviewText(for: sources[SearchSourceEnrichmentState.previewFetchLimit]))
    }
}
