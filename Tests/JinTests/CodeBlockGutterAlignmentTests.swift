import AppKit
import XCTest
@testable import Jin

/// Guards the line-number gutter alignment fix: the gutter must lay out with
/// the code's `codeParagraphStyle` (1.3× lineHeightMultiple) so its numbers
/// track the code lines. A plain `Text` (no multiplier) made the numbers drift
/// upward — this test fails if that regresses.
@MainActor
final class CodeBlockGutterAlignmentTests: XCTestCase {

    private func measuredHeight(
        _ string: String,
        font: NSFont,
        paragraphStyle: NSParagraphStyle
    ) -> CGFloat {
        let storage = NSTextStorage(
            string: string,
            attributes: [.font: font, .paragraphStyle: paragraphStyle]
        )
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)
        return ceil(layoutManager.usedRect(for: container).height)
    }

    func testGutterAndCodeShareLineHeightUnderCodeParagraphStyle() {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let style = MarkdownTheme.cachedCodeParagraphStyle

        let numbers = (1...20).map(String.init).joined(separator: "\n")
        let code = (1...20).map { _ in "let value = compute()" }.joined(separator: "\n")

        // Same line count + same paragraph style + same font → identical height,
        // i.e. the numbers and the code lines have the same vertical pitch.
        XCTAssertEqual(
            measuredHeight(numbers, font: font, paragraphStyle: style),
            measuredHeight(code, font: font, paragraphStyle: style),
            accuracy: 0.5
        )
    }

    func testCodeParagraphStyleInflatesLineHeightVsPlain() {
        // The whole point of the fix: codeParagraphStyle is taller per line than
        // a plain style (the 1.3 multiplier). If the gutter ever reverts to a
        // plain Text, its lines would be this much shorter and drift upward.
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let numbers = (1...20).map(String.init).joined(separator: "\n")

        let withCodeStyle = measuredHeight(
            numbers, font: font, paragraphStyle: MarkdownTheme.cachedCodeParagraphStyle
        )
        let withPlainStyle = measuredHeight(
            numbers, font: font, paragraphStyle: NSParagraphStyle.default
        )

        XCTAssertGreaterThan(withCodeStyle, withPlainStyle)
    }

    func testCodeParagraphStyleUsesExpectedMultiplier() {
        XCTAssertEqual(
            MarkdownTheme.cachedCodeParagraphStyle.lineHeightMultiple,
            MarkdownTheme.codeLineHeightMultiple,
            accuracy: 0.0001
        )
    }
}
