import AppKit
import XCTest
@testable import Jin

/// Off-live-width probes are answered on a SEPARATE layout manager (the
/// per-view shadow one, or — while a storage edit is in flight — the isolated
/// `JinTextMeasurementStack`) instead of by resizing the live text container,
/// which is what crashed. That is only safe if the separate manager wraps
/// EXACTLY like the live view — a one-line disagreement becomes a clipped
/// row, i.e. trading a crash for the bug family this branch exists to fix.
///
/// Each case measures a width two ways: through the live container (drive the
/// view's frame to that width first, then measure in place) and through the
/// off-width path (measure while the live container sits somewhere else). They
/// must agree exactly. The isolated stack's own parity is pinned here for the
/// code gutter and, against a live view, by
/// `JinMessageTextViewEditReentrancyTests`.
@MainActor
final class JinTextMeasurementParityTests: XCTestCase {

    private func makeView(_ attributed: NSAttributedString, inset: NSSize = .zero) -> JinMessageTextView {
        let view = JinMessageTextView()
        view.setScrubbedAttributedString(attributed)
        view.textContainerInset = inset
        return view
    }

    /// Height at `width` measured with the live container ALREADY at `width`.
    private func liveHeight(_ attributed: NSAttributedString, inset: NSSize, width: CGFloat) -> CGFloat {
        let view = makeView(attributed, inset: inset)
        view.setFrameSize(NSSize(width: width, height: 10))
        view.layoutSubtreeIfNeeded()
        return view.computeHeight(forWidth: width)
    }

    /// Height at `width` measured while the live container sits somewhere
    /// else — the isolated-stack path.
    private func probedHeight(_ attributed: NSAttributedString, inset: NSSize, width: CGFloat) -> CGFloat {
        let view = makeView(attributed, inset: inset)
        view.setFrameSize(NSSize(width: width * 0.5 + 37, height: 10))
        view.layoutSubtreeIfNeeded()
        return view.computeHeight(forWidth: width)
    }

    private func assertParity(
        _ attributed: NSAttributedString,
        inset: NSSize = .zero,
        widths: [CGFloat] = [280, 421, 640, 784, 1_120],
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for width in widths {
            let live = liveHeight(attributed, inset: inset, width: width)
            let probed = probedHeight(attributed, inset: inset, width: width)
            XCTAssertEqual(
                probed,
                live,
                accuracy: 0.5,
                "\(label) @\(width)pt: isolated stack says \(probed), live container says \(live) "
                    + "— a measurement that disagrees with render is a clipped or gapped row",
                file: file,
                line: line
            )
            XCTAssertGreaterThan(live, 0, "\(label) @\(width)pt measured nothing", file: file, line: line)
        }
    }

    // MARK: - Cases

    func testPlainProseParity() {
        assertParity(
            NSAttributedString(
                string: String(repeating: "resolution-dependent DiT scaling and VAE behaviour. ", count: 40),
                attributes: [.font: NSFont.systemFont(ofSize: 14)]
            ),
            label: "plain-prose"
        )
    }

    func testCJKParity() {
        assertParity(
            NSAttributedString(
                string: String(repeating: "总体判断：这个写法比上一版扎实得多，但分数和理由脱钩了。", count: 30),
                attributes: [.font: NSFont.systemFont(ofSize: 14)]
            ),
            label: "cjk"
        )
    }

    /// The custom layout manager's line-break delegate protects short
    /// bilingual parentheticals — the isolated stack uses the same subclass,
    /// so this must not drift.
    func testBilingualParentheticalParity() {
        assertParity(
            NSAttributedString(
                string: String(
                    repeating: "推理模型（reasoning model）会先思考再回答，thinking block 会折叠起来。",
                    count: 25
                ),
                attributes: [.font: NSFont.systemFont(ofSize: 14)]
            ),
            label: "bilingual-parenthetical"
        )
    }

    func testMixedFontRunsParity() {
        let mixed = NSMutableAttributedString(
            string: String(repeating: "body text with ", count: 40),
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        )
        var location = 5
        while location + 10 < mixed.length {
            mixed.addAttributes(
                [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .jinInlineCodeBackground: NSColor.gray.withAlphaComponent(0.2),
                ],
                range: NSRange(location: location, length: 9)
            )
            location += 61
        }
        assertParity(mixed, label: "mixed-font-runs")
    }

    /// Code blocks carry a (14, 10) inset — the inset round-trip has to hold
    /// on the isolated path too.
    func testInsetViewParity() {
        assertParity(
            NSAttributedString(
                string: String(repeating: "func measure(width: CGFloat) -> CGFloat { return 0 }\n", count: 30),
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]
            ),
            inset: NSSize(width: 14, height: 10),
            label: "code-inset"
        )
    }

    func testParagraphStyleParity() {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.35
        style.paragraphSpacing = 8
        style.firstLineHeadIndent = 12
        style.headIndent = 12
        assertParity(
            NSAttributedString(
                string: String(repeating: "indented paragraph with spacing 段落。", count: 40),
                attributes: [.font: NSFont.systemFont(ofSize: 14), .paragraphStyle: style]
            ),
            label: "paragraph-style"
        )
    }

    /// `naturalWidth` takes the same isolated path when probed off-width.
    func testNaturalWidthParity() {
        let attributed = NSAttributedString(
            string: "single line that should not wrap at ten thousand points",
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        )
        let live = makeView(attributed)
        live.setFrameSize(NSSize(width: 10_000, height: 10))
        live.layoutSubtreeIfNeeded()
        let liveWidth = live.naturalWidth(maxWidth: 10_000)

        let probed = makeView(attributed)
        probed.setFrameSize(NSSize(width: 300, height: 10))
        probed.layoutSubtreeIfNeeded()
        let probedWidth = probed.naturalWidth(maxWidth: 10_000)

        XCTAssertEqual(probedWidth, liveWidth, accuracy: 0.5)
        XCTAssertLessThan(liveWidth, 9_000, "natural width must be the text's, not the container's")
    }

    /// The code gutter is sized off the isolated stack now (its representable
    /// used to write line numbers into the live storage from `sizeThatFits`,
    /// the same layout-time mutation that crashed the message text views). Its
    /// size must still equal what the live gutter view reports, or the code
    /// block's columns shift.
    func testCodeGutterSizeParity() {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        for count in [1, 9, 10, 99, 100, 512] {
            let numbers = CodeLineNumberGutter.attributedNumbers(count: count, font: font)
            let inset = NSSize(width: 8, height: 10)

            let live = CodeLineNumberTextView()
            live.textContainerInset = inset
            guard let storage = live.textStorage else {
                return XCTFail("gutter text view has no storage — the comparison would be empty")
            }
            storage.setAttributedString(numbers)
            let liveSize = live.naturalSize()

            let measured = JinTextMeasurementStack.size(
                of: numbers,
                token: JinTextMeasurementStack.Token(key: "gutter-test:\(count)", version: 0),
                inset: inset
            )

            XCTAssertEqual(measured.width, liveSize.width, accuracy: 0.5, "gutter width @\(count) lines")
            XCTAssertEqual(measured.height, liveSize.height, accuracy: 0.5, "gutter height @\(count) lines")
        }
    }

    /// Measuring must not disturb the live view: the on-screen wrap width has
    /// to survive a burst of off-width probes (the previous design re-wrapped
    /// the live text at whichever probe came last).
    func testProbingDoesNotDisturbTheLiveContainer() {
        let attributed = NSAttributedString(
            string: String(repeating: "probe stability 段落 text. ", count: 60),
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        )
        let view = makeView(attributed)
        view.setFrameSize(NSSize(width: 640, height: 10))
        view.layoutSubtreeIfNeeded()
        let heightAt640 = view.computeHeight(forWidth: 640)
        let containerBefore = view.textContainer?.size.width ?? 0

        for width in [120.0, 2_000.0, 331.0, 10_000.0] as [CGFloat] {
            _ = view.computeHeight(forWidth: width)
            _ = view.naturalWidth(maxWidth: width)
        }

        XCTAssertEqual(view.textContainer?.size.width ?? 0, containerBefore, accuracy: 0.5)
        XCTAssertEqual(view.computeHeight(forWidth: 640), heightAt640, accuracy: 0.5)
        XCTAssertTrue(view.textContainer?.widthTracksTextView ?? false)
        XCTAssertTrue(view.isVerticallyResizable)
    }

    /// A stack token is a cheap SUMMARY of the content (signature or character
    /// hash + length) and is blind to ATTRIBUTES. Same characters in a bigger
    /// font — an app font-size change, a theme swap, a highlight upgrade —
    /// mint the identical token, so a token-only hit test would answer the new
    /// content with the old content's layout and size every affected row
    /// wrong.
    func testAttributeOnlyChangeUnderTheSameTokenIsNotServedFromTheOldLayout() {
        let text = String(repeating: "同じ文字列 with identical characters throughout. ", count: 12)
        let small = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let large = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 28)])

        // Deliberately the SAME token for both: this is exactly what
        // `AttributedTextBlock` mints when only attributes changed.
        let token = JinTextMeasurementStack.Token(key: "attr-collision", version: UInt64(small.length))

        let smallHeight = JinTextMeasurementStack.height(of: small, token: token, containerWidth: 400)
        let largeHeight = JinTextMeasurementStack.height(of: large, token: token, containerWidth: 400)

        XCTAssertGreaterThan(
            largeHeight,
            smallHeight * 1.5,
            "28pt text measured \(largeHeight)pt, barely more than the 12pt measurement "
                + "(\(smallHeight)pt) — the stack answered from the previous content's layout"
        )
        // And back again, so the check is not one-directional.
        XCTAssertEqual(
            JinTextMeasurementStack.height(of: small, token: token, containerWidth: 400),
            smallHeight,
            accuracy: 0.5
        )
    }

    /// The flip side: repeated probes of the SAME content must still hit, or
    /// the fix above would reintroduce the per-probe full-text copy that made
    /// scrolling lag.
    func testRepeatedProbesOfTheSameContentDoNotRecopy() {
        let attributed = NSAttributedString(
            string: String(repeating: "steady content. ", count: 40),
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        )
        let token = JinTextMeasurementStack.Token(key: "steady", version: UInt64(attributed.length))
        _ = JinTextMeasurementStack.height(of: attributed, token: token, containerWidth: 500)

        let copiesBefore = JinTextMeasurementStack.copyCount
        for width in [500.0, 320.0, 800.0, 500.0] as [CGFloat] {
            _ = JinTextMeasurementStack.height(of: attributed, token: token, containerWidth: width)
        }
        XCTAssertEqual(
            JinTextMeasurementStack.copyCount,
            copiesBefore,
            "re-probing identical content copied the string again"
        )
    }
}
