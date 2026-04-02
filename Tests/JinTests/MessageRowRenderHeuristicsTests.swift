import XCTest
@testable import Jin

final class MessageRowRenderHeuristicsTests: XCTestCase {
    func testCollapsedPreviewForDisplayUsesPrecomputedPreview() {
        let preview = LightweightMessagePreview(
            headline: "Code reply",
            body: "12 lines",
            lineCount: 12,
            containsCode: true
        )
        let item = makeItem(
            role: .assistant,
            renderedBlocks: [.content(anchorID: "anchor-0", part: .text("plain text without markdown"))],
            collapsedPreview: preview
        )

        XCTAssertEqual(item.collapsedPreviewForDisplay(in: .collapsedPreview), preview)
    }

    func testCollapsedPreviewForDisplayDoesNotInferPreviewFromRenderedBlocks() {
        let item = makeItem(
            role: .assistant,
            renderedBlocks: [
                .content(
                    anchorID: "anchor-0",
                    part: .text(
                        """
                        ```swift
                        print(\"hi\")
                        ```
                        """
                    )
                )
            ],
            collapsedPreview: nil
        )

        XCTAssertNil(item.collapsedPreviewForDisplay(in: .collapsedPreview))
    }

    func testCollapsedPreviewForDisplayRequiresAssistantCollapsedMode() {
        let preview = LightweightMessagePreview(
            headline: "Artifact",
            body: "HTML Artifact",
            lineCount: 1,
            containsCode: false
        )
        let userItem = makeItem(role: .user, collapsedPreview: preview)
        let assistantItem = makeItem(role: .assistant, collapsedPreview: preview)

        XCTAssertNil(userItem.collapsedPreviewForDisplay(in: .collapsedPreview))
        XCTAssertNil(assistantItem.collapsedPreviewForDisplay(in: .fullWeb))
    }

    func testVisibleToolCallsHidesBuiltinGoogleAndAgentTools() {
        let builtinSearchTool = makeToolCall(name: BuiltinSearchToolHub.functionName)
        let googleNativeTool = makeToolCall(name: "google_search")
        let agentTool = makeToolCall(name: AgentToolHub.shellExecuteFunctionName)
        let visibleTool = makeToolCall(name: "weather_lookup")
        let item = makeItem(
            role: .assistant,
            toolCalls: [builtinSearchTool, googleNativeTool, agentTool, visibleTool],
            collapsedPreview: nil
        )

        XCTAssertEqual(item.visibleToolCalls.map(\.name), [visibleTool.name])
    }

    private func makeItem(
        role: MessageRole,
        renderedBlocks: [RenderedMessageBlock] = [.content(anchorID: "anchor-0", part: .text("body"))],
        toolCalls: [ToolCall] = [],
        collapsedPreview: LightweightMessagePreview?
    ) -> MessageRenderItem {
        MessageRenderItem(
            id: UUID(),
            contextThreadID: nil,
            role: role.rawValue,
            timestamp: Date(timeIntervalSince1970: 1),
            renderedBlocks: renderedBlocks,
            toolCalls: toolCalls,
            searchActivities: [],
            codeExecutionActivities: [],
            codexToolActivities: [],
            agentToolActivities: [],
            assistantModelLabel: nil,
            assistantProviderIconID: nil,
            responseMetrics: nil,
            copyText: "body",
            preferredRenderMode: .fullWeb,
            isMemoryIntensiveAssistantContent: true,
            collapsedPreview: collapsedPreview,
            canEditUserMessage: role == .user,
            canDeleteResponse: false,
            perMessageMCPServerNames: []
        )
    }

    private func makeToolCall(name: String) -> ToolCall {
        ToolCall(id: UUID().uuidString, name: name, arguments: [:])
    }
}
