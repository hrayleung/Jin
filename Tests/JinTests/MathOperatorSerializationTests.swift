import AppKit
import SwiftMath
import XCTest
@testable import Jin

@MainActor
final class MathOperatorSerializationTests: XCTestCase {
    func testCustomOperatorSurvivesDisplayLabelAssignment() throws {
        // The crash report follows prepare → MTMathUILabel.mathList →
        // mathListToString. Image-only rendering never exercises that setter.
        let source = #"\operatorname{softmax}(x) = \frac{e^x}{\sum_i e^{x_i}}"#
        guard case .rendered(let list) = MathRenderer.prepare(source) else {
            return XCTFail("Expected the custom operator to parse")
        }

        let label = MTMathUILabel()
        label.labelMode = .display
        label.mathList = list

        XCTAssertTrue(label.mathList === list)
        XCTAssertTrue(label.latex.contains(#"\operatorname{softmax}"#))
        let size = label.sizeThatFits(CGSize(width: 600, height: 0))
        XCTAssertTrue(size.width.isFinite && size.width > 0)
        XCTAssertTrue(size.height.isFinite && size.height > 0)
    }

    func testCustomOperatorsRoundTripWithScriptsAndLimits() throws {
        for source in [
            #"\operatorname{ReLU}"#,
            #"\operatorname{softmax}_i^j"#,
            #"\operatorname*{argmax}_{x}^{n}"#,
            #"\operatorname{rank}\limits_{A}"#,
            #"\operatorname*{argmin}\nolimits_{x}"#,
            #"\operatorname{\text{arg max}}_{x}"#,
            #"\operatorname{a\_b\%\{x\}\backslash}"#,
            #"\operatorname{\text{归一化}}"#
        ] {
            let serialized = try assertOperatorRoundTrip(source)
            XCTAssertTrue(serialized.hasPrefix(#"\operatorname"#), source)
        }
    }

    func testCustomOperatorsSharingOrdinarySymbolNamesRemainOperators() throws {
        // A successful reverse lookup must not force-cast a variable/relation
        // to MTLargeOperator or discard the operator's scripts and limits.
        for source in [
            #"\operatorname{\alpha}_{i}"#,
            #"\operatorname*{\in}_{i}^{n}"#,
            #"\operatorname{\{}"#
        ] {
            let serialized = try assertOperatorRoundTrip(source)
            XCTAssertTrue(serialized.hasPrefix(#"\operatorname"#), source)
        }
    }

    func testBuiltInOperatorsKeepCommandsAndLimitOverrides() throws {
        for source in [
            #"\sum_{i=1}^{n}"#,
            #"\sum\nolimits_i^n"#,
            #"\int_0^1"#,
            #"\int\limits_0^1"#,
            #"\sin"#,
            #"\sin\limits_x"#,
            #"\lim\nolimits_{x}"#,
            #"\operatorname{sin}"#,
            #"\operatorname{lim}_{x}"#
        ] {
            let serialized = try assertOperatorRoundTrip(source)
            XCTAssertFalse(serialized.contains("operatorname"), source)
        }
    }

    func testNestedOperatorsRenderInDisplayLabelsAndInlineImages() throws {
        for source in [
            #"\frac{\operatorname{tr}(A)}{\operatorname{rank}(A)}"#,
            #"\sum_{i=1}^{n}\operatorname{ReLU}(x_i)"#,
            #"\underbrace{\operatorname{softmax}(x)}_{\operatorname{normalization}}"#,
            #"\begin{aligned}y&=\operatorname{softmax}(x)\\z&=\operatorname*{argmax}_i y_i\end{aligned}"#
        ] {
            guard case .rendered(let list) = MathRenderer.prepare(source) else {
                XCTFail("Expected the formula to parse: \(source)")
                continue
            }
            let label = MTMathUILabel()
            label.mathList = list
            let size = label.sizeThatFits(CGSize(width: 600, height: 0))
            XCTAssertTrue(size.width.isFinite && size.width > 0, source)
            XCTAssertTrue(size.height.isFinite && size.height > 0, source)
            XCTAssertNotNil(MTMathListBuilder.build(fromString: label.latex), source)

            let renderer = MTMathImage(latex: source, fontSize: 16, textColor: .black, labelMode: .text)
            let (error, image) = renderer.asImage()
            XCTAssertNil(error, source)
            XCTAssertNotNil(try XCTUnwrap(image).tiffRepresentation, source)
        }
    }

    func testIncompleteOperatorsKeepRawSourceFallback() {
        for source in [#"\operatorname"#, #"\operatorname*{"#, #"\operatorname{}"#, #"\operatorname{softmax"#] {
            guard case .raw(let original) = MathRenderer.prepare(source) else {
                XCTFail("Expected raw source for \(source)")
                continue
            }
            XCTAssertEqual(original, source)
        }
    }

    @discardableResult
    private func assertOperatorRoundTrip(
        _ source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let list = try XCTUnwrap(MTMathListBuilder.build(fromString: source), source, file: file, line: line)
        let original = try XCTUnwrap(list.atoms.first as? MTLargeOperator, source, file: file, line: line)
        let serialized = MTMathListBuilder.mathListToString(list)
        let reparsed = try XCTUnwrap(MTMathListBuilder.build(fromString: serialized), serialized, file: file, line: line)
        XCTAssertEqual(reparsed.atoms.count, 1, source, file: file, line: line)
        let restored = try XCTUnwrap(reparsed.atoms.first as? MTLargeOperator, serialized, file: file, line: line)
        XCTAssertEqual(restored.nucleus, original.nucleus, source, file: file, line: line)
        XCTAssertEqual(restored.limits, original.limits, source, file: file, line: line)
        XCTAssertEqual(
            MTMathListBuilder.mathListToString(restored.subScript),
            MTMathListBuilder.mathListToString(original.subScript),
            source, file: file, line: line
        )
        XCTAssertEqual(
            MTMathListBuilder.mathListToString(restored.superScript),
            MTMathListBuilder.mathListToString(original.superScript),
            source, file: file, line: line
        )
        return serialized
    }
}
