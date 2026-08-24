import XCTest
@testable import Jin

@MainActor
final class ChatTimelineSurvivingRowReloadSupportTests: XCTestCase {
    func testSendAppendDoesNotReloadEarlierRows() {
        let user = TimelineRowFixtures.item(role: "user", text: "Question")
        let assistant = TimelineRowFixtures.item(role: "assistant", text: "Answer")
        let followUp = TimelineRowFixtures.item(role: "user", text: "Next")
        let old: [ChatTimelineRow] = [
            .message(user, index: 0),
            .message(assistant, index: 1),
        ]
        let new: [ChatTimelineRow] = [
            .message(user, index: 0),
            .message(assistant, index: 1),
            .message(followUp, index: 2),
            .streaming(StreamingMessageState()),
        ]

        let identities = ChatTimelineSurvivingRowReloadSupport.identitiesNeedingReload(
            old: old,
            new: new,
            previousEditingUserMessageID: nil,
            newEditingUserMessageID: nil
        )
        XCTAssertTrue(identities.isEmpty)
    }

    func testEditAndTruncateReloadsTheRewrittenUserRow() {
        let userID = UUID()
        let original = makeUserItem(id: userID, text: "Original")
        let edited = makeUserItem(id: userID, text: "Edited")
        let assistant = TimelineRowFixtures.item(role: "assistant", text: "Answer")
        let old: [ChatTimelineRow] = [
            .message(original, index: 0),
            .message(assistant, index: 1),
        ]
        let new: [ChatTimelineRow] = [
            .message(edited, index: 0),
            .streaming(StreamingMessageState()),
        ]

        let identities = ChatTimelineSurvivingRowReloadSupport.identitiesNeedingReload(
            old: old,
            new: new,
            previousEditingUserMessageID: userID,
            newEditingUserMessageID: nil
        )
        XCTAssertEqual(identities, ["msg-\(userID.uuidString)"])
    }

    func testLeavingEditModeReloadsEvenWhenCopyTextIsUnchanged() {
        let userID = UUID()
        let item = makeUserItem(id: userID, text: "Same")
        XCTAssertTrue(
            ChatTimelineSurvivingRowReloadSupport.shouldReload(
                previous: item,
                current: item,
                previousEditingUserMessageID: userID,
                newEditingUserMessageID: nil
            )
        )
    }

    func testUnrelatedSurvivorsStayPut() {
        let earlier = TimelineRowFixtures.item(role: "user", text: "Earlier")
        let userID = UUID()
        let original = makeUserItem(id: userID, text: "Original")
        let edited = makeUserItem(id: userID, text: "Edited")
        let assistant = TimelineRowFixtures.item(role: "assistant", text: "Answer")
        let old: [ChatTimelineRow] = [
            .message(earlier, index: 0),
            .message(original, index: 1),
            .message(assistant, index: 2),
        ]
        let new: [ChatTimelineRow] = [
            .message(earlier, index: 0),
            .message(edited, index: 1),
        ]

        let identities = ChatTimelineSurvivingRowReloadSupport.identitiesNeedingReload(
            old: old,
            new: new,
            previousEditingUserMessageID: userID,
            newEditingUserMessageID: nil
        )
        XCTAssertEqual(identities, ["msg-\(userID.uuidString)"])
        XCTAssertFalse(identities.contains("msg-\(earlier.id.uuidString)"))
    }

    func testStreamingFinishReloadsThePersistedActivityOwner() {
        let user = TimelineRowFixtures.item(role: "user", text: "Question")
        let assistant = TimelineRowFixtures.item(role: "assistant", text: "Answer")
        let old: [ChatTimelineRow] = [
            .message(user, index: 0),
            .message(assistant, index: 1),
            .streaming(StreamingMessageState()),
        ]
        let newRows: [ChatTimelineRow] = [
            .message(user, index: 0),
            .message(assistant, index: 1),
        ]

        let identities = ChatTimelineSurvivingRowReloadSupport.identitiesNeedingReload(
            old: old,
            new: newRows,
            previousEditingUserMessageID: nil,
            newEditingUserMessageID: nil,
            previousStreamingActivityOwnerMessageID: assistant.id,
            newStreamingActivityOwnerMessageID: nil
        )
        XCTAssertEqual(identities, ["msg-\(assistant.id.uuidString)"])
        XCTAssertFalse(identities.contains("msg-\(user.id.uuidString)"))
    }

    func testUnchangedActivityOwnerDoesNotReloadSurvivors() {
        let user = TimelineRowFixtures.item(role: "user", text: "Question")
        let assistant = TimelineRowFixtures.item(role: "assistant", text: "Answer")
        let old: [ChatTimelineRow] = [
            .message(user, index: 0),
            .message(assistant, index: 1),
        ]
        let newRows: [ChatTimelineRow] = [
            .message(user, index: 0),
            .message(assistant, index: 1),
            .streaming(StreamingMessageState()),
        ]

        let identities = ChatTimelineSurvivingRowReloadSupport.identitiesNeedingReload(
            old: old,
            new: newRows,
            previousEditingUserMessageID: nil,
            newEditingUserMessageID: nil,
            previousStreamingActivityOwnerMessageID: assistant.id,
            newStreamingActivityOwnerMessageID: assistant.id
        )
        XCTAssertTrue(identities.isEmpty)
    }

    private func makeUserItem(id: UUID, text: String) -> MessageRenderItem {
        MessageRenderItem(
            id: id,
            role: MessageRole.user.rawValue,
            timestamp: Date(timeIntervalSince1970: 1),
            renderedBlocks: [.content(anchorID: "text-0", part: .text(text))],
            toolCalls: [],
            searchActivities: [],
            codeExecutionActivities: [],
            assistantModelLabel: nil,
            assistantProviderIconID: nil,
            responseMetrics: nil,
            copyText: text,
            preferredRenderMode: .fullWeb,
            isMemoryIntensiveAssistantContent: false,
            collapsedPreview: nil,
            canEditUserMessage: true,
            canDeleteResponse: false,
            perMessageMCPServerNames: []
        )
    }
}
