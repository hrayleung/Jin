import XCTest
@testable import Jin

final class ChatStreamingOrchestratorTests: XCTestCase {
    func testPrepareHistoryUsesOnlyMatchingThreadSnapshots() throws {
        let threadID = UUID()
        let otherThreadID = UUID()
        let matchingUser = try MessageEntity.fromDomain(
            Message(
                id: UUID(),
                role: .user,
                content: [.text("thread-a user")],
                timestamp: Date(timeIntervalSince1970: 1)
            )
        )
        matchingUser.contextThreadID = threadID

        let otherThreadMessage = try MessageEntity.fromDomain(
            Message(
                id: UUID(),
                role: .assistant,
                content: [.text("thread-b assistant")],
                timestamp: Date(timeIntervalSince1970: 2)
            )
        )
        otherThreadMessage.contextThreadID = otherThreadID

        let matchingAssistant = try MessageEntity.fromDomain(
            Message(
                id: UUID(),
                role: .assistant,
                content: [.text("thread-a assistant")],
                timestamp: Date(timeIntervalSince1970: 3)
            )
        )
        matchingAssistant.contextThreadID = threadID

        let context = ChatStreamingOrchestrator.SessionContext(
            conversationID: UUID(),
            threadID: threadID,
            turnID: nil,
            diagnosticRunID: "test-run-id",
            providerID: "provider",
            providerConfig: nil,
            providerType: nil,
            modelID: "model",
            modelNameSnapshot: "Model",
            resolvedModelSettings: nil,
            messageSnapshots: [
                PersistedMessageSnapshot(otherThreadMessage),
                PersistedMessageSnapshot(matchingAssistant),
                PersistedMessageSnapshot(matchingUser),
            ],
            systemPrompt: "system",
            controlsToUse: GenerationControls(),
            shouldTruncateMessages: false,
            maxHistoryMessages: nil,
            modelContextWindow: 4_096,
            reservedOutputTokens: 0,
            mcpServerConfigs: [],
            chatNamingTarget: nil,
            shouldOfferBuiltinSearch: false,
            triggeredByUserSend: false,
            networkLogContext: NetworkDebugLogContext()
        )

        let history = ChatStreamingOrchestrator.prepareHistory(from: context)
        XCTAssertEqual(history.map { $0.role }, [MessageRole.system, .user, .assistant])
        XCTAssertEqual(history.compactMap { message -> String? in
            guard case .text(let text) = message.content.first else { return nil }
            return text
        }, ["system", "thread-a user", "thread-a assistant"])
    }

    func testHasRenderableAssistantContentRequiresRenderablePayload() {
        XCTAssertFalse(
            ChatStreamingOrchestrator.hasRenderableAssistantContent(
                assistantPartCount: 0,
                searchActivityCount: 0,
                codeExecutionActivityCount: 0,
                codexToolActivityCount: 0
            )
        )
    }

    func testHasRenderableAssistantContentCountsNonTextAssistantOutputs() {
        XCTAssertTrue(
            ChatStreamingOrchestrator.hasRenderableAssistantContent(
                assistantPartCount: 0,
                searchActivityCount: 1,
                codeExecutionActivityCount: 0,
                codexToolActivityCount: 0
            )
        )
        XCTAssertTrue(
            ChatStreamingOrchestrator.hasRenderableAssistantContent(
                assistantPartCount: 0,
                searchActivityCount: 0,
                codeExecutionActivityCount: 1,
                codexToolActivityCount: 0
            )
        )
        XCTAssertTrue(
            ChatStreamingOrchestrator.hasRenderableAssistantContent(
                assistantPartCount: 0,
                searchActivityCount: 0,
                codeExecutionActivityCount: 0,
                codexToolActivityCount: 1
            )
        )
    }
}
