import Foundation
import XCTest
@testable import Jin

final class GoogleGenerateContentResponseTests: XCTestCase {
    func testMapsGroundingMetadataDecodesGoogleMapsURIAndReviewSnippets() throws {
        let json = """
        {
          "groundingMetadata": {
            "groundingChunks": [
              {
                "maps": {
                  "googleMapsUri": "https://maps.google.com/place",
                  "title": "Blue Bottle Coffee",
                  "placeId": "places/place-123",
                  "placeAnswerSources": {
                    "reviewSnippets": [
                      {
                        "reviewId": "review-1",
                        "googleMapsUri": "https://maps.google.com/review-1",
                        "title": "Great espresso"
                      }
                    ]
                  }
                }
              }
            ]
          }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response = try decoder.decode(GoogleGenerateContentResponse.self, from: data)
        let grounding = try XCTUnwrap(response.groundingMetadata)
        let shared = GeminiModelConstants.toSharedGrounding(grounding)
        let events = GoogleGroundingSearchActivities.events(
            from: shared,
            searchPrefix: "search",
            openPrefix: "open",
            searchURLPrefix: "fallback"
        )
        let activities = events.compactMap { event -> SearchActivity? in
            guard case .searchActivity(let activity) = event, activity.type == "open_page" else {
                return nil
            }
            return activity
        }

        XCTAssertEqual(activities.count, 2)
        XCTAssertEqual(activities[0].arguments["url"]?.value as? String, "https://maps.google.com/place")
        XCTAssertEqual(activities[0].arguments["mapsPlaceID"]?.value as? String, "places/place-123")
        XCTAssertEqual(activities[0].arguments["mapsReviewSnippets"]?.value as? [String], ["Great espresso"])
        XCTAssertEqual(activities[1].arguments["url"]?.value as? String, "https://maps.google.com/review-1")
        XCTAssertEqual(activities[1].arguments["mapsReviewID"]?.value as? String, "review-1")
    }
}
