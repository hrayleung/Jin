import XCTest
@testable import Jin

final class ChatThreadSupportTests: XCTestCase {

    // MARK: - panelThreads

    func testPanelThreadsReturnsOnlyThreadsWithMessages() throws {
        let (conversation, threads) = makeConversation(threadCount: 2)
        appendMessage(toConversation: conversation, threadID: threads[0].id)

        let panels = ChatThreadSupport.panelThreads(
            from: ChatThreadSupport.sortedThreads(in: conversation.modelThreads),
            allMessages: conversation.messages,
            activeThread: threads[0]
        )

        XCTAssertEqual(panels.map(\.id), [threads[0].id])
    }

    func testPanelThreadsExcludesNewlyToggledActiveThreadWithoutMessages() throws {
        let (conversation, threads) = makeConversation(threadCount: 2)
        appendMessage(toConversation: conversation, threadID: threads[0].id)

        // Simulate the user toggling the second tab — it becomes active but has
        // no messages of its own. Per Layer 1 of the multi-model refactor, this
        // should NOT promote the empty thread to a panel; the user sees the
        // populated thread until the new one receives its first message.
        let panels = ChatThreadSupport.panelThreads(
            from: ChatThreadSupport.sortedThreads(in: conversation.modelThreads),
            allMessages: conversation.messages,
            activeThread: threads[1]
        )

        XCTAssertEqual(panels.map(\.id), [threads[0].id])
    }

    func testPanelThreadsReturnsAllThreadsThatHaveMessages() throws {
        let (conversation, threads) = makeConversation(threadCount: 3)
        appendMessage(toConversation: conversation, threadID: threads[0].id)
        appendMessage(toConversation: conversation, threadID: threads[2].id)

        let panels = ChatThreadSupport.panelThreads(
            from: ChatThreadSupport.sortedThreads(in: conversation.modelThreads),
            allMessages: conversation.messages,
            activeThread: threads[2]
        )

        XCTAssertEqual(panels.map(\.id), [threads[0].id, threads[2].id])
    }

    func testPanelThreadsFallsBackToActiveThreadWhenNoMessagesExist() throws {
        let (conversation, threads) = makeConversation(threadCount: 2)

        let panels = ChatThreadSupport.panelThreads(
            from: ChatThreadSupport.sortedThreads(in: conversation.modelThreads),
            allMessages: conversation.messages,
            activeThread: threads[1]
        )

        XCTAssertEqual(panels.map(\.id), [threads[1].id])
    }

    func testPanelThreadsFallsBackToFirstThreadWhenActiveIsMissing() throws {
        let (conversation, threads) = makeConversation(threadCount: 2)

        let panels = ChatThreadSupport.panelThreads(
            from: ChatThreadSupport.sortedThreads(in: conversation.modelThreads),
            allMessages: conversation.messages,
            activeThread: nil
        )

        XCTAssertEqual(panels.map(\.id), [threads[0].id])
    }

    func testPanelThreadsIsEmptyWhenNoThreadsExist() {
        let panels = ChatThreadSupport.panelThreads(
            from: [],
            allMessages: [],
            activeThread: nil
        )

        XCTAssertTrue(panels.isEmpty)
    }

    // MARK: - Helpers

    private func makeConversation(
        threadCount: Int
    ) -> (ConversationEntity, [ConversationModelThreadEntity]) {
        let controlsData = (try? JSONEncoder().encode(GenerationControls())) ?? Data()
        let conversation = ConversationEntity(
            title: "Test",
            providerID: "openai",
            modelID: "gpt-5.2",
            modelConfigData: controlsData
        )

        let threads = (0..<threadCount).map { index in
            ConversationModelThreadEntity(
                providerID: "openai",
                modelID: "gpt-5.2",
                modelConfigData: controlsData,
                displayOrder: index,
                isSelected: true,
                isPrimary: index == 0
            )
        }

        for thread in threads {
            thread.conversation = conversation
            conversation.modelThreads.append(thread)
        }

        return (conversation, threads)
    }

    private func appendMessage(
        toConversation conversation: ConversationEntity,
        threadID: UUID
    ) {
        let contentData = (try? JSONEncoder().encode([ContentPart.text("hi")])) ?? Data()
        let message = MessageEntity(
            role: MessageRole.user.rawValue,
            contentData: contentData
        )
        message.contextThreadID = threadID
        message.conversation = conversation
        conversation.messages.append(message)
    }
}
