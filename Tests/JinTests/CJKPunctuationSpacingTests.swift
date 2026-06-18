import AppKit
import XCTest
@testable import Jin

/// Verifies the fullwidth-CJK-bracket tightening pass: it must reassign each
/// bracket character to a font carrying the AAT half-width (`kTextSpacingType`
/// / `kHalfWidthTextSelector`, i.e. type 22 / selector 2) feature, leave
/// everything else alone, never change the underlying characters, and skip
/// inline code. A companion layout assertion confirms the feature actually
/// compresses the glyph's advance when the render font is full-width PingFang.
final class CJKPunctuationSpacingTests: XCTestCase {

    private let body = NSFont.systemFont(ofSize: 14)

    private func halfWidthFeature(of font: NSFont) -> (type: Int, selector: Int)? {
        guard let settings = font.fontDescriptor.fontAttributes[.featureSettings] as? [[NSFontDescriptor.FeatureKey: Any]] else {
            return nil
        }
        for setting in settings {
            if let type = setting[.typeIdentifier] as? Int,
               let selector = setting[.selectorIdentifier] as? Int {
                return (type, selector)
            }
        }
        return nil
    }

    func testAssignsHalfWidthFeatureToFullwidthBrackets() {
        let string = "生态（HDFS、YARN）。"
        let attributed = NSMutableAttributedString(string: string, attributes: [.font: body])
        CJKPunctuationSpacing.apply(to: attributed)

        let ns = string as NSString
        let openIndex = ns.range(of: "（").location
        let closeIndex = ns.range(of: "）").location

        for index in [openIndex, closeIndex] {
            let font = attributed.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            XCTAssertNotNil(font, "bracket at \(index) must keep a font")
            let feature = halfWidthFeature(of: font!)
            XCTAssertEqual(feature?.type, 22, "bracket must use kTextSpacingType")
            XCTAssertEqual(feature?.selector, 2, "bracket must use kHalfWidthTextSelector")
        }
    }

    func testLeavesNonBracketCharactersUntouched() {
        let string = "生态（HDFS）"
        let attributed = NSMutableAttributedString(string: string, attributes: [.font: body])
        CJKPunctuationSpacing.apply(to: attributed)

        let ns = string as NSString
        for label in ["生", "H", "态"] {
            let i = ns.range(of: label).location
            let font = attributed.attribute(.font, at: i, effectiveRange: nil) as? NSFont
            XCTAssertNil(halfWidthFeature(of: font!), "'\(label)' should not get the spacing feature")
        }
        // Characters themselves are never rewritten.
        XCTAssertEqual(attributed.string, string)
    }

    func testIdeographicCommaAndPeriodAreNotTouched() {
        // Sentence punctuation is intentionally out of scope.
        let string = "甲、乙。丙"
        let attributed = NSMutableAttributedString(string: string, attributes: [.font: body])
        CJKPunctuationSpacing.apply(to: attributed)
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            XCTAssertNil(halfWidthFeature(of: value as! NSFont))
        }
    }

    func testSkipsBracketsInsideInlineCode() {
        let string = "（x）"
        let attributed = NSMutableAttributedString(string: string, attributes: [.font: body])
        // Mark the whole span as inline code the way the inline renderer does.
        attributed.addAttribute(.jinInlineCodeBackground, value: NSColor.gray, range: NSRange(location: 0, length: attributed.length))
        CJKPunctuationSpacing.apply(to: attributed)

        let ns = string as NSString
        let openIndex = ns.range(of: "（").location
        let font = attributed.attribute(.font, at: openIndex, effectiveRange: nil) as? NSFont
        XCTAssertNil(halfWidthFeature(of: font!), "inline-code brackets must keep full-width metrics")
    }

    func testNoBracketsIsANoOp() {
        let string = "纯中文段落没有括号 plus some ascii."
        let attributed = NSMutableAttributedString(string: string, attributes: [.font: body])
        let before = NSAttributedString(attributedString: attributed)
        CJKPunctuationSpacing.apply(to: attributed)
        XCTAssertTrue(attributed.isEqual(to: before))
    }

    func testIsIdempotent() {
        let string = "生态（HDFS）"
        let attributed = NSMutableAttributedString(string: string, attributes: [.font: body])
        CJKPunctuationSpacing.apply(to: attributed)
        let once = NSAttributedString(attributedString: attributed)
        // Running again must not stack features or otherwise mutate the result.
        CJKPunctuationSpacing.apply(to: attributed)
        XCTAssertTrue(attributed.isEqual(to: once), "second apply should be a no-op")
    }

    func testAppliedConvenienceReturnsSameInstanceWhenNoBrackets() {
        let plain = NSAttributedString(string: "no brackets here", attributes: [.font: body])
        XCTAssertTrue(CJKPunctuationSpacing.applied(to: plain) === plain, "should avoid copying bracket-free text")
    }

    func testAppliedConvenienceFixesBrackets() {
        let plain = NSAttributedString(string: "x（y）", attributes: [.font: body])
        let fixed = CJKPunctuationSpacing.applied(to: plain)
        XCTAssertFalse(fixed === plain)
        let i = (fixed.string as NSString).range(of: "（").location
        let font = fixed.attribute(.font, at: i, effectiveRange: nil) as? NSFont
        XCTAssertEqual(halfWidthFeature(of: font!)?.selector, 2)
    }

    /// Integration: the plain-text / native-text message path builds a *raw*
    /// `InlineRun` that bypasses the inline renderer and folds through
    /// `NativeMarkdownGroupBuilder` with `fontOverride == nil`. The folded prose
    /// must still tighten its brackets.
    func testFoldedRawParagraphRunGetsBracketFix() {
        let theme = MarkdownTheme.resolved(appFontFamily: "", codeFontFamily: "")
        let run = InlineRun(
            attributedString: NSAttributedString(string: "生态（HDFS）", attributes: [.font: theme.bodyFont]),
            plainText: "生态（HDFS）",
            linkURLs: []
        )
        let groups = NativeMarkdownGroupBuilder.build(blocks: [.paragraph(run)], theme: theme)
        guard case let .prose(attributedString, _, _, _)? = groups.first else {
            return XCTFail("expected a prose group")
        }
        let i = (attributedString.string as NSString).range(of: "（").location
        let font = attributedString.attribute(.font, at: i, effectiveRange: nil) as? NSFont
        XCTAssertEqual(halfWidthFeature(of: font!)?.type, 22, "folded raw paragraph bracket must be tightened")
        XCTAssertEqual(halfWidthFeature(of: font!)?.selector, 2)
    }

    /// The half-width feature must survive `NSTextStorage`'s `processEditing`
    /// font fixing (CJK substitution), which is what runs when the string lands
    /// in a real `JinMessageTextView`. If fixing stripped the feature, the
    /// brackets would silently revert to full-width in the live view.
    func testFeatureSurvivesTextStorageFontFixing() {
        let string = "态（H）这"
        let attributed = NSMutableAttributedString(string: string, attributes: [.font: body])
        CJKPunctuationSpacing.apply(to: attributed)

        let storage = NSTextStorage(attributedString: attributed)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 1000, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)

        let ns = string as NSString
        for bracket in ["（", "）"] {
            let i = ns.range(of: bracket).location
            let font = storage.attribute(.font, at: i, effectiveRange: nil) as? NSFont
            XCTAssertEqual(halfWidthFeature(of: font!)?.type, 22, "\(bracket) lost the feature after fixing")
            XCTAssertEqual(halfWidthFeature(of: font!)?.selector, 2, "\(bracket) lost the feature after fixing")
        }
    }

    /// End-to-end: when the bracket's render font is full-width PingFang SC
    /// (the locale that triggers the bug), the half-width feature must actually
    /// compress the laid-out advance from a full em to a half em.
    func testHalfWidthFeatureCompressesAdvanceUnderPingFang() throws {
        guard let pingfang = NSFont(name: "PingFangSC-Regular", size: 14) else {
            throw XCTSkip("PingFang SC unavailable on this host")
        }
        let probe = "态（H"
        func parenAdvance(applyFix: Bool) -> CGFloat {
            let attributed = NSMutableAttributedString(string: probe, attributes: [.font: pingfang])
            if applyFix { CJKPunctuationSpacing.apply(to: attributed) }
            let storage = NSTextStorage(attributedString: attributed)
            let layout = NSLayoutManager()
            storage.addLayoutManager(layout)
            let container = NSTextContainer(size: NSSize(width: 1000, height: CGFloat.greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)
            let parenX = layout.location(forGlyphAt: layout.glyphIndexForCharacter(at: 1)).x
            let nextX = layout.location(forGlyphAt: layout.glyphIndexForCharacter(at: 2)).x
            return nextX - parenX
        }
        let baseline = parenAdvance(applyFix: false)
        let fixed = parenAdvance(applyFix: true)
        XCTAssertEqual(baseline, 14, accuracy: 0.5, "fullwidth PingFang （ should advance a full em")
        XCTAssertLessThan(fixed, baseline - 4, "half-width feature should noticeably compress （")
    }
}
