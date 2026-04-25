import XCTest
@testable import Jin

@MainActor
final class ChatUserTurnPersistenceTests: XCTestCase {
    func testAppendPreparedUserMessagesStoresThreadMetadataAndFallbackTitle() throws {
        let controlsData = try JSONEncoder().encode(GenerationControls())
        let conversation = ConversationEntity(
            title: "New Chat",
            providerID: "openai",
            modelID: "gpt-5.2",
            modelConfigData: controlsData
        )
        let toolThread = ConversationModelThreadEntity(
            providerID: "openai",
            modelID: "gpt-5.2",
            modelConfigData: controlsData
        )
        let plainThread = ConversationModelThreadEntity(
            providerID: "anthropic",
            modelID: "claude-sonnet-4-6",
            modelConfigData: controlsData
        )
        let askedAt = Date(timeIntervalSince1970: 1234)
        let turnID = UUID()
        let draft = ChatSendDraftSnapshot(
            messageText: "Summarize this",
            remoteVideoURLText: "",
            attachments: [],
            quotes: [],
            selectedPerMessageMCPServers: [(id: "server-1", name: "Filesystem")],
            askedAt: askedAt,
            turnID: turnID
        )
        var didPersistConversation = false
        var didRebuild = false

        ChatUserTurnPersistence.appendPreparedUserMessages(
            [
                ChatMessagePreparationSupport.ThreadPreparedUserMessage(
                    threadID: toolThread.id,
                    parts: [.text("Tool thread prompt")]
                ),
                ChatMessagePreparationSupport.ThreadPreparedUserMessage(
                    threadID: plainThread.id,
                    parts: [.text("Plain thread prompt")]
                )
            ],
            draft: draft,
            toolCapableThreadIDs: [toolThread.id],
            conversationEntity: conversation,
            isChatNamingPluginEnabled: false,
            persistConversationIfNeeded: { didPersistConversation = true },
            makeConversationTitle: { "Title: \($0)" },
            rebuildMessageCaches: { didRebuild = true }
        )

        XCTAssertTrue(didPersistConversation)
        XCTAssertTrue(didRebuild)
        XCTAssertEqual(conversation.title, "Title: Summarize this")
        XCTAssertEqual(conversation.updatedAt, askedAt)
        XCTAssertEqual(conversation.messages.count, 2)
        XCTAssertEqual(conversation.messages.map(\.contextThreadID), [toolThread.id, plainThread.id])
        XCTAssertEqual(conversation.messages.map(\.turnID), [turnID, turnID])

        let decoder = JSONDecoder()
        let toolServerIDs = try XCTUnwrap(conversation.messages[0].perMessageMCPServerIDsData)
        let toolServerNames = try XCTUnwrap(conversation.messages[0].perMessageMCPServerNamesData)
        XCTAssertEqual(try decoder.decode([String].self, from: toolServerIDs), ["server-1"])
        XCTAssertEqual(try decoder.decode([String].self, from: toolServerNames), ["Filesystem"])
        XCTAssertNil(conversation.messages[1].perMessageMCPServerIDsData)
        XCTAssertNil(conversation.messages[1].perMessageMCPServerNamesData)
    }
}
