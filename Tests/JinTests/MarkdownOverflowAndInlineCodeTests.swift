import AppKit
import SwiftUI
import XCTest
@testable import Jin

@MainActor
final class MarkdownOverflowAndInlineCodeTests: XCTestCase {
    private let theme = MarkdownTheme.resolved(appFontFamily: "", codeFontFamily: "")

    private func render(_ source: String, streaming: Bool = false) -> [NativeMarkdownBlock] {
        NativeMarkdownCache.compute(
            key: .init(
                markdownText: source,
                isStreaming: streaming,
                renderPlainText: false,
                appFontFamily: "",
                codeFontFamily: ""
            ),
            theme: theme
        ).blocks
    }

    // MARK: - Fenced latex/tex vs display math

    func testFencedLatexProseBlockRendersAsCodeBlockNotMathBlock() {
        let roseParagraph = """
        Rose also has a large upfront tuning cost. The paper reports 0.8\\% and 2.3\\% net overhead, which only looks small because it is divided by 24--28 hours of full training to convergence. The tuning step actually takes 1,998~s to 4,615~s.
        """
        let markdown = """
        Here is the revised paragraph:

        ```latex
        \(roseParagraph)
        ```
        """

        let blocks = render(markdown)
        XCTAssertEqual(blocks.count, 2)
        guard case .codeBlock(let language, let source, _) = blocks[1] else {
            return XCTFail("Expected ```latex fence to render as .codeBlock, got \(blocks[1])")
        }
        XCTAssertEqual(language, "latex")
        XCTAssertTrue(source.contains("0.8\\%"))
        XCTAssertTrue(source.contains("1,998~s"))
    }

    func testFencedTexBlockRendersAsCodeBlockNotMathBlock() {
        let markdown = """
        ```tex
        Figure~\\ref{fig:ray-kernel-limits} shows that GPU resource demand varies across operations.
        ```
        """

        let blocks = render(markdown)
        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let language, let source, _) = blocks[0] else {
            return XCTFail("Expected ```tex fence to render as .codeBlock, got \(blocks[0])")
        }
        XCTAssertEqual(language, "tex")
        XCTAssertTrue(source.contains("\\ref{fig:ray-kernel-limits}"))
    }

    func testMathFenceAndDisplayDelimitersStillRenderAsMathBlock() {
        let markdown = """
        ```math
        E = mc^2
        ```

        $$
        \\sum_{i=1}^n x_i
        $$

        \\[
        \\int_0^1 x^2 \\, dx = \\frac{1}{3}
        \\]
        """

        let blocks = render(markdown)
        XCTAssertEqual(blocks.count, 3)
        for (idx, block) in blocks.enumerated() {
            guard case .mathBlock = block else {
                return XCTFail("Expected block \(idx) to be .mathBlock, got \(block)")
            }
        }
    }

    // MARK: - Wrapped inline-code pill segments

    func testSingleLineInlineCodeProducesOneFullyRoundedSegment() {
        let (layout, storage, container, codeRange) = makeInlineCodeLayout(
            prefix: "Use ",
            code: "fully utilize",
            suffix: " here.",
            containerWidth: 400,
            headIndent: 0
        )

        let glyphRange = layout.glyphRange(forCharacterRange: codeRange, actualCharacterRange: nil)
        let segments = layout.inlineCodePillSegments(
            forGlyphRange: glyphRange,
            in: container,
            storage: storage,
            origin: .zero
        )

        XCTAssertEqual(segments.count, 1)
        XCTAssertTrue(segments[0].roundLeft)
        XCTAssertTrue(segments[0].roundRight)
        XCTAssertLessThan(segments[0].rect.maxX, 250, "Single-line pill should hug its glyphs, not stretch to margin")
    }

    func testWrappedInlineCodeInIndentedListItemHugsGlyphsAndOpensInteriorEdges() {
        // Reproduces the list-item wrap: prefix fills most of line 1, causing
        // `interleave functions to fully utilize` to split across line 1 and line 2
        // with a 24pt list headIndent on line 2.
        let headIndent: CGFloat = 24
        let containerWidth: CGFloat = 260
        let (layout, storage, container, codeRange) = makeInlineCodeLayout(
            prefix: "1. 改成 ",
            code: "interleave functions to fully utilize",
            suffix: " 最准确。",
            containerWidth: containerWidth,
            headIndent: headIndent
        )

        let glyphRange = layout.glyphRange(forCharacterRange: codeRange, actualCharacterRange: nil)
        let segments = layout.inlineCodePillSegments(
            forGlyphRange: glyphRange,
            in: container,
            storage: storage,
            origin: .zero
        )

        guard segments.count == 2 else {
            return XCTFail("Expected inline code to wrap into 2 line segments, got \(segments.count)")
        }
        let first = segments[0]
        let second = segments[1]

        // CSS box-decoration-break: slice semantics:
        // First segment closes left, opens right; second segment opens left, closes right.
        XCTAssertTrue(first.roundLeft)
        XCTAssertFalse(first.roundRight)
        XCTAssertFalse(second.roundLeft)
        XCTAssertTrue(second.roundRight)

        // Second segment must align with the indented list text, NOT x = 0 in the gutter.
        XCTAssertGreaterThanOrEqual(
            second.rect.minX,
            headIndent - 2.0,
            "Wrapped inline-code segment on line 2 must not extend into the list headIndent gutter"
        )
        // First segment must not stretch past container width.
        XCTAssertLessThanOrEqual(first.rect.maxX, containerWidth)
        // Second segment should hug "utilize", well short of the full container width.
        XCTAssertLessThan(second.rect.maxX, containerWidth - 60)
    }

    func testThreeLineWrappedInlineCodeOpensMiddleSegmentOnBothSides() {
        let (layout, storage, container, codeRange) = makeInlineCodeLayout(
            prefix: "Call ",
            code: "interleave_functions_across_gpu_streams_to_fully_utilize_compute_and_memory_bandwidth_efficiently",
            suffix: " now.",
            containerWidth: 220,
            headIndent: 0
        )

        let glyphRange = layout.glyphRange(forCharacterRange: codeRange, actualCharacterRange: nil)
        let segments = layout.inlineCodePillSegments(
            forGlyphRange: glyphRange,
            in: container,
            storage: storage,
            origin: .zero
        )

        XCTAssertGreaterThanOrEqual(segments.count, 3)
        XCTAssertTrue(segments.first!.roundLeft)
        XCTAssertFalse(segments.first!.roundRight)
        for middle in segments.dropFirst().dropLast() {
            XCTAssertFalse(middle.roundLeft)
            XCTAssertFalse(middle.roundRight)
        }
        XCTAssertFalse(segments.last!.roundLeft)
        XCTAssertTrue(segments.last!.roundRight)
    }

    // MARK: - Wide display math containment

    func testWideDisplayMathNeverExceedsProposedBubbleWidth() {
        let wideEquation = """
        \\begin{pmatrix}
        a_{1,1} & a_{1,2} & a_{1,3} & a_{1,4} & a_{1,5} & a_{1,6} & a_{1,7} & a_{1,8} \\\\
        b_{2,1} & b_{2,2} & b_{2,3} & b_{2,4} & b_{2,5} & b_{2,6} & b_{2,7} & b_{2,8}
        \\end{pmatrix}
        = \\sum_{k=1}^{N} \\frac{\\alpha_k \\beta_k + \\gamma_k \\delta_k}{\\sqrt{1 + \\lambda_k^2}}
        """
        let proposedWidth: CGFloat = 280
        let view = MathBlockView(latex: wideEquation)
            .environment(\.markdownTheme, theme)
            .frame(width: proposedWidth)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: proposedWidth, height: 400)
        host.layoutSubtreeIfNeeded()

        XCTAssertLessThanOrEqual(
            host.fittingSize.width,
            proposedWidth + 1.0,
            "Wide display math block must not expand wider than its proposed container width"
        )
    }

    // MARK: - Helpers

    private func makeInlineCodeLayout(
        prefix: String,
        code: String,
        suffix: String,
        containerWidth: CGFloat,
        headIndent: CGFloat
    ) -> (JinMarkdownLayoutManager, NSTextStorage, NSTextContainer, NSRange) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = headIndent
        paragraphStyle.lineBreakMode = .byWordWrapping

        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: theme.bodyFont,
            .foregroundColor: theme.baseColor,
            .paragraphStyle: paragraphStyle,
        ]
        var codeAttrs = bodyAttrs
        codeAttrs[.font] = theme.codeFont
        codeAttrs[.jinInlineCodeBackground] = theme.inlineCodeBackground
        codeAttrs[.jinInlineCodeBorder] = theme.inlineCodeBorder

        let attributed = NSMutableAttributedString(string: prefix, attributes: bodyAttrs)
        let codeStart = attributed.length
        attributed.append(NSAttributedString(string: code, attributes: codeAttrs))
        let codeRange = NSRange(location: codeStart, length: attributed.length - codeStart)
        attributed.append(NSAttributedString(string: suffix, attributes: bodyAttrs))

        let storage = NSTextStorage(attributedString: attributed)
        let layout = JinMarkdownLayoutManager()
        let container = NSTextContainer(size: NSSize(width: containerWidth, height: 10_000))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)

        return (layout, storage, container, codeRange)
    }
}
