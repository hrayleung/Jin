import XCTest
@testable import Jin

final class MarkdownSyntaxHighlighterTests: XCTestCase {
    private let theme: MarkdownTheme = .resolved(appFontFamily: "", codeFontFamily: "")

    func testSwiftKeywordsClassified() {
        let attr = MarkdownSyntaxHighlighter.highlight(
            "func greet() { let name = \"world\" }",
            language: "swift",
            theme: theme
        )
        XCTAssertEqual(attr.string, "func greet() { let name = \"world\" }")
        // Spot-check: "func" should not have the same color as plain "name".
        let funcRange = (attr.string as NSString).range(of: "func")
        let nameRange = (attr.string as NSString).range(of: "name")
        let funcColor = attr.attribute(.foregroundColor, at: funcRange.location, effectiveRange: nil) as? NSColor
        let nameColor = attr.attribute(.foregroundColor, at: nameRange.location, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(funcColor)
        XCTAssertNotNil(nameColor)
        XCTAssertNotEqual(funcColor, nameColor)
    }

    func testUnknownLanguageRendersPlain() {
        let attr = MarkdownSyntaxHighlighter.highlight("hello", language: "klingon", theme: theme)
        XCTAssertEqual(attr.string, "hello")
    }

    func testLanguageAliasNormalizes() {
        XCTAssertEqual(LanguageAliases.normalize("ts"), "typescript")
        XCTAssertEqual(LanguageAliases.normalize("py"), "python")
        XCTAssertEqual(LanguageAliases.normalize("sh"), "bash")
        XCTAssertEqual(LanguageAliases.normalize("yml"), "yaml")
    }

    func testEmptySourceProducesEmpty() {
        let attr = MarkdownSyntaxHighlighter.highlight("", language: "swift", theme: theme)
        XCTAssertEqual(attr.string, "")
    }
}
