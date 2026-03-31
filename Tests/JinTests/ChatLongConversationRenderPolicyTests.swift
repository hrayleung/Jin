import XCTest
@testable import Jin

final class ChatLongConversationRenderPolicyTests: XCTestCase {
    func testEffectiveRenderModeBypassesCollapseForNativeTextMessages() {
        let message = makeAssistantItem(
            preferredRenderMode: .nativeText,
            isMemoryIntensive: true,
            collapsedPreview: LightweightMessagePreview(
                headline: "Summary",
                body: "Body",
                lineCount: 3,
                containsCode: false
            )
        )

        let mode = ChatLongConversationRenderPolicy.effectiveRenderMode(
            index: 0,
            message: message,
            totalMessageCount: ChatView.smartLongChatCollapseThreshold + 10,
            visibleMessageCount: ChatView.smartLongChatExpandedTailCount + 10,
            expandedIDs: []
        )

        XCTAssertEqual(mode, .nativeText)
    }

    func testEffectiveRenderModeCollapsesOlderMemoryIntensiveAssistantMessages() {
        let message = makeAssistantItem()

        let mode = ChatLongConversationRenderPolicy.effectiveRenderMode(
            index: 0,
            message: message,
            totalMessageCount: ChatView.smartLongChatCollapseThreshold + 1,
            visibleMessageCount: ChatView.smartLongChatExpandedTailCount + 2,
            expandedIDs: []
        )

        XCTAssertEqual(mode, .collapsedPreview)
    }

    func testEffectiveRenderModeKeepsExpandedTailFullyRendered() {
        let message = makeAssistantItem()
        let visibleMessageCount = ChatView.smartLongChatExpandedTailCount + 4

        let mode = ChatLongConversationRenderPolicy.effectiveRenderMode(
            index: visibleMessageCount - ChatView.smartLongChatExpandedTailCount,
            message: message,
            totalMessageCount: ChatView.smartLongChatCollapseThreshold + 1,
            visibleMessageCount: visibleMessageCount,
            expandedIDs: []
        )

        XCTAssertEqual(mode, .fullWeb)
    }

    func testEffectiveRenderModeHonorsExplicitExpansion() {
        let message = makeAssistantItem()

        let mode = ChatLongConversationRenderPolicy.effectiveRenderMode(
            index: 0,
            message: message,
            totalMessageCount: ChatView.smartLongChatCollapseThreshold + 1,
            visibleMessageCount: ChatView.smartLongChatExpandedTailCount + 4,
            expandedIDs: [message.id]
        )

        XCTAssertEqual(mode, .fullWeb)
    }

    private func makeAssistantItem(
        preferredRenderMode: MessageRenderMode = .fullWeb,
        isMemoryIntensive: Bool = true,
        collapsedPreview: LightweightMessagePreview? = LightweightMessagePreview(
            headline: "Preview",
            body: "Collapsed",
            lineCount: 12,
            containsCode: true
        )
    ) -> MessageRenderItem {
        MessageRenderItem(
            id: UUID(),
            contextThreadID: nil,
            role: MessageRole.assistant.rawValue,
            timestamp: Date(timeIntervalSince1970: 1),
            renderedBlocks: [.content(.text("ignored"))],
            toolCalls: [],
            searchActivities: [],
            codeExecutionActivities: [],
            codexToolActivities: [],
            agentToolActivities: [],
            assistantModelLabel: nil,
            assistantProviderIconID: nil,
            responseMetrics: nil,
            copyText: "ignored",
            preferredRenderMode: preferredRenderMode,
            isMemoryIntensiveAssistantContent: isMemoryIntensive,
            collapsedPreview: collapsedPreview,
            canEditUserMessage: false,
            canDeleteResponse: false,
            perMessageMCPServerNames: []
        )
    }
}
