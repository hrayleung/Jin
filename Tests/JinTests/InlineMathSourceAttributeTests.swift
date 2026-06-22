import AppKit
import XCTest
@testable import Jin

/// Locks in the inline-math copy/quote fix: the rendered attachment glyph
/// carries its delimited LaTeX source on `.jinInlineMathSource`, and the
/// extraction helpers expand that glyph back to the source on the way out to
/// the pasteboard / a quote — without ever changing string length.
@MainActor
final class InlineMathSourceAttributeTests: XCTestCase {

    private let font = NSFont.systemFont(ofSize: 14)

    /// Build a length-1 inline-math attachment glyph the way `InlineMath` does,
    /// but without invoking SwiftMath — keeps the extraction tests hermetic.
    private func mathGlyph(source: String) -> NSAttributedString {
        let attachment = NSTextAttachment()
        let s = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
        let full = NSRange(location: 0, length: s.length)
        s.addAttribute(.font, value: font, range: full)
        s.addAttribute(.jinInlineMathSource, value: source, range: full)
        return s
    }

    // MARK: - Extraction helpers (hermetic)

    func testExpandsSingleMathGlyphToSource() {
        let composed = NSMutableAttributedString(string: "before ", attributes: [.font: font])
        composed.append(mathGlyph(source: "$x^2$"))
        composed.append(NSAttributedString(string: " after", attributes: [.font: font]))

        XCTAssertEqual(
            JinMessageTextView.latexExpandedPlainString(from: composed),
            "before $x^2$ after"
        )
    }

    func testExpandedStringDropsAttachmentAndSourceAttributes() {
        let composed = NSMutableAttributedString(string: "a ", attributes: [.font: font])
        composed.append(mathGlyph(source: "$x$"))
        let expanded = JinMessageTextView.latexExpandedAttributedString(from: composed)

        XCTAssertFalse(expanded.string.unicodeScalars.contains { $0.value == 0xFFFC })
        let full = NSRange(location: 0, length: expanded.length)
        expanded.enumerateAttribute(.attachment, in: full, options: []) { value, _, _ in
            XCTAssertNil(value)
        }
        expanded.enumerateAttribute(.jinInlineMathSource, in: full, options: []) { value, _, _ in
            XCTAssertNil(value)
        }
    }

    /// Two adjacent identical formulas coalesce into a single
    /// `.jinInlineMathSource` run (TextKit merges equal values); each glyph
    /// must still expand to its own copy of the source.
    func testAdjacentIdenticalGlyphsExpandPerGlyph() {
        let composed = NSMutableAttributedString()
        composed.append(mathGlyph(source: "$x$"))
        composed.append(mathGlyph(source: "$x$"))

        XCTAssertEqual(
            JinMessageTextView.latexExpandedPlainString(from: composed),
            "$x$$x$"
        )
    }

    func testExpansionStripsZeroWidthSpace() {
        let composed = NSMutableAttributedString(string: "a\u{200B}b ", attributes: [.font: font])
        composed.append(mathGlyph(source: "$y$"))
        XCTAssertEqual(
            JinMessageTextView.latexExpandedPlainString(from: composed),
            "ab $y$"
        )
    }

    func testNonMathStringPassesThroughUnchanged() {
        let plain = NSAttributedString(string: "no math here", attributes: [.font: font])
        XCTAssertEqual(
            JinMessageTextView.latexExpandedPlainString(from: plain),
            "no math here"
        )
    }

    // MARK: - InlineMath wiring (depends on SwiftMath rendering)

    func testRenderedInlineMathCarriesDelimitedSource() {
        let result = InlineMath.attributedString(inner: "x^2", original: "$x^2$", font: font, color: .black)
        // On render success the glyph is a single U+FFFC carrying the source;
        // on a (rare) render failure it degrades to the raw delimited text,
        // which already round-trips correctly.
        if result.string == "\u{FFFC}" {
            XCTAssertEqual(result.length, 1, "math attachment must stay one UTF-16 unit (offset invariant)")
            XCTAssertNotNil(result.attribute(.attachment, at: 0, effectiveRange: nil))
            XCTAssertEqual(
                result.attribute(.jinInlineMathSource, at: 0, effectiveRange: nil) as? String,
                "$x^2$"
            )
        } else {
            XCTAssertEqual(result.string, "$x^2$")
        }
    }

    /// The attachment cache must key on the delimited `original`, not bare
    /// `inner`: `$y$` and `\(y\)` share an inner but must each persist their
    /// own delimiters, or copy/quote emits the wrong source.
    func testCacheKeyDistinguishesDelimiterSpellings() throws {
        let dollar = InlineMath.attributedString(inner: "y", original: "$y$", font: font, color: .black)
        let paren = InlineMath.attributedString(inner: "y", original: "\\(y\\)", font: font, color: .black)

        guard dollar.string == "\u{FFFC}", paren.string == "\u{FFFC}" else {
            throw XCTSkip("SwiftMath did not render the attachment in this environment")
        }
        XCTAssertEqual(dollar.attribute(.jinInlineMathSource, at: 0, effectiveRange: nil) as? String, "$y$")
        XCTAssertEqual(paren.attribute(.jinInlineMathSource, at: 0, effectiveRange: nil) as? String, "\\(y\\)")
    }
}
