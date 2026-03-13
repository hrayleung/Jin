import XCTest
@testable import Jin

final class GoogleGroundingSearchActivitiesTests: XCTestCase {
    func testEventsPreserveCaseSensitivePathVariants() {
        let grounding = GoogleGroundingSearchActivities.GroundingMetadata(
            webSearchQueries: nil,
            retrievalQueries: nil,
            groundingChunks: [
                .init(webURI: "https://example.com/Docs", webTitle: "Upper"),
                .init(webURI: "https://example.com/docs", webTitle: "Lower")
            ],
            groundingSupports: nil,
            searchEntryPoint: nil
        )

        let activities = sourceActivities(
            from: GoogleGroundingSearchActivities.events(
                from: grounding,
                searchPrefix: "search",
                openPrefix: "open",
                searchURLPrefix: "fallback"
            )
        )

        XCTAssertEqual(activities.count, 2)
        XCTAssertEqual(activities[0].arguments["url"]?.value as? String, "https://example.com/Docs")
        XCTAssertEqual(activities[0].arguments["title"]?.value as? String, "Upper")
        XCTAssertEqual(activities[1].arguments["url"]?.value as? String, "https://example.com/docs")
        XCTAssertEqual(activities[1].arguments["title"]?.value as? String, "Lower")
    }

    func testEventsMergeLaterTitleForDuplicateSourceURL() {
        let grounding = GoogleGroundingSearchActivities.GroundingMetadata(
            webSearchQueries: nil,
            retrievalQueries: nil,
            groundingChunks: [
                .init(webURI: "https://Example.com/docs", webTitle: nil),
                .init(webURI: "https://example.com/docs", webTitle: "Swift Docs")
            ],
            groundingSupports: nil,
            searchEntryPoint: nil
        )

        let activities = sourceActivities(
            from: GoogleGroundingSearchActivities.events(
                from: grounding,
                searchPrefix: "search",
                openPrefix: "open",
                searchURLPrefix: "fallback"
            )
        )

        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities[0].arguments["url"]?.value as? String, "https://Example.com/docs")
        XCTAssertEqual(activities[0].arguments["title"]?.value as? String, "Swift Docs")
    }

    func testEventsPreserveGoogleMapsSourceMetadata() {
        let grounding = GoogleGroundingSearchActivities.GroundingMetadata(
            webSearchQueries: ["best coffee"],
            retrievalQueries: nil,
            groundingChunks: [
                .init(
                    mapsURI: "https://maps.google.com/?cid=123",
                    mapsTitle: "Blue Bottle Coffee",
                    mapsPlaceId: "place-123"
                )
            ],
            groundingSupports: nil,
            searchEntryPoint: nil
        )

        let activities = sourceActivities(
            from: GoogleGroundingSearchActivities.events(
                from: grounding,
                searchPrefix: "search",
                openPrefix: "open",
                searchURLPrefix: "fallback"
            )
        )

        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities[0].arguments["url"]?.value as? String, "https://maps.google.com/?cid=123")
        XCTAssertEqual(activities[0].arguments["title"]?.value as? String, "Blue Bottle Coffee")
        XCTAssertEqual(activities[0].arguments["sourceKind"]?.value as? String, "google_maps")
        XCTAssertEqual(activities[0].arguments["mapsPlaceID"]?.value as? String, "place-123")
    }

    private func sourceActivities(from events: [StreamEvent]) -> [SearchActivity] {
        events.compactMap { event in
            guard case .searchActivity(let activity) = event, activity.type == "open_page" else {
                return nil
            }
            return activity
        }
    }
}
