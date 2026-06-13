import AppKit
import XCTest
@testable import Jin

@MainActor
final class JinMessageTextViewScrubTests: XCTestCase {
    /// A bare U+FFFC (OBJECT REPLACEMENT CHARACTER) in LLM text is classified
    /// by TextKit as an attachment control glyph, and drawing it adds a subview
    /// mid-`drawRect:` → constraint exception → crash. The scrub must remove it
    /// before it reaches the text storage, length-preserving so selection
    /// offsets stay aligned.
    func testScrubReplacesObjectReplacementCharacter() {
        let view = JinMessageTextView()
        let input = NSAttributedString(string: "a\u{FFFC}b\u{FFFC}c")

        view.setScrubbedAttributedString(input)

        let result = view.attributedString().string
        XCTAssertFalse(result.utf16.contains(0xFFFC), "U+FFFC must be scrubbed; got: \(result.unicodeScalars.map { String(format: "U+%04X", $0.value) })")
        XCTAssertEqual(result.count, input.length, "scrub must be length-preserving so selection offsets stay aligned")
        XCTAssertEqual(result, "a\u{FFFD}b\u{FFFD}c")
    }

    func testScrubLeavesNormalTextUntouched() {
        let view = JinMessageTextView()
        let input = NSAttributedString(string: "NSDI 与 MobiHoc 对比 (每年 600+ 篇)")

        view.setScrubbedAttributedString(input)

        XCTAssertEqual(view.attributedString().string, input.string)
    }
}
