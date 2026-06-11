import Foundation
import Markdown
import XCTest
@testable import Jin

/// Shared auditing helpers for the no-text-loss invariant suites.
///
/// Three tiers of protection, weakest precondition first:
///
/// - **Tier 1 (repair audit)**: `MarkdownRenderPreparation.repairMarkdown` may
///   only insert whitespace/ZWSP and the inline-completion closer characters
///   (`*`, `_`, `~`, `` ` ``), and may only delete backslashes (unescape) and
///   whitespace. Everything else must survive in order. Checked by an exact
///   two-pointer walk over whitespace-free "skeletons".
/// - **Tier 2 (end-to-end parse equivalence)**: the text-only walk of the
///   repaired + preprocessed document must contain exactly the same letters,
///   digits, CJK, and ordinary punctuation as the walk of the raw document.
///   Markdown syntax characters are excluded on both sides (repairs
///   legitimately convert literal markers into consumed markup and vice
///   versa). A separate heading-preservation rule catches structural
///   swallows (prose reclassified into math/code blocks) that character
///   comparison alone cannot see.
/// - **Tier 3 (renderer parity)**: the renderer's `flatText` (selection /
///   highlight offset source of truth) must agree with the Tier-2 walk.
enum MarkdownTextLossAudit {
    // MARK: - Skeletons

    /// Characters that never count as content: all whitespace, the ZWSP the
    /// CJK emphasis repair inserts, and variation selectors.
    static func skeleton(_ string: String) -> [Character] {
        string.filter { char in
            !char.isWhitespace && !Self.invisibleScalars.contains(char)
        }
    }

    private static let invisibleScalars: Set<Character> = ["\u{200B}", "\u{FE0F}", "\u{FE0E}"]

    /// Markdown syntax characters excluded from Tier-2/Tier-3 comparison.
    /// Repairs and parsing legitimately create or consume these (auto-closed
    /// `**`, list markers, fences, math delimiters, link syntax), so they
    /// cannot participate in an exact content comparison. Loss of *content*
    /// is still caught: letters, digits, CJK, and ordinary punctuation
    /// (，。：；！？% quotes…) all remain.
    ///
    /// Beyond the obvious markers, four asymmetry classes force extra
    /// exclusions (each stripped from BOTH sides, so the comparison stays
    /// symmetric — the cost is blindness to losing exactly these glyphs):
    /// - `:` — table delimiter cells (`| :--- |`) are visible text in an
    ///   unrepaired/truncated document but syntax once the table parses;
    ///   the fullwidth CJK `：` is unaffected and still compared.
    /// - `–`/`—` — cmark smart punctuation turns prose `--`/`---` into
    ///   dashes, while repair may turn the same run into a thematic break.
    /// - `•`/`◦`/`☑`/`☐` — the prose-group fold writes list markers into
    ///   `plainText` by contract (selection offsets include them).
    static let syntaxCharacters: Set<Character> = [
        "*", "_", "~", "`", "#", "\\", "$", "|", "-", ">", "+", "[", "]", "(", ")",
        ":", "–", "—", "•", "◦", "☑", "☐",
    ]

    /// `skeleton` minus syntax characters, with one carve-out: a digit run
    /// immediately followed by `.` or `)` is dropped together with that
    /// delimiter, because repairs legitimately convert prose like `…。1. 内容`
    /// into an ordered list whose marker digits become syntax. The rule is
    /// applied to both sides of every comparison, so it stays symmetric
    /// (e.g. version numbers like `2.5` lose the `2.` on both sides).
    static func contentSkeleton(_ string: String) -> [Character] {
        let chars = Array(string)
        var result: [Character] = []
        result.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isNumber {
                var end = i
                while end < chars.count, chars[end].isNumber { end += 1 }
                if end < chars.count, chars[end] == "." || chars[end] == ")" {
                    i = end + 1 // drop digits + delimiter
                    continue
                }
                while i < end {
                    result.append(chars[i])
                    i += 1
                }
                continue
            }
            if !c.isWhitespace, !invisibleScalars.contains(c), !syntaxCharacters.contains(c) {
                result.append(c)
            }
            i += 1
        }
        return result
    }

    // MARK: - Violations

    struct Violation: CustomStringConvertible {
        let message: String
        let expectedContext: String
        let actualContext: String

        var description: String {
            """
            \(message)
              expected …\(expectedContext)…
              actual   …\(actualContext)…
            """
        }
    }

    private static func context(_ chars: [Character], around index: Int, radius: Int = 40) -> String {
        guard !chars.isEmpty else { return "(empty)" }
        let lower = max(0, index - radius)
        let upper = min(chars.count, index + radius)
        return String(chars[lower..<upper])
    }

    // MARK: - Tier 1: repair audit

    /// Characters the repair pipeline may insert (beyond whitespace/ZWSP,
    /// which the skeleton already ignores): inline-completion closers and
    /// auto-closed fences.
    static let repairInsertionWhitelist: Set<Character> = ["*", "_", "~", "`"]

    /// Two-pointer ordered-subsequence audit of one repair stage.
    /// Returns nil when `output` preserves `input` content.
    static func auditRepair(input: String, output: String) -> Violation? {
        let inSkel = skeleton(input)
        let outSkel = skeleton(output)
        var i = 0
        var j = 0
        while i < inSkel.count {
            if j < outSkel.count, outSkel[j] == inSkel[i] {
                i += 1
                j += 1
                continue
            }
            if inSkel[i] == "\\" {
                // Unescape may delete backslashes.
                i += 1
                continue
            }
            if j < outSkel.count, repairInsertionWhitelist.contains(outSkel[j]) {
                j += 1
                continue
            }
            return Violation(
                message: "repair lost or reordered content at input index \(i) / output index \(j)",
                expectedContext: context(inSkel, around: i),
                actualContext: context(outSkel, around: j)
            )
        }
        while j < outSkel.count {
            guard repairInsertionWhitelist.contains(outSkel[j]) else {
                return Violation(
                    message: "repair inserted non-whitelisted character '\(outSkel[j])' at output index \(j)",
                    expectedContext: context(inSkel, around: inSkel.count),
                    actualContext: context(outSkel, around: j)
                )
            }
            j += 1
        }
        return nil
    }

    /// The inline-code placeholder scalars must never leak out of the repair.
    static func placeholderResidue(in string: String) -> Bool {
        string.unicodeScalars.contains { $0.value == 0xF0000 || $0.value == 0xF0001 }
    }

    // MARK: - Tier 2: text-only document walks

    /// Concatenated visible text of a parsed document. Maps every node kind
    /// that carries text; container nodes recurse. Symmetric by construction:
    /// both the raw and the repaired document run through the same walk.
    static func textOnlyWalk(_ document: Document, skipMermaid: Bool = false) -> String {
        var out = ""
        walk(document, into: &out, includeCodeBlocks: true, skipMermaid: skipMermaid)
        return out
    }

    /// Like `textOnlyWalk` but excludes fenced code/HTML blocks — used to
    /// check that prose stays prose (a paragraph swallowed into a ```math
    /// fence disappears from this walk even though its characters survive).
    static func proseOnlyWalk(_ document: Document) -> String {
        var out = ""
        walk(document, into: &out, includeCodeBlocks: false, skipMermaid: true)
        return out
    }

    private static func walk(
        _ markup: any Markup,
        into out: inout String,
        includeCodeBlocks: Bool,
        skipMermaid: Bool
    ) {
        switch markup {
        case let text as Markdown.Text:
            out.append(text.string)
        case let code as InlineCode:
            out.append(code.code)
        case let code as CodeBlock:
            let language = code.language?.lowercased()
            if skipMermaid, language == "mermaid" { return }
            if includeCodeBlocks { out.append(code.code) }
        case let html as InlineHTML:
            out.append(html.rawHTML)
        case let html as HTMLBlock:
            if includeCodeBlocks { out.append(html.rawHTML) }
        case is SoftBreak:
            out.append(" ")
        case is LineBreak:
            out.append("\n")
        case let symbol as SymbolLink:
            if let destination = symbol.destination { out.append(destination) }
        case let image as Markdown.Image:
            out.append(image.plainText)
        default:
            for child in markup.children {
                walk(child, into: &out, includeCodeBlocks: includeCodeBlocks, skipMermaid: skipMermaid)
            }
            if markup is BlockMarkup {
                out.append("\n")
            }
        }
    }

    /// All heading texts of a document, in order.
    static func headingTexts(_ document: Document) -> [String] {
        var result: [String] = []
        func visit(_ markup: any Markup) {
            if let heading = markup as? Heading {
                result.append(heading.plainText)
            }
            for child in markup.children { visit(child) }
        }
        visit(document)
        return result
    }

    // MARK: - Tier 2 comparison

    static func compareContentSkeletons(reference: String, actual: String) -> Violation? {
        let expected = contentSkeleton(reference)
        let got = contentSkeleton(actual)
        let limit = min(expected.count, got.count)
        var k = 0
        while k < limit, expected[k] == got[k] { k += 1 }
        if k == expected.count, k == got.count { return nil }
        if k == expected.count {
            return Violation(
                message: "rendered output contains \(got.count - k) surplus content characters",
                expectedContext: context(expected, around: k),
                actualContext: context(got, around: k)
            )
        }
        if k == got.count {
            return Violation(
                message: "rendered output lost \(expected.count - k) trailing content characters",
                expectedContext: context(expected, around: k),
                actualContext: context(got, around: k)
            )
        }
        return Violation(
            message: "content diverges at index \(k): expected '\(expected[k])', got '\(got[k])'",
            expectedContext: context(expected, around: k),
            actualContext: context(got, around: k)
        )
    }

    /// Structural rule: every heading of the reference document must survive
    /// in the actual document — either verbatim, or split (repairs may break
    /// a glued heading into a shorter heading + body, in which case the
    /// shorter heading must be a prefix of the original and the remainder
    /// must still be visible as prose).
    static func auditHeadingsPreserved(
        referenceDocument: Document,
        actualDocument: Document
    ) -> Violation? {
        let referenceHeadings = headingTexts(referenceDocument)
        guard !referenceHeadings.isEmpty else { return nil }
        let actualHeadings = headingTexts(actualDocument).map(contentSkeleton)
        let actualProse = contentSkeleton(proseOnlyWalk(actualDocument))

        for heading in referenceHeadings {
            let target = contentSkeleton(heading)
            guard !target.isEmpty else { continue }
            let survives = actualHeadings.contains { candidate in
                guard !candidate.isEmpty, candidate.count <= target.count else { return false }
                guard Array(target.prefix(candidate.count)) == candidate else { return false }
                let remainder = Array(target.dropFirst(candidate.count))
                return remainder.isEmpty || containsSubarray(actualProse, remainder)
            }
            if !survives {
                return Violation(
                    message: "heading was swallowed or rewritten: \"\(heading)\"",
                    expectedContext: String(target),
                    actualContext: actualHeadings.map { String($0) }.joined(separator: " ⏐ ")
                )
            }
        }
        return nil
    }

    static func containsSubarray(_ haystack: [Character], _ needle: [Character]) -> Bool {
        guard !needle.isEmpty else { return true }
        guard haystack.count >= needle.count else { return false }
        for start in 0...(haystack.count - needle.count) {
            var matched = true
            for offset in 0..<needle.count where haystack[start + offset] != needle[offset] {
                matched = false
                break
            }
            if matched { return true }
        }
        return false
    }

    // MARK: - Streaming prefix sampling

    /// Indices to truncate a document at when simulating mid-stream flushes.
    /// Dense around markdown-significant characters (so mid-token truncation
    /// is always exercised) plus a coarse stride elsewhere; capped so large
    /// documents stay testable.
    static func prefixSampleLengths(for text: String, maxSamples: Int = 160) -> [Int] {
        let chars = Array(text)
        guard chars.count > 1 else { return [] }
        let significant: Set<Character> = ["*", "$", "\\", "`", "#", "|", "-", "~", "(", "\n"]
        var lengths = Set<Int>()
        let stride = max(13, chars.count / 80)
        var i = stride
        while i < chars.count {
            lengths.insert(i)
            i += stride
        }
        for (index, char) in chars.enumerated() where significant.contains(char) {
            for delta in -2...2 {
                let candidate = index + delta
                if candidate > 0, candidate < chars.count {
                    lengths.insert(candidate)
                }
            }
        }
        var sorted = lengths.sorted()
        if sorted.count > maxSamples {
            // Deterministic downsample: keep an even spread.
            let step = Double(sorted.count) / Double(maxSamples)
            var sampled: [Int] = []
            var cursor = 0.0
            while Int(cursor) < sorted.count {
                sampled.append(sorted[Int(cursor)])
                cursor += step
            }
            sorted = sampled
        }
        return sorted
    }

    static func prefix(_ text: String, length: Int) -> String {
        String(Array(text).prefix(length))
    }
}
