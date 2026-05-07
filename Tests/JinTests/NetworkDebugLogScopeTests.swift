import XCTest
@testable import Jin

final class NetworkDebugLogScopeTests: XCTestCase {
    func testNetworkDebugLogContextTrimsAndDropsBlankIdentifiers() {
        let context = NetworkDebugLogContext(
            conversationID: " conversation\n",
            threadID: " \t ",
            turnID: "turn"
        )

        XCTAssertEqual(
            context.jsonObject,
            [
                "conversation_id": "conversation",
                "turn_id": "turn"
            ]
        )
    }
}
