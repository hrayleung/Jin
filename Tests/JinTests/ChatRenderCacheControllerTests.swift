import XCTest
@testable import Jin

@MainActor
final class ChatRenderCacheControllerTests: XCTestCase {
    func testRebuildAppliesActiveAndSelectedThreadContexts() throws {
        let controller = ChatRenderCacheController()
        let threadA = try makeThread(providerID: "openai", modelID: "gpt-5.2", displayOrder: 0)
        let threadB = try makeThread(providerID: "anthropic", modelID: "claude-sonnet-4-6", displayOrder: 1)
        let updatedAt = Date()
        let messages = try [
            makeMessage(role: .user, text: "Thread A prompt", threadID: threadA.id),
            makeMessage(role: .assistant, text: "Thread A response", threadID: threadA.id),
            makeMessage(role: .user, text: "Thread B prompt", threadID: threadB.id),
            makeMessage(role: .assistant, text: "Thread B response", threadID: threadB.id),
        ]
        let ordered = ChatMessageRenderPipeline.orderedMessages(from: messages, threadID: threadA.id)

        controller.rebuild(
            request: ChatRenderCacheRebuildRequest(
                conversationID: UUID(),
                activeThreadID: threadA.id,
                allMessages: messages,
                orderedMessages: ordered,
                selectedThreads: [threadA, threadB],
                updatedAt: updatedAt,
                fallbackModelLabel: "GPT",
                providerIconsByID: [:]
            ),
            modelNameForThread: { thread in thread.id == threadA.id ? "GPT" : "Claude" },
            assistantProviderIconID: { _ in nil },
            isStillCurrent: { _, _, _ in true },
            onContextApplied: {},
            onHistoryReady: {}
        )

        XCTAssertEqual(controller.version, 1)
        XCTAssertEqual(controller.visibleMessages.map(\.id), ordered.map(\.id))
        XCTAssertEqual(controller.contextsByThreadID[threadA.id]?.visibleMessages.map(\.id), controller.visibleMessages.map(\.id))
        XCTAssertEqual(controller.contextsByThreadID[threadB.id]?.visibleMessages.count, 2)
        XCTAssertTrue(controller.isHistoryReady)
    }

    func testRebuildIfNeededSkipsUnchangedConversationSnapshot() throws {
        let controller = ChatRenderCacheController()
        let thread = try makeThread(providerID: "openai", modelID: "gpt-5.2", displayOrder: 0)
        let updatedAt = Date()
        let messages = try [
            makeMessage(role: .user, text: "Prompt", threadID: thread.id),
            makeMessage(role: .assistant, text: "Response", threadID: thread.id),
        ]
        let request = ChatRenderCacheRebuildRequest(
            conversationID: UUID(),
            activeThreadID: thread.id,
            allMessages: messages,
            orderedMessages: ChatMessageRenderPipeline.orderedMessages(from: messages, threadID: thread.id),
            selectedThreads: [thread],
            updatedAt: updatedAt,
            fallbackModelLabel: "GPT",
            providerIconsByID: [:]
        )

        controller.rebuild(
            request: request,
            modelNameForThread: { _ in "GPT" },
            assistantProviderIconID: { _ in nil },
            isStillCurrent: { _, _, _ in true },
            onContextApplied: {},
            onHistoryReady: {}
        )
        controller.rebuildIfNeeded(
            request: request,
            modelNameForThread: { _ in "GPT" },
            assistantProviderIconID: { _ in nil },
            isStillCurrent: { _, _, _ in true },
            onContextApplied: {},
            onHistoryReady: {}
        )

        XCTAssertEqual(controller.version, 1)
    }

    func testClearForConversationSwitchCancelsAndClearsCache() throws {
        let controller = ChatRenderCacheController()
        let thread = try makeThread(providerID: "openai", modelID: "gpt-5.2", displayOrder: 0)
        let messages = try [makeMessage(role: .assistant, text: "Response", threadID: thread.id)]

        controller.rebuild(
            request: ChatRenderCacheRebuildRequest(
                conversationID: UUID(),
                activeThreadID: thread.id,
                allMessages: messages,
                orderedMessages: messages,
                selectedThreads: [thread],
                updatedAt: Date(),
                fallbackModelLabel: "GPT",
                providerIconsByID: [:]
            ),
            modelNameForThread: { _ in "GPT" },
            assistantProviderIconID: { _ in nil },
            isStillCurrent: { _, _, _ in true },
            onContextApplied: {},
            onHistoryReady: {}
        )

        controller.clearForConversationSwitch()

        XCTAssertEqual(controller.version, 2)
        XCTAssertTrue(controller.visibleMessages.isEmpty)
        XCTAssertTrue(controller.contextsByThreadID.isEmpty)
        XCTAssertTrue(controller.isHistoryReady)
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
