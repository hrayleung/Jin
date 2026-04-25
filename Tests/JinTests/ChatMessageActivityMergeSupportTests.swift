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

    func testMergedAgentToolActivitiesPreservesOrderAndMergesByID() throws {
        let existing = [
            CodexToolActivity(id: "tool-1", toolName: "read", status: .running, arguments: ["path": AnyCodable("A.swift")]),
            CodexToolActivity(id: "tool-2", toolName: "write", status: .running)
        ]
        let existingData = try JSONEncoder().encode(existing)

        let mergedData = ChatMessageActivityMergeSupport.mergedAgentToolActivities(
            existingData: existingData,
            newActivities: [
                CodexToolActivity(id: "tool-1", toolName: "read", status: .completed, output: "ok"),
                CodexToolActivity(id: "tool-3", toolName: "grep", status: .running)
            ]
        )

        let merged = try XCTUnwrap(mergedData).decodedCodexToolActivities()
        XCTAssertEqual(merged.map(\.id), ["tool-1", "tool-2", "tool-3"])
        XCTAssertEqual(merged[0].status, .completed)
        XCTAssertEqual(merged[0].arguments["path"]?.value as? String, "A.swift")
        XCTAssertEqual(merged[0].output, "ok")
    }

    func testMergeReturnsNilForEmptyResult() {
        XCTAssertNil(ChatMessageActivityMergeSupport.mergedSearchActivities(existingData: nil, newActivities: []))
        XCTAssertNil(ChatMessageActivityMergeSupport.mergedAgentToolActivities(existingData: nil, newActivities: []))
    }
}

private extension Data {
    func decodedSearchActivities() throws -> [SearchActivity] {
        try JSONDecoder().decode([SearchActivity].self, from: self)
    }

    func decodedCodexToolActivities() throws -> [CodexToolActivity] {
        try JSONDecoder().decode([CodexToolActivity].self, from: self)
    }
}
