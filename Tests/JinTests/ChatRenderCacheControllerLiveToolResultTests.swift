import XCTest
@testable import Jin

@MainActor
final class ChatRenderCacheControllerLiveToolResultTests: XCTestCase {
    func testLiveToolResultIsVisibleBeforePersistedToolMessageLands() throws {
        let controller = ChatRenderCacheController()
        let assistant = try MessageEntity.fromDomain(
            Message(
                id: UUID(),
                role: .assistant,
                content: [.text("Looking that up.")],
                toolCalls: [
                    ToolCall(id: "fetch_1", name: "tinyfish__fetch_content", arguments: [:]),
                ]
            )
        )
        rebuild(controller, messages: [assistant], updatedAt: Date(timeIntervalSince1970: 1))
        XCTAssertTrue(controller.toolResultsByCallID.isEmpty)

        let live = ToolResult(
            toolCallID: "fetch_1",
            toolName: "tinyfish__fetch_content",
            content: "page body",
            isError: false
        )
        let versionBefore = controller.version
        controller.upsertLiveToolResult(live)

        XCTAssertEqual(controller.toolResultsByCallID["fetch_1"]?.content, "page body")
        XCTAssertEqual(controller.version, versionBefore &+ 1)
    }

    func testPersistedToolMessagePrunesMatchingLiveResult() throws {
        let controller = ChatRenderCacheController()
        let assistant = try MessageEntity.fromDomain(
            Message(
                id: UUID(),
                role: .assistant,
                content: [.text("Looking that up.")],
                toolCalls: [
                    ToolCall(id: "fetch_1", name: "tinyfish__fetch_content", arguments: [:]),
                ]
            )
        )
        rebuild(controller, messages: [assistant], updatedAt: Date(timeIntervalSince1970: 1))
        controller.upsertLiveToolResult(
            ToolResult(
                toolCallID: "fetch_1",
                toolName: "tinyfish__fetch_content",
                content: "live",
                isError: false
            )
        )

        let toolMessage = try MessageEntity.fromDomain(
            Message(
                id: UUID(),
                role: .tool,
                content: [.text("page body")],
                toolResults: [
                    ToolResult(
                        toolCallID: "fetch_1",
                        toolName: "tinyfish__fetch_content",
                        content: "persisted",
                        isError: false
                    ),
                ]
            )
        )
        rebuild(
            controller,
            messages: [assistant, toolMessage],
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual(controller.toolResultsByCallID["fetch_1"]?.content, "persisted")
    }

    func testConversationSwitchClearsLiveToolResults() throws {
        let controller = ChatRenderCacheController()
        controller.upsertLiveToolResult(
            ToolResult(
                toolCallID: "fetch_1",
                toolName: "tinyfish__fetch_content",
                content: "live",
                isError: false
            )
        )
        XCTAssertEqual(controller.toolResultsByCallID["fetch_1"]?.content, "live")

        controller.clearForConversationSwitch()

        XCTAssertTrue(controller.toolResultsByCallID.isEmpty)
    }

    private func rebuild(
        _ controller: ChatRenderCacheController,
        messages: [MessageEntity],
        updatedAt: Date
    ) {
        controller.rebuild(
            request: ChatRenderCacheRebuildRequest(
                conversationID: UUID(),
                allMessages: messages,
                orderedMessages: messages,
                updatedAt: updatedAt,
                fallbackModelLabel: "Model",
                artifactsEnabled: false,
                providerIconsByID: [:]
            ),
            assistantProviderIconID: { _ in nil },
            isStillCurrent: { _, _ in true },
            onContextApplied: {},
            onHistoryReady: {}
        )
    }
}
