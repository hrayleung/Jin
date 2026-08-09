import AppKit
import XCTest
@testable import Jin

/// `computeHeight(forWidth:)` / `naturalWidth(maxWidth:)` / `intrinsicContentSize`
/// — the measurements the timeline's row heights are built from. Two invariants:
///
/// 1. Inset round-trip: both take/report VIEW metrics, laying text out at the
///    same container width `widthTracksTextView` produces at render time
///    (view width minus horizontal insets) and adding the insets back into the
///    result. The pre-fix version measured the bare `usedRect` at the full
///    view width — code blocks (inset 14×10) were reported 20pt short and
///    wrapped 28pt wider than they rendered, which the hosting cell's mask
///    turned into bottom-clipped rows.
/// 2. Version-keyed memoization: ANY storage mutation must miss the memo.
///    The pre-fix key was the storage LENGTH — recycled views showing
///    same-length different content, and highlight upgrades swapping fonts
///    under identical characters, both returned the stale height.
@MainActor
final class JinMessageTextViewSizingTests: XCTestCase {
    private let font = NSFont.systemFont(ofSize: 14)

    private func attributed(_ string: String, pointSize: CGFloat = 14) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: pointSize)])
    }

    private func makeView(_ string: String, inset: NSSize = .zero) -> JinMessageTextView {
        let view = JinMessageTextView()
        view.setScrubbedAttributedString(attributed(string))
        view.textContainerInset = inset
        return view
    }

    // MARK: - Inset round-trip

    func testVerticalInsetIsIncludedInComputedHeight() {
        // Single short line: wraps identically with and without the inset.
        let plain = makeView("short line")
        let inset = makeView("short line", inset: NSSize(width: 14, height: 10))

        let plainHeight = plain.computeHeight(forWidth: 400)
        let insetHeight = inset.computeHeight(forWidth: 400)

        XCTAssertEqual(insetHeight, plainHeight + 20, accuracy: 1.0)
    }

    func testInsetViewWrapsAtRenderContainerWidth() {
        // The inset view's container at view width W is (W − 28) — identical
        // to a zero-inset view laid out at (W − 28). Same wraps ⇒ heights
        // differ by exactly the vertical insets.
        let text = String(repeating: "wrap parity probe ", count: 30)
        let plain = makeView(text)
        let inset = makeView(text, inset: NSSize(width: 14, height: 10))

        let reference = plain.computeHeight(forWidth: 300 - 28)
        let measured = inset.computeHeight(forWidth: 300)

        XCTAssertEqual(measured, reference + 20, accuracy: 1.0)
    }

    func testNaturalWidthIncludesHorizontalInsets() {
        let plain = makeView("single line, no wrapping")
        let inset = makeView("single line, no wrapping", inset: NSSize(width: 14, height: 10))

        XCTAssertEqual(
            inset.naturalWidth(maxWidth: 10_000),
            plain.naturalWidth(maxWidth: 10_000) + 28,
            accuracy: 1.0
        )
    }

    func testIntrinsicHeightMatchesComputeHeightRoundTrip() {
        let view = makeView(
            String(repeating: "round trip ", count: 40),
            inset: NSSize(width: 14, height: 10)
        )
        // `intrinsicContentSize` reads the LIVE tracked container, so give
        // the view a real frame first — exactly what SwiftUI does before
        // AppKit ever asks for the intrinsic size. Measurement itself is
        // side-effect-free and must agree with the tracked geometry.
        view.setFrameSize(NSSize(width: 360, height: 100))
        view.layoutSubtreeIfNeeded()
        let computed = view.computeHeight(forWidth: 360)

        XCTAssertEqual(view.intrinsicContentSize.height, computed, accuracy: 0.5)
    }

    // MARK: - Memoization must miss on every mutation

    func testSameLengthDifferentContentRecomputes() {
        // Equal UTF-16 length (7), different line counts. The length-keyed
        // memo returned the single-line height for the four-line content.
        let view = makeView("abc def")
        let singleLine = view.computeHeight(forWidth: 400)

        view.setScrubbedAttributedString(attributed("a\nb\nc\nd"))
        let fourLines = view.computeHeight(forWidth: 400)

        XCTAssertGreaterThan(fourLines, singleLine + 10)
    }

    func testSameCharactersDifferentFontRecomputes() {
        // Models the async highlight upgrade: identical characters, fonts
        // swapped underneath (bold/italic variants, or here a larger size).
        let view = makeView("identical characters")
        let small = view.computeHeight(forWidth: 400)

        view.setScrubbedAttributedString(attributed("identical characters", pointSize: 28))
        let large = view.computeHeight(forWidth: 400)

        XCTAssertGreaterThan(large, small)
    }

    func testIncrementalAppendRecomputes() {
        let view = makeView("streaming prefix,")
        let before = view.computeHeight(forWidth: 400)

        let grown = attributed("streaming prefix,\nnew line\nanother line")
        XCTAssertEqual(view.applyAttributedStringPreferringIncremental(grown), .incremental)
        let after = view.computeHeight(forWidth: 400)

        XCTAssertGreaterThan(after, before + 10)
    }

    func testInsetChangeAloneRecomputes() {
        let view = makeView("inset flips late")
        let before = view.computeHeight(forWidth: 400)

        view.textContainerInset = NSSize(width: 14, height: 10)
        let after = view.computeHeight(forWidth: 400)

        XCTAssertEqual(after, before + 20, accuracy: 1.0)
    }
}
