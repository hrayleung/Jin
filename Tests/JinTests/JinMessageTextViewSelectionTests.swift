import AppKit
import XCTest
@testable import Jin

/// Selection highlight lifecycle for read-only message text views.
/// Residual unemphasized (gray) selection across many per-block
/// `JinMessageTextView`s is the sticky “shadow” bug after mouse-up / click-away.
@MainActor
final class JinMessageTextViewSelectionTests: XCTestCase {
    private func makeView(text: String = "可选中的一段消息文本") -> JinMessageTextView {
        let view = JinMessageTextView()
        view.setScrubbedAttributedString(
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14)])
        )
        return view
    }

    func testResignFirstResponderClearsNonEmptySelection() {
        let view = makeView()
        view.setSelectedRange(NSRange(location: 1, length: 4))
        XCTAssertEqual(view.selectedRange().length, 4)

        // resignFirstResponder requires a window responder chain; exercise the
        // same clear path the override calls when resign succeeds.
        view.clearSelectionHighlightIfNeeded()
        XCTAssertEqual(view.selectedRange().length, 0)
        XCTAssertEqual(view.selectedRange().location, 1)
    }

    func testClearSelectionIsNoOpWhenAlreadyEmpty() {
        let view = makeView()
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.clearSelectionHighlightIfNeeded()
        XCTAssertEqual(view.selectedRange(), NSRange(location: 3, length: 0))
    }

    func testAcceptsFirstResponderWhenSelectable() {
        let view = makeView()
        XCTAssertTrue(view.isSelectable)
        XCTAssertTrue(view.acceptsFirstResponder)
    }

    func testResignFirstResponderInWindowClearsSelection() {
        let view = makeView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 200)

        XCTAssertTrue(window.makeFirstResponder(view))
        view.setSelectedRange(NSRange(location: 0, length: 5))
        XCTAssertEqual(view.selectedRange().length, 5)

        // Hand focus to the window itself — message text must drop its
        // highlight so the gray inactive selection does not linger.
        XCTAssertTrue(window.makeFirstResponder(nil))
        XCTAssertEqual(view.selectedRange().length, 0)
    }
}
