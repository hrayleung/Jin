import XCTest
@testable import Jin

@MainActor
final class ChatLiveToolResultStoreTests: XCTestCase {
    func testUpsertReplacesSameCallID() {
        let store = ChatLiveToolResultStore()
        store.upsert(
            ToolResult(toolCallID: "c1", toolName: "lookup", content: "partial", isError: false)
        )
        store.upsert(
            ToolResult(toolCallID: "c1", toolName: "lookup", content: "final", isError: false)
        )

        XCTAssertEqual(store.resultsByCallID["c1"]?.content, "final")
        XCTAssertEqual(store.resultsByCallID.count, 1)
    }

    func testReplaceAllIsNoOpWhenEqual() {
        let store = ChatLiveToolResultStore()
        let result = ToolResult(toolCallID: "c1", toolName: "lookup", content: "done", isError: false)
        store.replaceAll(["c1": result])
        let before = store.resultsByCallID
        store.replaceAll(["c1": result])
        XCTAssertEqual(store.resultsByCallID, before)
    }

    func testSuppressFlagIgnoresRedundantWrites() {
        let store = ChatLiveToolResultStore()
        XCTAssertFalse(store.suppressIdleStreamingPlaceholder)
        store.setSuppressIdleStreamingPlaceholder(true)
        XCTAssertTrue(store.suppressIdleStreamingPlaceholder)
        store.setSuppressIdleStreamingPlaceholder(true)
        XCTAssertTrue(store.suppressIdleStreamingPlaceholder)
        store.setSuppressIdleStreamingPlaceholder(false)
        XCTAssertFalse(store.suppressIdleStreamingPlaceholder)
    }

    func testClearEmptiesResults() {
        let store = ChatLiveToolResultStore()
        store.upsert(ToolResult(toolCallID: "c1", toolName: "lookup", content: "x", isError: false))
        store.clear()
        XCTAssertTrue(store.resultsByCallID.isEmpty)
    }
}
