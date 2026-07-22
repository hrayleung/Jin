import Foundation
import XCTest
@testable import Jin

/// Tier-1: `MarkdownRenderPreparation.repairMarkdown` must preserve content
/// exactly — it may insert whitespace/ZWSP and inline-completion closers
/// (`*`, `_`, `~`, `` ` ``), delete backslashes (unescape) and whitespace,
/// and nothing else. Runs over the full corpus (including pending-fix
/// documents: the known bugs live downstream of repair, so repair itself
/// must already be loss-free on them) and over streaming prefixes.
final class MarkdownRepairCharacterAuditTests: XCTestCase {
    private func auditRepair(
        _ text: String,
        name: String,
        isStreaming: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let output = MarkdownRenderPreparation.repairMarkdown(text, isStreaming: isStreaming)
        if let violation = MarkdownTextLossAudit.auditRepair(input: text, output: output) {
            XCTFail("[\(name)] streaming=\(isStreaming) repair audit failed:\n\(violation)", file: file, line: line)
        }
        XCTAssertFalse(
            MarkdownTextLossAudit.placeholderResidue(in: output),
            "[\(name)] streaming=\(isStreaming) inline-code placeholder leaked into repair output",
            file: file,
            line: line
        )
    }

    func testRepairPreservesContentOnFullDocuments() {
        for entry in MarkdownTextLossCorpus.allDocuments {
            auditRepair(entry.text, name: entry.name, isStreaming: false)
            auditRepair(entry.text, name: entry.name, isStreaming: true)
        }
    }

    func testRepairPreservesContentOnEveryStreamingPrefix() {
        for entry in MarkdownTextLossCorpus.allDocuments {
            for length in MarkdownTextLossAudit.prefixSampleLengths(for: entry.text) {
                let prefix = MarkdownTextLossAudit.prefix(entry.text, length: length)
                auditRepair(prefix, name: "\(entry.name)#prefix\(length)", isStreaming: true)
            }
        }
    }

    func testPreparedOutputHasNoPlaceholderResidue() {
        for entry in MarkdownTextLossCorpus.allDocuments {
            let prepared = MarkdownRenderPreparation.prepareForRender(entry.text, isStreaming: false).text
            XCTAssertFalse(
                MarkdownTextLossAudit.placeholderResidue(in: prepared),
                "[\(entry.name)] placeholder scalar leaked through prepareForRender"
            )
        }
    }

    func testCorruptedPlaceholderFallsBackToOriginalLine() {
        // Inject a transform that destroys the placeholder's closing scalar —
        // restoration then can't find it. The fail-safe must return the
        // ORIGINAL line rather than leaking PUA junk / dropping the code.
        let line = "前缀 `code span` 后缀"
        let mangled = MarkdownRenderPreparation.preserveInlineCode(in: line) { sanitized in
            sanitized.replacingOccurrences(of: "\u{F0001}", with: "")
        }
        XCTAssertEqual(mangled, line)
    }

    func testInputContainingPlaceholderScalarsSkipsProtection() {
        // Adversarial input that already contains our PUA scalars must not
        // collide with minted placeholders (which would duplicate content).
        let line = "异常\u{F0000}JIN_CODE_0\u{F0001}文本 `code` 结尾"
        let result = MarkdownRenderPreparation.preserveInlineCode(in: line) { $0 }
        XCTAssertEqual(result, line)
    }

    func testEscapedBacktickDoesNotOpenProtectedSpan() {
        let line = #"prefix \`literal###heading` suffix"#
        let result = MarkdownRenderPreparation.preserveInlineCode(in: line) { candidate in
            candidate.replacingOccurrences(of: "###heading", with: "\n### heading")
        }

        XCTAssertEqual(result, #"prefix \`literal"# + "\n" + #"### heading` suffix"#)
    }

    func testBackticksAfterEscapedBacktickStillFormDelimiterRun() {
        let line = "prefix \\`" + "``protected`` suffix"
        let result = MarkdownRenderPreparation.preserveInlineCode(in: line) { candidate in
            candidate.replacingOccurrences(of: "protected", with: "changed")
        }

        XCTAssertEqual(result, line)
    }
}
