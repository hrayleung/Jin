import Foundation
import XCTest
@testable import Jin

final class GoogleGroundingSearchSuggestionParserTests: XCTestCase {
    func testParseDecodesStandardBase64Blob() throws {
        let payload = [
            [
                "query": "swift 6 release",
                "url": "https://www.google.com/search?q=swift+6+release"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let blob = data.base64EncodedString()

        let suggestions = GoogleGroundingSearchSuggestionParser.parse(sdkBlob: blob)
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].query, "swift 6 release")
        XCTAssertEqual(suggestions[0].url, "https://www.google.com/search?q=swift+6+release")
    }

    func testParseDecodesURLSafeBlobWithoutPadding() throws {
        let payload = [
            "items": [
                [
                    "q": "swift actors",
                    "uri": "https://www.google.com/search?q=swift+actors"
                ]
            ]
        ] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let blob = data
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let suggestions = GoogleGroundingSearchSuggestionParser.parse(sdkBlob: blob)
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].query, "swift actors")
        XCTAssertEqual(suggestions[0].url, "https://www.google.com/search?q=swift+actors")
    }
}
