import XCTest
@testable import Jin

final class ChatStreamingOrchestratorTests: XCTestCase {
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
