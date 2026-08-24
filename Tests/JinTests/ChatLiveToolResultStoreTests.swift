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

    func testTimelinePresentationIgnoresRedundantWrites() {
        let store = ChatLiveToolResultStore()
        let owner = UUID()
        store.applyTimelinePresentation(
            isConversationStreaming: true,
            activityOwnerMessageID: owner,
            suppressIdleStreamingPlaceholder: true
        )
        XCTAssertTrue(store.isConversationStreaming)
        XCTAssertEqual(store.streamingActivityOwnerMessageID, owner)
        XCTAssertTrue(store.suppressIdleStreamingPlaceholder)

        store.applyTimelinePresentation(
            isConversationStreaming: true,
            activityOwnerMessageID: owner,
            suppressIdleStreamingPlaceholder: true
        )
        XCTAssertEqual(store.streamingActivityOwnerMessageID, owner)

        store.applyTimelinePresentation(
            isConversationStreaming: false,
            activityOwnerMessageID: nil,
            suppressIdleStreamingPlaceholder: false
        )
        XCTAssertFalse(store.isConversationStreaming)
        XCTAssertNil(store.streamingActivityOwnerMessageID)
        XCTAssertFalse(store.suppressIdleStreamingPlaceholder)
    }

    func testClearEmptiesResults() {
        let store = ChatLiveToolResultStore()
        store.upsert(ToolResult(toolCallID: "c1", toolName: "lookup", content: "x", isError: false))
        store.clear()
        XCTAssertTrue(store.resultsByCallID.isEmpty)
    }
}
