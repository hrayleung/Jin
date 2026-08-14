import CoreGraphics
import XCTest
@testable import Jin

final class UserMessageImageStackSupportTests: XCTestCase {
    func testShouldStackOnlyWhenImagesExceedInlineCap() {
        XCTAssertFalse(UserMessageImageStackSupport.shouldStack(imageCount: 0))
        XCTAssertFalse(UserMessageImageStackSupport.shouldStack(imageCount: 1))
        XCTAssertFalse(UserMessageImageStackSupport.shouldStack(imageCount: 3))
        XCTAssertTrue(UserMessageImageStackSupport.shouldStack(imageCount: 4))
        XCTAssertTrue(UserMessageImageStackSupport.shouldStack(imageCount: 12))
    }

    func testPreviewCountCapsCollapsedFan() {
        XCTAssertEqual(UserMessageImageStackSupport.previewCount(imageCount: 0), 0)
        XCTAssertEqual(UserMessageImageStackSupport.previewCount(imageCount: 1), 1)
        XCTAssertEqual(UserMessageImageStackSupport.previewCount(imageCount: 3), 3)
        XCTAssertEqual(UserMessageImageStackSupport.previewCount(imageCount: 12), 3)
    }

    func testCollapsedStackSizeGrowsWithPeekOffsets() {
        XCTAssertEqual(UserMessageImageStackSupport.collapsedStackSize(imageCount: 0), .zero)

        let single = UserMessageImageStackSupport.collapsedStackSize(imageCount: 1)
        XCTAssertEqual(single.width, UserMessageImageStackSupport.thumbnailSize, accuracy: 0.01)
        XCTAssertEqual(single.height, UserMessageImageStackSupport.thumbnailSize, accuracy: 0.01)
        XCTAssertEqual(UserMessageImageStackSupport.collapsedFanOrigin(imageCount: 1), .zero)

        let stacked = UserMessageImageStackSupport.collapsedStackSize(imageCount: 12)
        XCTAssertGreaterThan(stacked.width, UserMessageImageStackSupport.thumbnailSize)
        XCTAssertGreaterThan(stacked.height, UserMessageImageStackSupport.thumbnailSize)

        let origin = UserMessageImageStackSupport.collapsedFanOrigin(imageCount: 12)
        XCTAssertGreaterThanOrEqual(origin.x, 0)
        XCTAssertGreaterThanOrEqual(origin.y, 0)
        XCTAssertEqual(
            UserMessageImageStackSupport.collapsedStackBounds(imageCount: 12).origin,
            UserMessageImageStackSupport.collapsedStackBounds(imageCount: 4).origin
        )
    }

    func testTitleAndActionCopy() {
        XCTAssertEqual(UserMessageImageStackSupport.titleText(imageCount: 1), "1 image")
        XCTAssertEqual(UserMessageImageStackSupport.titleText(imageCount: 12), "12 images")
        XCTAssertEqual(UserMessageImageStackSupport.actionText(isExpanded: false), "Show all")
        XCTAssertEqual(UserMessageImageStackSupport.actionText(isExpanded: true), "Hide")
    }
}
