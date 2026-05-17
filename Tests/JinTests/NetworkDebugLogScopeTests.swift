import XCTest
@testable import Jin

final class NetworkDebugLogScopeTests: XCTestCase {
    func testNetworkDebugLogContextTrimsConversationID() {
        let context = NetworkDebugLogContext(conversationID: " conversation\n")
        XCTAssertEqual(context.jsonObject, ["conversation_id": "conversation"])
    }

    func testNetworkDebugLogContextDropsBlankIdentifier() {
        let context = NetworkDebugLogContext(conversationID: " \t ")
        XCTAssertEqual(context.jsonObject, [:])
    }
}
