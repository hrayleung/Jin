import XCTest
import AppKit
import SwiftMath

/// End-to-end verification of the Jin SwiftMath-fork math additions
/// (`\overset`/`\underset`/`\stackrel`, native `\boxed`, `\:` spacing) and a
/// regression guard that existing constructs still typeset.
///
/// `MTMathImage.asImage()` runs the full pipeline — parse → tokenize → the
/// new `makeOverUnderSet`/`makeBox` → display construction — to compute the
/// image size, and `tiffRepresentation` forces the draw handler (exercising
/// `MTBoxDisplay.draw` / limit stacking). A nil error + non-empty rasterized
/// image means the construct renders without crashing.
final class SwiftMathForkConstructsTests: XCTestCase {

    private func assertRenders(_ latex: String, file: StaticString = #filePath, line: UInt = #line) {
        let image = MTMathImage(latex: latex, fontSize: 16, textColor: .black, labelMode: .display, textAlignment: .left)
        let (error, nsImage) = image.asImage()
        XCTAssertNil(error, "‘\(latex)’ failed to parse/typeset: \(error?.localizedDescription ?? "")", file: file, line: line)
        guard let nsImage else {
            XCTFail("‘\(latex)’ produced no image", file: file, line: line)
            return
        }
        XCTAssertGreaterThan(nsImage.size.width, 0, "‘\(latex)’ has zero width", file: file, line: line)
        XCTAssertGreaterThan(nsImage.size.height, 0, "‘\(latex)’ has zero height", file: file, line: line)
        // Force the drawing handler so MTBoxDisplay.draw / limit stacking runs.
        XCTAssertNotNil(nsImage.tiffRepresentation, "‘\(latex)’ failed to rasterize", file: file, line: line)
    }

    // MARK: - New constructs

    func testOverset() { assertRenders("\\overset{def}{=}") }
    func testUnderset() { assertRenders("\\underset{x \\to 0}{\\lim}") }
    func testStackrel() { assertRenders("\\stackrel{?}{=}") }
    func testOversetWithOuterScript() { assertRenders("\\overset{a}{b}^{2}") }
    func testBoxedDisplay() { assertRenders("\\boxed{x = 5}") }
    func testBoxedInExpression() { assertRenders("a = \\boxed{5} + 1") }
    func testBoxedNestedFraction() { assertRenders("\\boxed{\\frac{a}{b}}") }
    func testMediumSpaceColon() { assertRenders("a \\: b") }

    // MARK: - Regression: existing constructs must still render

    func testFraction() { assertRenders("\\frac{1}{2}") }
    func testSqrt() { assertRenders("\\sqrt{2}") }
    func testSumLimits() { assertRenders("\\sum_{i=1}^{n} i") }
    func testMatrix() { assertRenders("\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}") }
    func testOverline() { assertRenders("\\overline{x}") }
    func testThinSpace() { assertRenders("a \\, b") }
    func testAligned() { assertRenders("\\begin{aligned} x &= 1 \\\\ y &= 2 \\end{aligned}") }
    func testRK4Formula() { assertRenders("y_{n+1} = y_n + \\frac{h}{6}(k_1 + 2k_2 + 2k_3 + k_4)") }
}
