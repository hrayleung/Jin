import XCTest
@testable import Jin

final class ChatMessageStageEquatableKeyTests: XCTestCase {
    func testSingleThreadKeyIgnoresComposerDraftText() {
        let conversationID = UUID()
        let messageID = UUID()
        let entityID = UUID()
        let expandedID = UUID()

        let first = ChatMessageStageEquatableKeyBuilder.singleThreadKey(
            conversationID: conversationID,
            conversationMessageCount: 1,
            containerSize: CGSize(width: 800, height: 600),
            messageIDs: [messageID],
            toolResultIDs: ["tool-1"],
            entityIDs: [entityID],
            assistantDisplayName: "Assistant",
            providerType: nil,
            providerIconID: nil,
            composerHeight: 120,
            isStreaming: false,
            streamingObjectID: nil,
            streamingModelLabel: nil,
            streamingModelID: nil,
            expandedCollapsedMessageIDs: [expandedID]
        )

        let second = ChatMessageStageEquatableKeyBuilder.singleThreadKey(
            conversationID: conversationID,
            conversationMessageCount: 1,
            containerSize: CGSize(width: 800, height: 600),
            messageIDs: [messageID],
            toolResultIDs: ["tool-1"],
            entityIDs: [entityID],
            assistantDisplayName: "Assistant",
            providerType: nil,
            providerIconID: nil,
            composerHeight: 120,
            isStreaming: false,
            streamingObjectID: nil,
            streamingModelLabel: nil,
            streamingModelID: nil,
            expandedCollapsedMessageIDs: [expandedID]
        )

        XCTAssertEqual(first, second)
    }

    func testSingleThreadKeyChangesForMessageAndLayoutChanges() {
        let conversationID = UUID()
        let messageID = UUID()

        let base = ChatMessageStageEquatableKeyBuilder.singleThreadKey(
            conversationID: conversationID,
            conversationMessageCount: 1,
            containerSize: CGSize(width: 800, height: 600),
            messageIDs: [messageID],
            toolResultIDs: [],
            entityIDs: [],
            assistantDisplayName: "Assistant",
            providerType: nil,
            providerIconID: nil,
            composerHeight: 80,
            isStreaming: false,
            streamingObjectID: nil,
            streamingModelLabel: nil,
            streamingModelID: nil,
            expandedCollapsedMessageIDs: []
        )

        let withNewMessage = ChatMessageStageEquatableKeyBuilder.singleThreadKey(
            conversationID: conversationID,
            conversationMessageCount: 2,
            containerSize: CGSize(width: 800, height: 600),
            messageIDs: [messageID, UUID()],
            toolResultIDs: [],
            entityIDs: [],
            assistantDisplayName: "Assistant",
            providerType: nil,
            providerIconID: nil,
            composerHeight: 80,
            isStreaming: false,
            streamingObjectID: nil,
            streamingModelLabel: nil,
            streamingModelID: nil,
            expandedCollapsedMessageIDs: []
        )

        let withComposerHeightChange = ChatMessageStageEquatableKeyBuilder.singleThreadKey(
            conversationID: conversationID,
            conversationMessageCount: 1,
            containerSize: CGSize(width: 800, height: 600),
            messageIDs: [messageID],
            toolResultIDs: [],
            entityIDs: [],
            assistantDisplayName: "Assistant",
            providerType: nil,
            providerIconID: nil,
            composerHeight: 140,
            isStreaming: false,
            streamingObjectID: nil,
            streamingModelLabel: nil,
            streamingModelID: nil,
            expandedCollapsedMessageIDs: []
        )

        XCTAssertNotEqual(base, withNewMessage)
        XCTAssertNotEqual(base, withComposerHeightChange)
    }
}
