import XCTest
@testable import Jin

final class ChatStreamingHistoryPreparationTests: XCTestCase {
    func testPrepareHistoryPrefersPrebuiltMessagesOverSnapshots() {
        let prebuilt = [
            Message(role: .user, content: [.text("hello from cache")]),
            Message(role: .assistant, content: [.text("cached reply")])
        ]
        let ctx = makeContext(
            prebuiltHistory: prebuilt,
            messageSnapshots: [],
            systemPrompt: "You are helpful."
        )

        let history = ChatStreamingOrchestrator.prepareHistory(from: ctx)

        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history[0].role, .system)
        XCTAssertEqual(textContent(of: history[0]), "You are helpful.")
        XCTAssertEqual(textContent(of: history[1]), "hello from cache")
        XCTAssertEqual(textContent(of: history[2]), "cached reply")
    }

    func testPrepareHistoryFallsBackToSnapshotsWhenPrebuiltMissing() throws {
        let user = Message(role: .user, content: [.text("from snapshot")])
        let entity = try MessageEntity.fromDomain(user)
        let snapshot = PersistedMessageSnapshot(entity)
        let ctx = makeContext(
            prebuiltHistory: nil,
            messageSnapshots: [snapshot],
            systemPrompt: nil
        )

        let history = ChatStreamingOrchestrator.prepareHistory(from: ctx)

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].role, .user)
        XCTAssertEqual(textContent(of: history[0]), "from snapshot")
    }

    private func textContent(of message: Message) -> String? {
        guard case .text(let text)? = message.content.first else { return nil }
        return text
    }

    private func makeContext(
        prebuiltHistory: [Message]?,
        messageSnapshots: [PersistedMessageSnapshot],
        systemPrompt: String?
    ) -> ChatStreamingOrchestrator.SessionContext {
        ChatStreamingOrchestrator.SessionContext(
            conversationID: UUID(),
            diagnosticRunID: "test",
            providerID: "openai",
            providerConfig: nil,
            providerType: .openai,
            modelID: "gpt-test",
            modelNameSnapshot: "GPT Test",
            resolvedModelSettings: nil,
            messageSnapshots: messageSnapshots,
            prebuiltHistory: prebuiltHistory,
            systemPrompt: systemPrompt,
            controlsToUse: GenerationControls(),
            shouldTruncateMessages: false,
            maxHistoryMessages: nil,
            modelContextWindow: 128_000,
            reservedOutputTokens: 4_096,
            mcpServerConfigs: [],
            chatNamingTarget: nil,
            shouldOfferBuiltinSearch: false,
            triggeredByUserSend: true,
            networkLogContext: NetworkDebugLogContext(conversationID: UUID().uuidString)
        )
    }
}
