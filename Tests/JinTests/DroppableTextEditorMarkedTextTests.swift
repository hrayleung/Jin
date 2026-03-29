import XCTest
import AppKit
@testable import Jin

final class DroppableTextEditorMarkedTextTests: XCTestCase {
    func testSyncExternalTextDoesNotClearMarkedTextDuringComposition() {
        let textView = DroppableNSTextView(frame: .zero)
        textView.setMarkedText(
            "ni",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        XCTAssertTrue(textView.hasMarkedText())
        XCTAssertEqual(textView.string, "ni")

        textView.syncExternalTextIfNeeded("")

        XCTAssertTrue(textView.hasMarkedText())
        XCTAssertEqual(textView.string, "ni")
        XCTAssertEqual(textView.markedRange(), NSRange(location: 0, length: 2))
    }

    func testSyncExternalTextAppliesNormallyAfterMarkedTextEnds() {
        let textView = DroppableNSTextView(frame: .zero)
        textView.setMarkedText(
            "ni",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        textView.unmarkText()

        XCTAssertFalse(textView.hasMarkedText())
        XCTAssertEqual(textView.string, "ni")

        textView.syncExternalTextIfNeeded("")

        XCTAssertFalse(textView.hasMarkedText())
        XCTAssertEqual(textView.string, "")
    }
}
