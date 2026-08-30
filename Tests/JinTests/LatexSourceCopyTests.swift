import AppKit
import XCTest
@testable import Jin

@MainActor
final class LatexSourceCopyTests: XCTestCase {

    private let font = NSFont.systemFont(ofSize: 14)

    // MARK: - Display source

    func testDelimitedDisplaySourceWrapsAndTrims() {
        XCTAssertEqual(
            LatexSourceCopy.delimitedDisplaySource("  a+b  \n"),
            "$$\na+b\n$$"
        )
    }

    func testDelimitedDisplaySourcePreservesInnerNewlines() {
        let inner = "x &= 1 \\\\\ny &= 2"
        XCTAssertEqual(
            LatexSourceCopy.delimitedDisplaySource(inner),
            "$$\n\(inner)\n$$"
        )
    }

    func testDelimitedDisplaySourceEmptyStillDelimits() {
        XCTAssertEqual(LatexSourceCopy.delimitedDisplaySource("   \n"), "$$\n\n$$")
    }

    // MARK: - Click vs drag

    func testPlainClickIsAccepted() {
        XCTAssertTrue(
            LatexSourceCopy.isClick(
                dragDistanceSquared: 0,
                clickCount: 1,
                modifierFlags: []
            )
        )
    }

    func testClickWithinSlopIsAccepted() {
        let slop = LatexSourceCopy.clickSlop
        XCTAssertTrue(
            LatexSourceCopy.isClick(
                dragDistanceSquared: slop * slop,
                clickCount: 1,
                modifierFlags: []
            )
        )
    }

    func testDragPastSlopIsRejected() {
        let slop = LatexSourceCopy.clickSlop
        XCTAssertFalse(
            LatexSourceCopy.isClick(
                dragDistanceSquared: slop * slop + 0.01,
                clickCount: 1,
                modifierFlags: []
            )
        )
    }

    func testDoubleClickIsRejected() {
        XCTAssertFalse(
            LatexSourceCopy.isClick(
                dragDistanceSquared: 0,
                clickCount: 2,
                modifierFlags: []
            )
        )
    }

    func testShiftClickIsRejected() {
        XCTAssertFalse(
            LatexSourceCopy.isClick(
                dragDistanceSquared: 0,
                clickCount: 1,
                modifierFlags: .shift
            )
        )
    }

    func testCommandClickIsRejected() {
        XCTAssertFalse(
            LatexSourceCopy.isClick(
                dragDistanceSquared: 0,
                clickCount: 1,
                modifierFlags: .command
            )
        )
    }

    func testMulticharacterFallbackSelectionStillCountsAsClick() {
        // Parse-failure `$…$` is many glyphs; AppKit selecting the run must
        // not suppress the popover.
        XCTAssertTrue(
            LatexSourceCopy.isClick(
                dragDistanceSquared: 0,
                clickCount: 1,
                modifierFlags: []
            )
        )
    }

    func testCapsLockDoesNotRejectClick() {
        XCTAssertTrue(
            LatexSourceCopy.isClick(
                dragDistanceSquared: 0,
                clickCount: 1,
                modifierFlags: .capsLock
            )
        )
    }

    // MARK: - Reopen suppression

    func testSameIdentityInsideWindowIsSuppressed() {
        let view = NSView()
        let identity = LatexSourceCopy.PresentationIdentity.of(view, charIndex: 3)
        let now: CFAbsoluteTime = 100
        XCTAssertTrue(
            LatexSourceCopy.shouldSuppressReopen(
                now: now,
                lastClose: (identity, now - 0.1),
                presenting: identity
            )
        )
    }

    func testDifferentGlyphIsNotSuppressed() {
        let view = NSView()
        let closed = LatexSourceCopy.PresentationIdentity.of(view, charIndex: 3)
        let presenting = LatexSourceCopy.PresentationIdentity.of(view, charIndex: 7)
        XCTAssertFalse(
            LatexSourceCopy.shouldSuppressReopen(
                now: 100,
                lastClose: (closed, 99.9),
                presenting: presenting
            )
        )
    }

    func testExpiredWindowIsNotSuppressed() {
        let view = NSView()
        let identity = LatexSourceCopy.PresentationIdentity.of(view, charIndex: nil)
        XCTAssertFalse(
            LatexSourceCopy.shouldSuppressReopen(
                now: 100,
                lastClose: (identity, 100 - LatexSourceCopy.reopenSuppressionWindow - 0.01),
                presenting: identity
            )
        )
    }

    func testNilLastCloseIsNotSuppressed() {
        let view = NSView()
        XCTAssertFalse(
            LatexSourceCopy.shouldSuppressReopen(
                now: 100,
                lastClose: nil,
                presenting: .of(view, charIndex: nil)
            )
        )
    }

    // MARK: - Source attribute lookup

    func testSourceAtMathGlyph() {
        let composed = NSMutableAttributedString(string: "ab", attributes: [.font: font])
        composed.insert(mathGlyph(source: "$x^2$"), at: 1)
        XCTAssertEqual(LatexSourceCopy.source(at: 1, in: composed), "$x^2$")
        XCTAssertNil(LatexSourceCopy.source(at: 0, in: composed))
        XCTAssertNil(LatexSourceCopy.source(at: 2, in: composed))
        XCTAssertNil(LatexSourceCopy.source(at: -1, in: composed))
        XCTAssertNil(LatexSourceCopy.source(at: 99, in: composed))
    }

    func testEmptySourceAttributeIsIgnored() {
        let glyph = mathGlyph(source: "")
        XCTAssertNil(LatexSourceCopy.source(at: 0, in: glyph))
    }

    // MARK: - Hit testing

    func testHitTestFindsMathGlyphAndRejectsNeighboringProse() {
        let view = makeLaidOutView()
        guard let mathRect = mathGlyphRect(in: view) else {
            XCTFail("expected a laid-out math glyph")
            return
        }

        let hit = LatexSourceCopy.inlineMathHit(
            at: NSPoint(x: mathRect.midX, y: mathRect.midY),
            in: view
        )
        XCTAssertEqual(hit?.source, "$x$")
        XCTAssertEqual(hit?.charIndex, 7) // "before " is 7 UTF-16 units

        let miss = LatexSourceCopy.inlineMathHit(
            at: NSPoint(x: 2, y: mathRect.midY),
            in: view
        )
        XCTAssertNil(miss, "a click on leading prose must not snap to the math glyph")
    }

    func testHitTestRejectsEmptyView() {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        XCTAssertNil(LatexSourceCopy.inlineMathHit(at: NSPoint(x: 10, y: 10), in: view))
    }

    func testHitTestFindsFallbackTextRunInTheMiddle() {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 40))
        view.textContainer?.containerSize = NSSize(width: 500, height: 1_000_000)
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = .zero

        let original = "$(x_0, y_0)$"
        let run = NSMutableAttributedString(string: original, attributes: [.font: font])
        run.addAttribute(
            .jinInlineMathSource,
            value: original,
            range: NSRange(location: 0, length: run.length)
        )
        let composed = NSMutableAttributedString(string: "go ", attributes: [.font: font])
        composed.append(run)
        view.textStorage?.setAttributedString(composed)
        if let layoutManager = view.layoutManager, let container = view.textContainer {
            layoutManager.ensureLayout(for: container)
        }

        let glyphRange = NSRange(location: 3, length: (original as NSString).length)
        let rect = view.layoutManager!.boundingRect(
            forGlyphRange: glyphRange,
            in: view.textContainer!
        )
        let origin = view.textContainerOrigin
        let point = NSPoint(x: rect.midX + origin.x, y: rect.midY + origin.y)
        XCTAssertEqual(
            LatexSourceCopy.inlineMathHit(at: point, in: view)?.source,
            original
        )
    }

    func testHitTestRejectsLinkedMath() {
        let view = makeLaidOutView(linkMath: true)
        guard let mathRect = mathGlyphRect(in: view) else {
            XCTFail("expected a laid-out math glyph")
            return
        }
        XCTAssertNil(
            LatexSourceCopy.inlineMathHit(
                at: NSPoint(x: mathRect.midX, y: mathRect.midY),
                in: view
            )
        )
    }

    // MARK: - Popover layout

    func testShortSourceGetsCompactPopover() {
        let layout = LatexSourceCopy.popoverLayout(for: "$x$")
        XCTAssertGreaterThanOrEqual(layout.size.width, LatexSourceCopy.PopoverChrome.minOuterWidth)
        XCTAssertLessThan(layout.size.width, LatexSourceCopy.PopoverChrome.maxOuterWidth)
        XCTAssertEqual(
            layout.sourceWidth,
            layout.size.width - LatexSourceCopy.PopoverChrome.padding * 2
        )
        XCTAssertFalse(layout.sourceNeedsScroll)
        XCTAssertGreaterThan(layout.size.height, 40)
        XCTAssertLessThan(layout.size.height, 120)
    }

    func testLongSourceIsCappedAndScrolls() {
        let long = String(repeating: "\\frac{a}{b} + ", count: 80)
        let layout = LatexSourceCopy.popoverLayout(for: long)
        let chrome = LatexSourceCopy.PopoverChrome.self
        XCTAssertEqual(layout.size.width, chrome.maxOuterWidth)
        XCTAssertEqual(layout.sourceWidth, chrome.maxOuterWidth - chrome.padding * 2)
        XCTAssertTrue(layout.sourceNeedsScroll)
        XCTAssertEqual(layout.sourceMaxHeight, chrome.maxSourceHeight)
        XCTAssertGreaterThan(layout.size.height, layout.sourceMaxHeight)
        XCTAssertLessThanOrEqual(
            layout.size.height,
            chrome.maxSourceHeight + 90
        )
    }

    func testDisplaySourceLayoutFitsSeveralLinesWithoutScroll() {
        let source = LatexSourceCopy.delimitedDisplaySource("\\mu_1 = [1,1]^{T}")
        let layout = LatexSourceCopy.popoverLayout(for: source)
        XCTAssertFalse(layout.sourceNeedsScroll)
        XCTAssertGreaterThan(layout.sourceMaxHeight, 30)
    }

    /// Regression: `$$\nformula\n$$` must not layout as a single line of
    /// opening delimiters (the popover used to clip to `$$...`).
    func testDisplayMathPopoverHeightIncludesInnerFormula() {
        let inner = "f'(\\xi) = \\frac{f(b) - f(a)}{b-a}"
        let source = LatexSourceCopy.delimitedDisplaySource(inner)
        XCTAssertTrue(source.hasPrefix("$$\n"))
        XCTAssertTrue(source.contains("\\frac"))
        XCTAssertTrue(source.hasSuffix("\n$$"))

        let layout = LatexSourceCopy.popoverLayout(for: source)
        let oneLine = LatexSourceCopy.measureSource("$x$", maxWidth: 400).height
        XCTAssertGreaterThan(
            layout.sourceMaxHeight,
            oneLine * 2,
            "display math is three lines; clipping to the opening $$ is the $$... bug"
        )
        XCTAssertFalse(layout.sourceNeedsScroll)
    }

    func testMeasureSourceCountsNewlines() {
        let one = LatexSourceCopy.measureSource("$x$", maxWidth: 400)
        let three = LatexSourceCopy.measureSource("$$\nx^2\n$$", maxWidth: 400)
        XCTAssertGreaterThan(three.height, one.height * 2)
        XCTAssertLessThan(three.width, 400)
    }

    func testDragDistanceSquared() {
        XCTAssertEqual(
            LatexSourceCopy.dragDistanceSquared(
                from: NSPoint(x: 0, y: 0),
                to: NSPoint(x: 3, y: 4)
            ),
            25
        )
    }

    // MARK: - Fixtures

    private func mathGlyph(source: String, size: NSSize = NSSize(width: 40, height: 16)) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = NSImage(size: size)
        attachment.bounds = CGRect(origin: .zero, size: size)
        let s = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
        let full = NSRange(location: 0, length: s.length)
        s.addAttribute(.font, value: font, range: full)
        s.addAttribute(.jinInlineMathSource, value: source, range: full)
        return s
    }

    private func makeLaidOutView(linkMath: Bool = false) -> NSTextView {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 40))
        view.textContainer?.containerSize = NSSize(width: 500, height: 1_000_000)
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = .zero

        let composed = NSMutableAttributedString(string: "before ", attributes: [.font: font])
        let glyph = NSMutableAttributedString(attributedString: mathGlyph(source: "$x$"))
        if linkMath {
            glyph.addAttribute(.link, value: URL(string: "https://example.com")!, range: NSRange(location: 0, length: glyph.length))
        }
        composed.append(glyph)
        composed.append(NSAttributedString(string: " after", attributes: [.font: font]))
        view.textStorage?.setAttributedString(composed)
        if let layoutManager = view.layoutManager, let container = view.textContainer {
            layoutManager.ensureLayout(for: container)
        }
        return view
    }

    private func mathGlyphRect(in view: NSTextView) -> CGRect? {
        guard let layoutManager = view.layoutManager,
              let textContainer = view.textContainer,
              let storage = view.textStorage else { return nil }
        var found: CGRect?
        storage.enumerateAttribute(
            .jinInlineMathSource,
            in: NSRange(location: 0, length: storage.length),
            options: []
        ) { value, range, stop in
            guard value is String else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let origin = view.textContainerOrigin
            found = rect.offsetBy(dx: origin.x, dy: origin.y)
            stop.pointee = true
        }
        return found
    }
}
