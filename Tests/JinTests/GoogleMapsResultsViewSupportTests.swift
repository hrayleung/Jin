import XCTest
@testable import Jin

final class GoogleMapsResultsViewSupportTests: XCTestCase {
    func testExtractContentSortsActivitiesAndDeduplicatesQueriesAndPlaces() {
        let view = GoogleMapsResultsView(
            activities: [
                activity(
                    id: "place-2",
                    type: "open_page",
                    status: .completed,
                    arguments: [
                        "sourceKind": AnyCodable("google_maps"),
                        "url": AnyCodable("https://maps.example/coffee"),
                        "title": AnyCodable("Coffee Bar"),
                    ],
                    outputIndex: 2,
                    sequenceNumber: 2
                ),
                activity(
                    id: "search-1",
                    type: "search",
                    status: .searching,
                    arguments: [
                        "query": AnyCodable(" Coffee near me "),
                        "queries": AnyCodable(["Coffee near me", "Tea"]),
                    ],
                    outputIndex: 0,
                    sequenceNumber: 1
                ),
                activity(
                    id: "place-1",
                    type: "open_page",
                    status: .completed,
                    arguments: [
                        "sourceKind": AnyCodable("google_maps"),
                        "url": AnyCodable(" https://maps.example/tea "),
                        "title": AnyCodable(" Tea House "),
                        "mapsPlaceID": AnyCodable("place-tea"),
                    ],
                    outputIndex: 1,
                    sequenceNumber: 2
                ),
                activity(
                    id: "place-duplicate",
                    type: "open_page",
                    status: .completed,
                    arguments: [
                        "sourceKind": AnyCodable("google_maps"),
                        "url": AnyCodable("HTTPS://MAPS.EXAMPLE/TEA"),
                        "title": AnyCodable("Ignored Duplicate"),
                    ],
                    outputIndex: 3,
                    sequenceNumber: 2
                ),
            ],
            isStreaming: true,
            providerLabel: nil,
            modelLabel: nil
        )

        let content = view.extractContent()

        XCTAssertEqual(content.queries, ["Coffee near me", "Tea"])
        XCTAssertEqual(content.places.map(\.name), ["Tea House", "Coffee Bar"])
        XCTAssertEqual(content.places.first?.placeID, "place-tea")
        XCTAssertTrue(content.hasRunningActivity)
    }

    func testExtractContentIgnoresNonMapsOpenPageActivities() {
        let view = GoogleMapsResultsView(
            activities: [
                activity(
                    id: "web",
                    type: "open_page",
                    status: .completed,
                    arguments: [
                        "sourceKind": AnyCodable("web"),
                        "url": AnyCodable("https://example.com"),
                        "title": AnyCodable("Example"),
                    ]
                ),
            ],
            isStreaming: false,
            providerLabel: nil,
            modelLabel: nil
        )

        let content = view.extractContent()

        XCTAssertTrue(content.queries.isEmpty)
        XCTAssertTrue(content.places.isEmpty)
        XCTAssertFalse(content.hasRunningActivity)
    }

    func testContextLabelTrimsProviderAndModel() {
        XCTAssertEqual(
            GoogleMapsResultsView(
                activities: [],
                isStreaming: false,
                providerLabel: " Gemini ",
                modelLabel: "\n2.5 Pro "
            ).contextLabel,
            "Gemini / 2.5 Pro"
        )
        XCTAssertEqual(
            GoogleMapsResultsView(
                activities: [],
                isStreaming: false,
                providerLabel: " ",
                modelLabel: " gemini "
            ).contextLabel,
            "gemini"
        )
    }

    private func activity(
        id: String,
        type: String,
        status: SearchActivityStatus,
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
