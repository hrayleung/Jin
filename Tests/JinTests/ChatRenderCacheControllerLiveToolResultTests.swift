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
        let conversationID = UUID()
        rebuild(
            controller,
            messages: [assistant],
            updatedAt: Date(timeIntervalSince1970: 1),
            conversationID: conversationID
        )
        XCTAssertTrue(controller.toolResultsByCallID.isEmpty)

        let live = ToolResult(
            toolCallID: "fetch_1",
            toolName: "tinyfish__fetch_content",
            content: "page body",
            isError: false
        )
        let versionBefore = controller.version
        controller.upsertLiveToolResult(live, conversationID: conversationID)

        XCTAssertEqual(controller.toolResultsByCallID["fetch_1"]?.content, "page body")
        XCTAssertEqual(
            controller.liveToolResultStore.resultsByCallID["fetch_1"]?.content,
            "page body"
        )
        // Live bodies must not bump the table epoch — that remounts every
        // resident cell and stalls the activity-orb display link.
        XCTAssertEqual(controller.version, versionBefore)
        XCTAssertNil(controller.singleThreadContext().toolResultsByCallID["fetch_1"])
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
        let conversationID = UUID()
        rebuild(
            controller,
            messages: [assistant],
            updatedAt: Date(timeIntervalSince1970: 1),
            conversationID: conversationID
        )
        controller.upsertLiveToolResult(
            ToolResult(
                toolCallID: "fetch_1",
                toolName: "tinyfish__fetch_content",
                content: "live",
                isError: false
            ),
            conversationID: conversationID
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
            updatedAt: Date(timeIntervalSince1970: 2),
            conversationID: conversationID
        )

        XCTAssertEqual(controller.toolResultsByCallID["fetch_1"]?.content, "persisted")
        XCTAssertNil(controller.liveToolResultStore.resultsByCallID["fetch_1"])
        XCTAssertEqual(
            controller.singleThreadContext().toolResultsByCallID["fetch_1"]?.content,
            "persisted"
        )
    }

    func testConversationSwitchClearsLiveToolResults() throws {
        let controller = ChatRenderCacheController()
        let conversationID = UUID()
        rebuild(
            controller,
            messages: [],
            updatedAt: Date(timeIntervalSince1970: 1),
            conversationID: conversationID
        )
        controller.upsertLiveToolResult(
            ToolResult(
                toolCallID: "fetch_1",
                toolName: "tinyfish__fetch_content",
                content: "live",
                isError: false
            ),
            conversationID: conversationID
        )
        XCTAssertEqual(controller.toolResultsByCallID["fetch_1"]?.content, "live")

        controller.clearForConversationSwitch()

        XCTAssertTrue(controller.toolResultsByCallID.isEmpty)
    }

    func testLateLiveResultFromPreviousConversationIsIgnored() throws {
        let controller = ChatRenderCacheController()
        let previousConversationID = UUID()
        let currentConversationID = UUID()
        rebuild(
            controller,
            messages: [],
            updatedAt: Date(timeIntervalSince1970: 1),
            conversationID: previousConversationID
        )
        controller.clearForConversationSwitch()
        rebuild(
            controller,
            messages: [],
            updatedAt: Date(timeIntervalSince1970: 2),
            conversationID: currentConversationID
        )

        controller.upsertLiveToolResult(
            ToolResult(
                toolCallID: "fetch_1",
                toolName: "tinyfish__fetch_content",
                content: "stale",
                isError: false
            ),
            conversationID: previousConversationID
        )

        XCTAssertTrue(controller.toolResultsByCallID.isEmpty)
    }

    private func rebuild(
        _ controller: ChatRenderCacheController,
        messages: [MessageEntity],
        updatedAt: Date,
        conversationID: UUID = UUID()
    ) {
        controller.rebuild(
            request: ChatRenderCacheRebuildRequest(
                conversationID: conversationID,
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
