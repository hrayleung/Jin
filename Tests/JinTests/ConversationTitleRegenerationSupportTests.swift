import XCTest
@testable import Jin

final class ConversationTitleRegenerationSupportTests: XCTestCase {
    func testContextMessagesReturnsLatestUserAndLatestAssistantPair() {
        let olderUser = makeMessage(role: .user, text: "Older prompt")
        let latestUser = makeMessage(role: .user, text: "Latest prompt")
        let latestAssistant = makeMessage(role: .assistant, text: "Latest answer")
        let trailingTool = makeMessage(role: .tool, text: "Tool result")

        XCTAssertEqual(
            ConversationTitleRegenerationSupport.contextMessages(
                from: [olderUser, latestUser, latestAssistant, trailingTool]
            ).map(\.id),
            [latestUser.id, latestAssistant.id]
        )
    }

    func testContextMessagesUsesAssistantAloneWhenNoPriorUserExists() {
        let system = makeMessage(role: .system, text: "Rules")
        let assistant = makeMessage(role: .assistant, text: "Answer")

        XCTAssertEqual(
            ConversationTitleRegenerationSupport.contextMessages(from: [system, assistant]).map(\.id),
            [assistant.id]
        )
    }

    func testContextMessagesUsesLatestUserWhenNoAssistantExists() {
        let olderUser = makeMessage(role: .user, text: "First")
        let latestUser = makeMessage(role: .user, text: "Second")

        XCTAssertEqual(
            ConversationTitleRegenerationSupport.contextMessages(from: [olderUser, latestUser]).map(\.id),
            [latestUser.id]
        )
    }

    func testContextMessagesDropsHistoryWithoutUserOrAssistantMessages() {
        XCTAssertTrue(
            ConversationTitleRegenerationSupport.contextMessages(
                from: [
                    makeMessage(role: .system, text: "Rules"),
                    makeMessage(role: .tool, text: "Tool output")
                ]
            ).isEmpty
        )
    }

    private func makeMessage(role: MessageRole, text: String) -> Message {
        Message(id: UUID(), role: role, content: [.text(text)])
    }
}
