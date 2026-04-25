import XCTest
@testable import Jin

final class ChatRenderContextBatchBuilderTests: XCTestCase {
    func testMakeBatchReusesActiveContextAndBuildsSelectedThreadContexts() throws {
        let threadA = try makeThread(providerID: "openai", modelID: "gpt-5.2", displayOrder: 0)
        let threadB = try makeThread(providerID: "anthropic", modelID: "claude-sonnet-4-6", displayOrder: 1)
        let messages = try [
            makeMessage(role: .user, text: "Thread A prompt", threadID: threadA.id),
            makeMessage(role: .assistant, text: "Thread A response", threadID: threadA.id),
            makeMessage(role: .user, text: "Thread B prompt", threadID: threadB.id),
            makeMessage(role: .assistant, text: "Thread B response", threadID: threadB.id),
        ]
        let activeContext = ChatMessageRenderPipeline.makeRenderContext(
            from: ChatMessageRenderPipeline.orderedMessages(from: messages, threadID: threadA.id),
            fallbackModelLabel: "GPT",
            assistantProviderIconID: { _ in nil }
        )
        let expectedThreadBContext = ChatMessageRenderPipeline.makeRenderContext(
            from: ChatMessageRenderPipeline.orderedMessages(from: messages, threadID: threadB.id),
            fallbackModelLabel: "Claude",
            assistantProviderIconID: { _ in nil }
        )

        let batch = ChatRenderContextBatchBuilder.makeBatch(
            allMessages: messages,
            activeThreadID: threadA.id,
            selectedThreads: [threadA, threadB],
            activeContext: activeContext,
            modelNameForThread: { thread in
                thread.id == threadA.id ? "GPT" : "Claude"
            },
            assistantProviderIconID: { _ in nil }
        )

        XCTAssertEqual(batch.activeThreadID, threadA.id)
        XCTAssertEqual(batch.activeContext.visibleMessages.map(\.id), activeContext.visibleMessages.map(\.id))
        XCTAssertEqual(batch.contextsByThreadID[threadA.id]?.visibleMessages.map(\.id), activeContext.visibleMessages.map(\.id))
        XCTAssertEqual(batch.contextsByThreadID[threadB.id]?.visibleMessages.map(\.id), expectedThreadBContext.visibleMessages.map(\.id))
        XCTAssertEqual(batch.contextsByThreadID[threadB.id]?.historyMessages.count, expectedThreadBContext.historyMessages.count)
    }

    func testMakeBatchKeepsActiveContextWhenActiveThreadIsNotSelected() throws {
        let activeThreadID = UUID()
        let selectedThread = try makeThread(providerID: "openai", modelID: "gpt-5.2", displayOrder: 0)
        let messages = try [
            makeMessage(role: .assistant, text: "Active response", threadID: activeThreadID),
            makeMessage(role: .assistant, text: "Selected response", threadID: selectedThread.id),
        ]
        let activeContext = ChatMessageRenderPipeline.makeRenderContext(
            from: ChatMessageRenderPipeline.orderedMessages(from: messages, threadID: activeThreadID),
            fallbackModelLabel: "Active",
            assistantProviderIconID: { _ in nil }
        )

        let batch = ChatRenderContextBatchBuilder.makeBatch(
            allMessages: messages,
            activeThreadID: activeThreadID,
            selectedThreads: [selectedThread],
            activeContext: activeContext,
            modelNameForThread: { _ in "Selected" },
            assistantProviderIconID: { _ in nil }
        )

        XCTAssertEqual(batch.contextsByThreadID[activeThreadID]?.visibleMessages.map(\.id), activeContext.visibleMessages.map(\.id))
        XCTAssertNotNil(batch.contextsByThreadID[selectedThread.id])
    }

    private func makeThread(providerID: String, modelID: String, displayOrder: Int) throws -> ConversationModelThreadEntity {
        ConversationModelThreadEntity(
            providerID: providerID,
            modelID: modelID,
            modelConfigData: try JSONEncoder().encode(GenerationControls()),
            displayOrder: displayOrder
        )
    }

    private func makeMessage(role: MessageRole, text: String, threadID: UUID) throws -> MessageEntity {
        let entity = try MessageEntity.fromDomain(
            Message(
                id: UUID(),
                role: role,
                content: [.text(text)],
                timestamp: Date()
            )
        )
        entity.contextThreadID = threadID
        return entity
    }
}
