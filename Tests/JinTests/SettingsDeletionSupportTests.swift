import XCTest
@testable import Jin

final class SettingsDeletionSupportTests: XCTestCase {
    func testProviderDeletionMessageWithoutChatsMentionsOnlyProvider() {
        XCTAssertEqual(
            SettingsDeletionSupport.providerDeletionMessage(
                providerName: "OpenAI",
                chatCount: 0
            ),
            "This will permanently delete \u{201C}OpenAI\u{201D}."
        )
    }

    func testProviderDeletionMessagePluralizesChatUsage() {
        XCTAssertEqual(
            SettingsDeletionSupport.providerDeletionMessage(
                providerName: "OpenAI",
                chatCount: 1
            ),
            """
            This will permanently delete \u{201C}OpenAI\u{201D}.

            It is currently used by 1 chat. Those chats will need a different provider selected.
            """
        )

        XCTAssertEqual(
            SettingsDeletionSupport.providerDeletionMessage(
                providerName: "OpenAI",
                chatCount: 2
            ),
            """
            This will permanently delete \u{201C}OpenAI\u{201D}.

            It is currently used by 2 chats. Those chats will need a different provider selected.
            """
        )
    }

    func testServerDeletionMessageMentionsServer() {
        XCTAssertEqual(
            SettingsDeletionSupport.serverDeletionMessage(serverName: "Filesystem"),
            "This will permanently delete \u{201C}Filesystem\u{201D}."
        )
    }
}
