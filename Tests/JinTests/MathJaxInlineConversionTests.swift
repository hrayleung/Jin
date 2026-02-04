import MathJaxSwift
import XCTest

final class MathJaxInlineConversionTests: XCTestCase {
    func testMathJaxConvertsMathcalInline() throws {
        let mathjax = try MathJax(preferredOutputFormat: .svg)
        var conversionError: Error?
        let svg = mathjax.tex2svg(
            #"\mathcal{S}_V"#,
            styles: false,
            conversionOptions: ConversionOptions(display: false),
            inputOptions: TeXInputProcessorOptions(),
            error: &conversionError
        )

        if conversionError != nil {
            XCTFail("Expected MathJax conversion without error, got: \(String(describing: conversionError))")
        }
        XCTAssertTrue(svg.contains("<svg"))
    }
}
