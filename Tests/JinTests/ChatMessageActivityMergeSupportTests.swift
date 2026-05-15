import XCTest
@testable import Jin

final class ChatMessageActivityMergeSupportTests: XCTestCase {
    func testMergedSearchActivitiesPreservesOrderAndMergesByID() throws {
        let existing = [
            SearchActivity(id: "search-1", type: "web_search", status: .searching, arguments: ["query": AnyCodable("swift")]),
            SearchActivity(id: "search-2", type: "web_search", status: .inProgress)
        ]
        let existingData = try JSONEncoder().encode(existing)

        let mergedData = ChatMessageActivityMergeSupport.mergedSearchActivities(
            existingData: existingData,
            newActivities: [
                SearchActivity(id: "search-1", type: "web_search", status: .completed, arguments: ["count": AnyCodable(3)]),
                SearchActivity(id: "search-3", type: "web_search", status: .searching)
            ]
        )

        let merged = try XCTUnwrap(mergedData).decodedSearchActivities()
        XCTAssertEqual(merged.map(\.id), ["search-1", "search-2", "search-3"])
        XCTAssertEqual(merged[0].status, .completed)
        XCTAssertEqual(merged[0].arguments["query"]?.value as? String, "swift")
        XCTAssertEqual(merged[0].arguments["count"]?.value as? Int, 3)
    }

    func testMergeReturnsNilForEmptyResult() {
        XCTAssertNil(ChatMessageActivityMergeSupport.mergedSearchActivities(existingData: nil, newActivities: []))
    }
}

private extension Data {
    func decodedSearchActivities() throws -> [SearchActivity] {
        try JSONDecoder().decode([SearchActivity].self, from: self)
    }
}
