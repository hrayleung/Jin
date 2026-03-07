import XCTest
@testable import Jin

final class ConversationModelThreadEntityTests: XCTestCase {
    func testConversationToDomainUsesActiveThreadModelConfigWhenAvailable() throws {
        let legacyControls = GenerationControls(maxTokens: 111)
        let activeControls = GenerationControls(maxTokens: 222)

        let conversation = ConversationEntity(
            title: "Threaded Chat",
            providerID: "openai",
            modelID: "gpt-5.2",
            modelConfigData: try JSONEncoder().encode(legacyControls)
        )

        let activeThread = ConversationModelThreadEntity(
            providerID: "anthropic",
            modelID: "claude-sonnet-4-6",
            modelConfigData: try JSONEncoder().encode(activeControls),
            displayOrder: 0
        )
        activeThread.conversation = conversation
        conversation.modelThreads.append(activeThread)
        conversation.activeThreadID = activeThread.id

        let domain = try conversation.toDomain()
        XCTAssertEqual(domain.modelConfig.providerID, "anthropic")
        XCTAssertEqual(domain.modelConfig.modelID, "claude-sonnet-4-6")
        XCTAssertEqual(domain.modelConfig.controls.maxTokens, 222)
    }

    func testConversationModelThreadModelConfigCanCarryInternalCodexPersistence() throws {
        var controls = GenerationControls()
        controls.codexResumeThreadID = "remote-thread-123"
        controls.codexPendingRollbackTurns = 2

        let thread = ConversationModelThreadEntity(
            providerID: "codex-app-server",
            modelID: "gpt-5-codex",
            modelConfigData: try JSONEncoder().encode(controls)
        )

        let decoded = try JSONDecoder().decode(GenerationControls.self, from: thread.modelConfigData)
        XCTAssertEqual(decoded.codexResumeThreadID, "remote-thread-123")
        XCTAssertEqual(decoded.codexPendingRollbackTurns, 2)
    }
}
