import XCTest
@testable import Jin

final class ChatAssistantBubbleStackSupportTests: XCTestCase {
    func testCanonicalOrderPutsMCPToolsAfterProse() {
        XCTAssertEqual(
            ChatAssistantBubbleStackSupport.order,
            [
                .searchActivities,
                .codeExecution,
                .thinking,
                .text,
                .artifacts,
                .mcpTools
            ]
        )
        XCTAssertEqual(
            ChatAssistantBubbleStackSupport.order.last,
            .mcpTools
        )
        XCTAssertLessThan(
            ChatAssistantBubbleStackSupport.order.firstIndex(of: .text)!,
            ChatAssistantBubbleStackSupport.order.firstIndex(of: .mcpTools)!
        )
    }

    func testPreamblePlusMCPSearchDoesNotPlaceTheCardAboveText() {
        let sections = ChatAssistantBubbleStackSupport.visibleSections(
            in: .init(hasText: true, hasMCPTools: true)
        )

        XCTAssertEqual(sections, [.text, .mcpTools])
    }

    func testBuiltinSearchActivitiesStayAboveTextInBothSurfaces() {
        let sections = ChatAssistantBubbleStackSupport.visibleSections(
            in: .init(hasSearchActivities: true, hasText: true, hasMCPTools: true)
        )

        XCTAssertEqual(sections, [.searchActivities, .text, .mcpTools])
    }

    func testThinkingStaysWithProseAndStillAboveMCPTools() {
        let sections = ChatAssistantBubbleStackSupport.visibleSections(
            in: .init(hasThinking: true, hasText: true, hasArtifacts: true, hasMCPTools: true)
        )

        XCTAssertEqual(sections, [.thinking, .text, .artifacts, .mcpTools])
    }
}
