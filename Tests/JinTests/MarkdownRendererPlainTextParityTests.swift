import Foundation
import Markdown
import XCTest
@testable import Jin

/// Tier-3: the renderer's `NativeAnchorLayout.flatText` (the source of truth
/// for selection / persisted-highlight offsets and copy text) must carry the
/// same visible content as the parsed document itself. Documents containing
/// inline-math syntax are skipped: inline math legitimately collapses a
/// `$…$` span into one U+FFFC attachment character, which has no stable
/// textual expansion to compare against.
@MainActor
final class MarkdownRendererPlainTextParityTests: XCTestCase {
    private static let productionParseOptions: ParseOptions = [.parseBlockDirectives, .parseSymbolLinks]

    func testFlatTextMatchesDocumentWalkForMathFreeCorpus() {
        let theme = MarkdownTheme.resolved(appFontFamily: "", codeFontFamily: "")
        for entry in MarkdownTextLossCorpus.documents where !entry.containsInlineMathSyntax {
            let key = NativeMarkdownCache.Key(
                markdownText: entry.text,
                isStreaming: false,
                renderPlainText: false,
                appFontFamily: "",
                codeFontFamily: ""
            )
            let parsed = NativeMarkdownCache.compute(key: key, theme: theme)

            let prepared = MarkdownRenderPreparation.prepareForRender(entry.text, isStreaming: false).text
            let preprocessed = MarkdownExtensionPreprocessor.preprocess(prepared)
            let document = Document(parsing: preprocessed, options: Self.productionParseOptions)
            let expected = MarkdownTextLossAudit.textOnlyWalk(document, skipMermaid: true)

            if let violation = MarkdownTextLossAudit.compareContentSkeletons(
                reference: expected,
                actual: parsed.layout.flatText
            ) {
                XCTFail("[\(entry.name)] flatText parity failed:\n\(violation)")
            }
        }
    }

    func testProseGroupsKeepAttributedStringAndPlainTextAligned() {
        // The offset contract behind selection & highlights: for every prose
        // group, the attributed string's characters ARE the plain text.
        let theme = MarkdownTheme.resolved(appFontFamily: "", codeFontFamily: "")
        for entry in MarkdownTextLossCorpus.documents where !entry.containsInlineMathSyntax {
            let key = NativeMarkdownCache.Key(
                markdownText: entry.text,
                isStreaming: false,
                renderPlainText: false,
                appFontFamily: "",
                codeFontFamily: ""
            )
            let parsed = NativeMarkdownCache.compute(key: key, theme: theme)
            for group in parsed.groups {
                if case let .prose(attributed, plainText, _, _) = group {
                    XCTAssertEqual(
                        attributed.string,
                        plainText,
                        "[\(entry.name)] prose group attributedString/plainText diverged"
                    )
                }
            }
        }
    }
}
