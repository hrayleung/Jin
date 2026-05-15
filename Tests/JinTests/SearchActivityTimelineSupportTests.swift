import XCTest
@testable import Jin

final class SearchActivityTimelineSupportTests: XCTestCase {
    func testOrderedActivitiesSortsBySequenceThenOutputThenOriginalOffset() {
        let activities = [
            activity(id: "original-first", outputIndex: nil, sequenceNumber: nil),
            activity(id: "third", outputIndex: 1, sequenceNumber: 2),
            activity(id: "first", outputIndex: 2, sequenceNumber: 1),
            activity(id: "second", outputIndex: 3, sequenceNumber: 1),
            activity(id: "original-last", outputIndex: nil, sequenceNumber: nil)
        ]

        XCTAssertEqual(
            SearchActivityTimelineSupport.orderedActivities(activities).map(\.id),
            ["first", "second", "third", "original-first", "original-last"]
        )
    }

    func testBuildContentReportsRunningActivityForSearchingAndInProgressOnly() {
        XCTAssertTrue(
            SearchActivityTimelineSupport.buildContent(
                from: [
                    activity(id: "done", status: .completed),
                    activity(id: "searching", status: .searching)
                ]
            )
            .hasRunningActivity
        )
        XCTAssertTrue(
            SearchActivityTimelineSupport.buildContent(
                from: [
                    activity(id: "running", status: .inProgress)
                ]
            )
            .hasRunningActivity
        )
        XCTAssertFalse(
            SearchActivityTimelineSupport.buildContent(
                from: [
                    activity(id: "failed", status: .failed),
                    activity(id: "unknown", status: .unknown("queued"))
                ]
            )
            .hasRunningActivity
        )
    }

    func testRoutedContentSplitsMapsAndWebPanels() throws {
        let route = try XCTUnwrap(
            SearchActivityTimelineSupport.routedContent(
                from: [
                    activity(
                        id: "query",
                        type: "search",
                        arguments: ["query": AnyCodable("coffee near me")]
                    ),
                    sourceActivity(
                        id: "maps",
                        url: "https://maps.google.com/place/1",
                        sourceKind: "google_maps"
                    ),
                    sourceActivity(
                        id: "web",
                        url: "https://example.com/best-coffee",
                        sourceKind: nil
                    )
                ]
            )
        )

        XCTAssertTrue(route.showsMapsPanel)

        let webContent = try XCTUnwrap(route.webContent)
        XCTAssertEqual(webContent.presentation.sources.map(\.canonicalURLString), ["https://example.com/best-coffee"])
        XCTAssertTrue(webContent.presentation.queries.isEmpty)
    }

    func testRoutedContentKeepsQueryOnlySearchInWebPanel() throws {
        let route = try XCTUnwrap(
            SearchActivityTimelineSupport.routedContent(
                from: [
                    activity(
                        id: "query",
                        type: "search",
                        arguments: ["query": AnyCodable("weather today")]
                    )
                ]
            )
        )

        XCTAssertFalse(route.showsMapsPanel)
        XCTAssertEqual(route.webContent?.presentation.queries, ["weather today"])
    }

    func testRoutedContentOmitsWebPanelForMapsOnlySources() throws {
        let route = try XCTUnwrap(
            SearchActivityTimelineSupport.routedContent(
                from: [
                    sourceActivity(
                        id: "maps",
                        url: "https://maps.google.com/place/1",
                        sourceKind: "google_maps"
                    )
                ]
            )
        )

        XCTAssertTrue(route.showsMapsPanel)
        XCTAssertNil(route.webContent)
    }

    func testRoutedContentReturnsNilForEmptyActivities() {
        XCTAssertNil(SearchActivityTimelineSupport.routedContent(from: []))
    }

    func testPresentationDisplayKindsAndSummaryCopy() {
        let web = SearchActivityPresentation(
            activities: [sourceActivity(id: "web", url: "https://example.com", sourceKind: nil)]
        )
        XCTAssertEqual(web.displayKind, .web)
        XCTAssertEqual(web.sectionTitle, "Web Search")
        XCTAssertEqual(web.summarySystemImage, "magnifyingglass")
        XCTAssertEqual(web.sourceSummaryText, "Browsed 1 link")

        let maps = SearchActivityPresentation(
            activities: [sourceActivity(id: "maps", url: "https://maps.google.com/place/1", sourceKind: "google_maps")]
        )
        XCTAssertEqual(maps.displayKind, .maps)
        XCTAssertEqual(maps.sectionTitle, "Google Maps")
        XCTAssertEqual(maps.summarySystemImage, "map")
        XCTAssertEqual(maps.sourceSummaryText, "Cited 1 place source")

        let mixed = SearchActivityPresentation(
            activities: [
                sourceActivity(id: "web", url: "https://example.com", sourceKind: nil),
                sourceActivity(id: "maps", url: "https://maps.google.com/place/1", sourceKind: "google_maps")
            ]
        )
        XCTAssertEqual(mixed.displayKind, .mixed)
        XCTAssertEqual(mixed.sectionTitle, "Search & Maps")
        XCTAssertEqual(mixed.summarySystemImage, "map.circle")
        XCTAssertEqual(mixed.sourceSummaryText, "Browsed 2 grounded sources")

        let xOnly = SearchActivityPresentation(
            activities: [sourceActivity(id: "x", url: "https://x.com/jack/status/1", sourceKind: nil)]
        )
        XCTAssertEqual(xOnly.displayKind, .x)
        XCTAssertEqual(xOnly.sectionTitle, "X Search")
        XCTAssertEqual(xOnly.summarySystemImage, "at")
        XCTAssertEqual(xOnly.sourceSummaryText, "Browsed 1 link")

        let webAndX = SearchActivityPresentation(
            activities: [
                sourceActivity(id: "web", url: "https://example.com", sourceKind: nil),
                sourceActivity(id: "x", url: "https://twitter.com/jack/status/1", sourceKind: nil)
            ]
        )
        XCTAssertEqual(webAndX.displayKind, .webAndX)
        XCTAssertEqual(webAndX.sectionTitle, "Web + X")
        XCTAssertEqual(webAndX.summarySystemImage, "magnifyingglass")
        XCTAssertEqual(webAndX.sourceSummaryText, "Browsed 2 links")
    }

    func testMapsAndSearchActivityPredicatesMatchTimelineFiltering() {
        XCTAssertTrue(
            SearchActivityTimelineSupport.isMapsOpenPage(
                activity(
                    id: "maps-open",
                    type: "open_page",
                    arguments: ["sourceKind": AnyCodable(" google_maps ")]
                )
            )
        )
        XCTAssertFalse(
            SearchActivityTimelineSupport.isMapsOpenPage(
                activity(
                    id: "web-open",
                    type: "open_page",
                    arguments: ["sourceKind": AnyCodable("web")]
                )
            )
        )
        XCTAssertTrue(SearchActivityTimelineSupport.isSearchActivity(activity(id: "search", type: "search")))
        XCTAssertTrue(SearchActivityTimelineSupport.isSearchActivity(activity(id: "searching", type: "searching")))
        XCTAssertFalse(SearchActivityTimelineSupport.isSearchActivity(activity(id: "open", type: "open_page")))
    }

    func testContextLabelTrimsAndCombinesProviderAndModel() {
        XCTAssertEqual(
            SearchActivityTimelineSupport.contextLabel(providerLabel: " OpenAI ", modelLabel: "\nGPT-5"),
            "OpenAI / GPT-5"
        )
        XCTAssertEqual(
            SearchActivityTimelineSupport.contextLabel(providerLabel: " ", modelLabel: " GPT-5 "),
            "GPT-5"
        )
        XCTAssertNil(SearchActivityTimelineSupport.contextLabel(providerLabel: " OpenAI ", modelLabel: " "))
    }

    private func sourceActivity(
        id: String,
        url: String,
        sourceKind: String?
    ) -> SearchActivity {
        var arguments: [String: AnyCodable] = ["url": AnyCodable(url)]
        if let sourceKind {
            arguments["sourceKind"] = AnyCodable(sourceKind)
        }
        return activity(id: id, type: "open_page", arguments: arguments)
    }

    private func activity(
        id: String,
        type: String = "search",
        status: SearchActivityStatus = .completed,
        arguments: [String: AnyCodable] = [:],
        outputIndex: Int? = nil,
        sequenceNumber: Int? = nil
    ) -> SearchActivity {
        SearchActivity(
            id: id,
            type: type,
            status: status,
            arguments: arguments,
            outputIndex: outputIndex,
            sequenceNumber: sequenceNumber
        )
    }
}
