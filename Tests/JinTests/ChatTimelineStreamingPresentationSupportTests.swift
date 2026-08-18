import XCTest
@testable import Jin

final class ChatTimelineStreamingPresentationSupportTests: XCTestCase {
    func testLastVisibleTurnTreatsMissingToolResultsAsUnresolved() {
        let turn = ChatTimelineStreamingPresentationSupport.lastVisibleTurn(
            lastMessage: makeItem(
                role: .assistant,
                toolCalls: [
                    ToolCall(id: "fetch_1", name: "tinyfish__fetch_content", arguments: [:]),
                    ToolCall(id: "search_1", name: "tinyfish__search", arguments: [:]),
                ]
            ),
            toolResultsByCallID: [
                "fetch_1": ToolResult(
                    toolCallID: "fetch_1",
                    toolName: "tinyfish__fetch_content",
                    content: "ok",
                    isError: false
                ),
            ]
        )

        XCTAssertEqual(turn?.role, .assistant)
        XCTAssertEqual(turn?.unresolvedVisibleToolCallIDs, ["search_1"])
        XCTAssertTrue(turn?.hasUnresolvedVisibleToolCalls == true)
    }

    func testLastVisibleTurnIgnoresBuiltinSearchTools() {
        let turn = ChatTimelineStreamingPresentationSupport.lastVisibleTurn(
            lastMessage: makeItem(
                role: .assistant,
                toolCalls: [
                    ToolCall(id: "exa_1", name: BuiltinSearchToolHub.functionName, arguments: [:]),
                ]
            ),
            toolResultsByCallID: [:]
        )

        XCTAssertEqual(turn?.role, .assistant)
        XCTAssertEqual(turn?.unresolvedVisibleToolCallIDs, [])
        XCTAssertFalse(turn?.hasUnresolvedVisibleToolCalls == true)
    }

    func testSuppressesIdlePlaceholderOnlyForAssistantWithInFlightMCPTools() {
        let unresolvedAssistant = ChatTimelineStreamingPresentationSupport.LastVisibleTurn(
            role: .assistant,
            unresolvedVisibleToolCallIDs: ["fetch_1"]
        )
        let resolvedAssistant = ChatTimelineStreamingPresentationSupport.LastVisibleTurn(
            role: .assistant,
            unresolvedVisibleToolCallIDs: []
        )
        let userTurn = ChatTimelineStreamingPresentationSupport.LastVisibleTurn(
            role: .user,
            unresolvedVisibleToolCallIDs: []
        )

        XCTAssertTrue(
            ChatTimelineStreamingPresentationSupport.suppressesIdlePlaceholder(
                lastVisibleTurn: unresolvedAssistant
            )
        )
        XCTAssertFalse(
            ChatTimelineStreamingPresentationSupport.suppressesIdlePlaceholder(
                lastVisibleTurn: resolvedAssistant
            )
        )
        XCTAssertFalse(
            ChatTimelineStreamingPresentationSupport.suppressesIdlePlaceholder(
                lastVisibleTurn: userTurn
            )
        )
        XCTAssertFalse(
            ChatTimelineStreamingPresentationSupport.suppressesIdlePlaceholder(
                lastVisibleTurn: nil
            )
        )
    }

    func testIdleStreamingRowCollapsesOnlyWhenEmptyAndToolsAreLiveOnLastAssistant() {
        let unresolvedAssistant = ChatTimelineStreamingPresentationSupport.LastVisibleTurn(
            role: .assistant,
            unresolvedVisibleToolCallIDs: ["fetch_1"]
        )

        XCTAssertTrue(
            ChatTimelineStreamingPresentationSupport.shouldCollapseIdleStreamingRow(
                hasVisiblePresentation: false,
                lastVisibleTurn: unresolvedAssistant
            )
        )
        XCTAssertFalse(
            ChatTimelineStreamingPresentationSupport.shouldCollapseIdleStreamingRow(
                hasVisiblePresentation: true,
                lastVisibleTurn: unresolvedAssistant
            )
        )
        XCTAssertFalse(
            ChatTimelineStreamingPresentationSupport.shouldCollapseIdleStreamingRow(
                hasVisiblePresentation: false,
                lastVisibleTurn: ChatTimelineStreamingPresentationSupport.LastVisibleTurn(
                    role: .user,
                    unresolvedVisibleToolCallIDs: []
                )
            )
        )
    }

    func testLiveToolTimelineRequiresStreamingAndUnresolvedCalls() {
        let calls = [ToolCall(id: "fetch_1", name: "tinyfish__fetch_content", arguments: [:])]

        XCTAssertTrue(
            ChatTimelineStreamingPresentationSupport.isLiveToolTimeline(
                isConversationStreaming: true,
                visibleToolCalls: calls,
                toolResultsByCallID: [:]
            )
        )
        XCTAssertFalse(
            ChatTimelineStreamingPresentationSupport.isLiveToolTimeline(
                isConversationStreaming: false,
                visibleToolCalls: calls,
                toolResultsByCallID: [:]
            )
        )
        XCTAssertFalse(
            ChatTimelineStreamingPresentationSupport.isLiveToolTimeline(
                isConversationStreaming: true,
                visibleToolCalls: calls,
                toolResultsByCallID: [
                    "fetch_1": ToolResult(
                        toolCallID: "fetch_1",
                        toolName: "tinyfish__fetch_content",
                        content: "ok",
                        isError: false
                    ),
                ]
            )
        )
    }

    func testPersistedActivityOwnerExistsOnlyDuringUnresolvedToolHandoff() {
        let assistant = makeItem(
            role: .assistant,
            toolCalls: [ToolCall(id: "fetch_1", name: "tinyfish__fetch_content", arguments: [:])]
        )
        XCTAssertEqual(
            ChatTimelineStreamingPresentationSupport.persistedActivityOwnerMessageID(
                isConversationStreaming: true,
                lastMessage: assistant,
                toolResultsByCallID: [:]
            ),
            assistant.id
        )
        XCTAssertNil(
            ChatTimelineStreamingPresentationSupport.persistedActivityOwnerMessageID(
                isConversationStreaming: false,
                lastMessage: assistant,
                toolResultsByCallID: [:]
            )
        )
        XCTAssertNil(
            ChatTimelineStreamingPresentationSupport.persistedActivityOwnerMessageID(
                isConversationStreaming: true,
                lastMessage: assistant,
                toolResultsByCallID: [
                    "fetch_1": ToolResult(toolCallID: "fetch_1", content: "ok"),
                ]
            )
        )
    }

    private func makeItem(
        role: MessageRole,
        toolCalls: [ToolCall]
    ) -> MessageRenderItem {
        MessageRenderItem(
            id: UUID(),
            role: role.rawValue,
            timestamp: Date(timeIntervalSince1970: 1),
            renderedBlocks: [.content(anchorID: "anchor-0", part: .text("body"))],
            toolCalls: toolCalls,
            searchActivities: [],
            codeExecutionActivities: [],
            assistantModelLabel: "Kimi K3",
            assistantProviderIconID: nil,
            responseMetrics: nil,
            copyText: "body",
            preferredRenderMode: .fullWeb,
            isMemoryIntensiveAssistantContent: false,
            collapsedPreview: nil,
            canEditUserMessage: role == .user,
            canDeleteResponse: role == .user,
            perMessageMCPServerNames: []
        )
    }
}
