import XCTest
import AppKit
@testable import Jin

final class DroppableTextEditorFocusTests: XCTestCase {
    func testProgrammaticFocusRequestClaimsFirstResponderWhenAlreadyInWindow() {
        let window = makeWindow()
        let hostView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = hostView

        let textView = DroppableNSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        hostView.addSubview(textView)

        XCTAssertFalse(window.firstResponder === textView)

        textView.setProgrammaticFocusRequested(true)

        XCTAssertTrue(window.firstResponder === textView)
    }

    func testProgrammaticFocusRequestClaimsFirstResponderAfterMovingIntoWindow() {
        let detachedHost = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        let textView = DroppableNSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        detachedHost.addSubview(textView)
        textView.setProgrammaticFocusRequested(true)

        let window = makeWindow()
        let hostView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = hostView
        hostView.addSubview(textView)

        XCTAssertTrue(window.firstResponder === textView)
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
    }
}
