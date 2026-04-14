import XCTest
@testable import Jin

final class ChatDropHandlingSupportTests: XCTestCase {
    func testMakeAttachmentImportPlanWithoutLimitKeepsAllURLs() {
        let urls = [
            URL(fileURLWithPath: "/tmp/a.png"),
            URL(fileURLWithPath: "/tmp/b.png"),
            URL(fileURLWithPath: "/tmp/c.png")
        ]

        let plan = ChatDropHandlingSupport.makeAttachmentImportPlan(
            from: urls,
            currentAttachmentCount: 12,
            maxAttachments: nil
        )

        XCTAssertEqual(plan.urlsToImport, urls)
        XCTAssertTrue(plan.errors.isEmpty)
    }

    func testMakeAttachmentImportPlanTruncatesToRemainingSlots() {
        let urls = [
            URL(fileURLWithPath: "/tmp/a.png"),
            URL(fileURLWithPath: "/tmp/b.png"),
            URL(fileURLWithPath: "/tmp/c.png")
        ]

        let plan = ChatDropHandlingSupport.makeAttachmentImportPlan(
            from: urls,
            currentAttachmentCount: 1,
            maxAttachments: 2
        )

        XCTAssertEqual(plan.urlsToImport, [urls[0]])
        XCTAssertEqual(plan.errors, ["You can attach up to 2 files per message."])
    }

    func testMakeAttachmentImportPlanReturnsErrorWhenLimitAlreadyReached() {
        let urls = [
            URL(fileURLWithPath: "/tmp/a.png")
        ]

        let plan = ChatDropHandlingSupport.makeAttachmentImportPlan(
            from: urls,
            currentAttachmentCount: 2,
            maxAttachments: 2
        )

        XCTAssertTrue(plan.urlsToImport.isEmpty)
        XCTAssertEqual(plan.errors, ["You can attach up to 2 files per message."])
    }
}
