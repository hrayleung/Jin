import XCTest
@testable import Jin

@MainActor
final class ConversationStreamingStoreTests: XCTestCase {
    func testThreadScopedSessionsCanCoexist() {
        let store = ConversationStreamingStore()
        let conversationID = UUID()
        let threadA = UUID()
        let threadB = UUID()

        let stateA = store.beginSession(conversationID: conversationID, threadID: threadA, modelLabel: "A")
        let stateB = store.beginSession(conversationID: conversationID, threadID: threadB, modelLabel: "B")

        XCTAssertTrue(store.isStreaming(conversationID: conversationID))
        XCTAssertTrue(store.isStreaming(conversationID: conversationID, threadID: threadA))
        XCTAssertTrue(store.isStreaming(conversationID: conversationID, threadID: threadB))
        XCTAssertTrue(stateA === store.streamingState(conversationID: conversationID, threadID: threadA))
        XCTAssertTrue(stateB === store.streamingState(conversationID: conversationID, threadID: threadB))
        XCTAssertEqual(store.streamingModelLabel(conversationID: conversationID, threadID: threadA), "A")
        XCTAssertEqual(store.streamingModelLabel(conversationID: conversationID, threadID: threadB), "B")
    }

    func testEndSessionForSingleThreadKeepsOtherThreadsRunning() {
        let store = ConversationStreamingStore()
        let conversationID = UUID()
        let threadA = UUID()
        let threadB = UUID()

        store.beginSession(conversationID: conversationID, threadID: threadA, modelLabel: "A")
        store.beginSession(conversationID: conversationID, threadID: threadB, modelLabel: "B")

        store.endSession(conversationID: conversationID, threadID: threadA)

        XCTAssertFalse(store.isStreaming(conversationID: conversationID, threadID: threadA))
        XCTAssertTrue(store.isStreaming(conversationID: conversationID, threadID: threadB))
        XCTAssertTrue(store.isStreaming(conversationID: conversationID))
    }
}

