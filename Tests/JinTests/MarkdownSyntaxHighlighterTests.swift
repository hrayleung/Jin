import XCTest
@testable import Jin

final class MarkdownSyntaxHighlighterTests: XCTestCase {
    private let theme: MarkdownTheme = .resolved(appFontFamily: "", codeFontFamily: "")

    func testSwiftKeywordsClassified() {
        let attr = MarkdownSyntaxHighlighter.highlight(
            "func greet() { let name = \"world\" }",
            language: "swift",
            theme: theme,
            isDarkMode: true
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
        let attr = MarkdownSyntaxHighlighter.highlight(
            "func hello()",
            language: "klingon",
            theme: theme,
            isDarkMode: false
        )
        XCTAssertEqual(attr.string, "func hello()")
        let funcRange = (attr.string as NSString).range(of: "func")
        let helloRange = (attr.string as NSString).range(of: "hello")
        let funcColor = attr.attribute(.foregroundColor, at: funcRange.location, effectiveRange: nil) as? NSColor
        let helloColor = attr.attribute(.foregroundColor, at: helloRange.location, effectiveRange: nil) as? NSColor
        XCTAssertEqual(funcColor, helloColor)
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

    func testHighlightJSThemeNamesUseGitHubPair() {
        XCTAssertEqual(MarkdownSyntaxHighlighter.highlightJSThemeName(isDarkMode: false), "github")
        XCTAssertEqual(MarkdownSyntaxHighlighter.highlightJSThemeName(isDarkMode: true), "github-dark")
    }

    func testZigFastFallbackHighlightsKeywords() {
        let attr = MarkdownSyntaxHighlighter.highlight(
            "const std = @import(\"std\");\n// comment\n",
            language: "zig",
            theme: theme,
            isDarkMode: false,
            useFastFallback: true
        )
        XCTAssertEqual(attr.string, "const std = @import(\"std\");\n// comment\n")
        let constRange = (attr.string as NSString).range(of: "const")
        let stdRange = (attr.string as NSString).range(of: "std")
        let constColor = attr.attribute(.foregroundColor, at: constRange.location, effectiveRange: nil) as? NSColor
        let stdColor = attr.attribute(.foregroundColor, at: stdRange.location, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(constColor)
        XCTAssertNotNil(stdColor)
        XCTAssertNotEqual(constColor, stdColor)
    }

    func testHugeCodeBlockRendersPlainPastHighlightCap() {
        let source = String(repeating: "func name() {}\n", count: 4_000)
        let attr = MarkdownSyntaxHighlighter.highlight(
            source,
            language: "swift",
            theme: theme,
            isDarkMode: false
        )
        XCTAssertEqual(attr.string, source)
        let funcRange = (attr.string as NSString).range(of: "func")
        let nameRange = (attr.string as NSString).range(of: "name")
        let funcColor = attr.attribute(.foregroundColor, at: funcRange.location, effectiveRange: nil) as? NSColor
        let nameColor = attr.attribute(.foregroundColor, at: nameRange.location, effectiveRange: nil) as? NSColor
        XCTAssertEqual(funcColor, nameColor)
    }
}
