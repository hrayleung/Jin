import XCTest
@testable import Jin

@MainActor
final class ConversationStreamingStoreTests: XCTestCase {
    func testBeginSessionArmsIdleSessionWithoutActiveTask() {
        let store = ConversationStreamingStore()
        let conversationID = UUID()

        let state = store.beginSession(
            conversationID: conversationID,
            modelLabel: "demo",
            modelID: "demo-model"
        )

        XCTAssertTrue(store.isStreaming(conversationID: conversationID))
        XCTAssertFalse(store.hasActiveStreamingTask(conversationID: conversationID))
        XCTAssertTrue(state === store.streamingState(conversationID: conversationID))
        XCTAssertEqual(store.streamingModelLabel(conversationID: conversationID), "demo")
        XCTAssertEqual(store.streamingModelID(conversationID: conversationID), "demo-model")
    }

    func testBeginSessionUpgradesProvisionalLabels() {
        let store = ConversationStreamingStore()
        let conversationID = UUID()

        _ = store.beginSession(
            conversationID: conversationID,
            modelLabel: "provisional",
            modelID: "old-id"
        )
        _ = store.beginSession(
            conversationID: conversationID,
            modelLabel: "Final Name",
            modelID: "final-id"
        )

        XCTAssertEqual(store.streamingModelLabel(conversationID: conversationID), "Final Name")
        XCTAssertEqual(store.streamingModelID(conversationID: conversationID), "final-id")
    }

    func testCancelEndsArmedSessionWithoutTask() {
        let store = ConversationStreamingStore()
        let conversationID = UUID()

        _ = store.beginSession(conversationID: conversationID, modelLabel: nil, modelID: nil)
        XCTAssertTrue(store.isStreaming(conversationID: conversationID))

        store.cancel(conversationID: conversationID)

        XCTAssertFalse(store.isStreaming(conversationID: conversationID))
        XCTAssertNil(store.streamingState(conversationID: conversationID))
    }

    func testCancelWithActiveTaskDoesNotEndSessionImmediately() {
        let store = ConversationStreamingStore()
        let conversationID = UUID()

        _ = store.beginSession(conversationID: conversationID, modelLabel: nil, modelID: nil)
        let task = Task<Void, Never> {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        store.attachTask(task, conversationID: conversationID)
        XCTAssertTrue(store.hasActiveStreamingTask(conversationID: conversationID))

        store.cancel(conversationID: conversationID)

        // Cooperative cancel: session stays until orchestrator calls endSession.
        XCTAssertTrue(store.isStreaming(conversationID: conversationID))
        task.cancel()
        store.endSession(conversationID: conversationID)
        XCTAssertFalse(store.isStreaming(conversationID: conversationID))
    }

    func testHasActiveStreamingTaskTracksAttachTask() {
        let store = ConversationStreamingStore()
        let conversationID = UUID()

        _ = store.beginSession(conversationID: conversationID, modelLabel: nil, modelID: nil)
        XCTAssertFalse(store.hasActiveStreamingTask(conversationID: conversationID))

        let task = Task<Void, Never> {}
        store.attachTask(task, conversationID: conversationID)
        XCTAssertTrue(store.hasActiveStreamingTask(conversationID: conversationID))

        store.endSession(conversationID: conversationID)
        XCTAssertFalse(store.hasActiveStreamingTask(conversationID: conversationID))
    }
}
