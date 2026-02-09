import XCTest
import AppKit
@testable import Jin

final class DroppableTextEditorPasteRoutingTests: XCTestCase {
    func testPasteRoutesToCustomHandler() {
        let textView = DroppableNSTextView(frame: .zero)
        var callCount = 0
        textView.onPerformPasteboard = { pasteboard in
            callCount += 1
            return pasteboard == .general
        }

        textView.paste(nil)

        XCTAssertEqual(callCount, 1)
    }

    func testPasteAsPlainTextRoutesToCustomHandler() {
        let textView = DroppableNSTextView(frame: .zero)
        var callCount = 0
        textView.onPerformPasteboard = { _ in
            callCount += 1
            return true
        }

        textView.pasteAsPlainText(nil)

        XCTAssertEqual(callCount, 1)
    }

    func testReadSelectionRoutesToCustomHandler() {
        let textView = DroppableNSTextView(frame: .zero)
        let pasteboard = NSPasteboard.withUniqueName()
        var seenPasteboardNames: [NSPasteboard.Name] = []
        textView.onPerformPasteboard = { source in
            seenPasteboardNames.append(source.name)
            return source.name == pasteboard.name
        }

        let handled = textView.readSelection(from: pasteboard)

        XCTAssertTrue(handled)
        XCTAssertEqual(seenPasteboardNames, [pasteboard.name])
    }
}
