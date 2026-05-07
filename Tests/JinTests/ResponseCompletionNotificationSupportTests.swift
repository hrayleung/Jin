import XCTest
@testable import Jin

final class ResponseCompletionNotificationSupportTests: XCTestCase {
    func testNotificationTitleTrimsConversationTitle() {
        XCTAssertEqual(
            ResponseCompletionNotificationSupport.notificationTitle(from: " \n Project Notes\t "),
            "Project Notes"
        )
    }

    func testNotificationTitleFallsBackForBlankConversationTitle() {
        XCTAssertEqual(
            ResponseCompletionNotificationSupport.notificationTitle(from: " \n\t "),
            "Jin"
        )
    }

    func testNotificationBodyTrimsReplyPreview() {
        XCTAssertEqual(
            ResponseCompletionNotificationSupport.notificationBody(from: " \n Done with the draft.\t "),
            "Done with the draft."
        )
    }

    func testNotificationBodyFallsBackForMissingOrBlankReplyPreview() {
        XCTAssertEqual(
            ResponseCompletionNotificationSupport.notificationBody(from: nil),
            "Your assistant reply is ready."
        )
        XCTAssertEqual(
            ResponseCompletionNotificationSupport.notificationBody(from: " \n\t "),
            "Your assistant reply is ready."
        )
    }
}
