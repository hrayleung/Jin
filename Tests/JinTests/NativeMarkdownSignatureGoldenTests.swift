import AppKit
import XCTest
@testable import Jin

/// Golden, content-addressable signature values for widget groups. These signatures
/// are `ForEach` IDs / cache keys: if they change, the renderer churns cached
/// NSTextViews and persisted highlight offsets drift. This pins them so the
/// `makeWidgetGroup` / `NativeMarkdownBlock.contentSignature` lockstep cannot
/// silently change a value during refactors.
@MainActor
final class NativeMarkdownSignatureGoldenTests: XCTestCase {
    private func groups(_ markdown: String) -> [NativeMarkdownGroup] {
        let theme = MarkdownTheme.resolved(appFontFamily: "", codeFontFamily: "")
        let key = NativeMarkdownCache.Key(
            markdownText: markdown,
            isStreaming: false,
            renderPlainText: false,
            appFontFamily: "",
            codeFontFamily: ""
        )
        return NativeMarkdownCache.compute(key: key, theme: theme).groups
    }

    private func widgetSignature(_ markdown: String) -> UInt64? {
        for group in groups(markdown) {
            switch group {
            case .codeBlock(_, _, _, let s),
                 .table(_, _, _, let s),
                 .math(_, let s),
                 .mermaid(_, let s),
                 .htmlBlock(_, let s),
                 .thematicBreak(let s),
                 .complexList(_, _, _, _, let s),
                 .complexBlockQuote(_, let s):
                return s
            case .prose:
                continue
            }
        }
        return nil
    }

    func testWidgetGroupSignaturesAreStable() {
        XCTAssertEqual(widgetSignature("```swift\nlet x = 1\n```"), 2047575550043147495, "codeBlock")
        XCTAssertEqual(widgetSignature("| a | b |\n|---|---|\n| 1 | 2 |"), 10245312135234498429, "table")
        XCTAssertEqual(widgetSignature("---"), 3683485007503858797, "thematicBreak")
        XCTAssertEqual(
            widgetSignature("- item\n\n  ```swift\n  let x = 1\n  ```"),
            6673050836031744132,
            "complexList"
        )
        XCTAssertEqual(
            widgetSignature("> text\n>\n> ```swift\n> let x = 1\n> ```"),
            10459471093328535523,
            "complexBlockQuote"
        )
    }
}
