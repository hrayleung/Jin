import Foundation

/// Content-preservation invariant for the markdown repair pipeline.
///
/// Every repair stage (structural per-line repair, inline completion,
/// block-spacing normalization) must satisfy: ignoring whitespace and
/// invisible characters, the output contains every input character in
/// order, except that backslashes may be deleted (unescape) and the
/// inline-completion closer characters (`*`, `_`, `~`, `` ` ``) may be
/// inserted. Anything else is a text-swallowing bug.
///
/// `repairMarkdown` asserts this per stage in DEBUG builds; the test
/// suites run the same auditor over the regression corpus. Keeping the
/// auditor in production code means the two can never drift.
enum MarkdownRepairInvariant {
    /// Characters a repair stage may insert (beyond whitespace/invisibles).
    static let insertionWhitelist: Set<Character> = ["*", "_", "~", "`"]

    /// Invisible characters ignored on both sides: ZWSP (inserted by the
    /// CJK emphasis repair) and variation selectors.
    static let invisibleCharacters: Set<Character> = ["\u{200B}", "\u{FE0F}", "\u{FE0E}"]

    struct Violation: CustomStringConvertible {
        let stage: String
        let message: String
        let inputContext: String
        let outputContext: String

        var description: String {
            """
            repair stage '\(stage)' violated content preservation: \(message)
              input  …\(inputContext)…
              output …\(outputContext)…
            """
        }
    }

    /// Whitespace- and invisible-free character sequence.
    static func skeleton(_ string: String) -> [Character] {
        string.filter { !$0.isWhitespace && !invisibleCharacters.contains($0) }
    }

    /// Two-pointer ordered audit. Returns nil when `output` preserves
    /// `input` content under the stage rules.
    static func auditContentPreserved(
        input: String,
        output: String,
        stage: String = "repair"
    ) -> Violation? {
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
                i += 1 // unescape may delete backslashes
                continue
            }
            if j < outSkel.count, insertionWhitelist.contains(outSkel[j]) {
                j += 1 // completion may insert closers
                continue
            }
            return Violation(
                stage: stage,
                message: "lost or reordered content at input index \(i)",
                inputContext: context(inSkel, around: i),
                outputContext: context(outSkel, around: j)
            )
        }
        while j < outSkel.count {
            guard insertionWhitelist.contains(outSkel[j]) else {
                return Violation(
                    stage: stage,
                    message: "inserted non-whitelisted character '\(outSkel[j])'",
                    inputContext: context(inSkel, around: inSkel.count),
                    outputContext: context(outSkel, around: j)
                )
            }
            j += 1
        }
        return nil
    }

    /// The inline-code preservation placeholders (`U+F0000…U+F0001`) must
    /// never leak out of a repair stage.
    static func containsPlaceholderScalar(_ string: String) -> Bool {
        string.unicodeScalars.contains { $0.value == 0xF0000 || $0.value == 0xF0001 }
    }

    /// DEBUG-only stage assertion used by `repairMarkdown`.
    @inline(__always)
    static func assertStagePreservesContent(
        input: String,
        output: String,
        stage: String
    ) {
        #if DEBUG
        if let violation = auditContentPreserved(input: input, output: output, stage: stage) {
            assertionFailure(violation.description)
        }
        if containsPlaceholderScalar(output) {
            assertionFailure("repair stage '\(stage)' leaked an inline-code placeholder scalar")
        }
        #endif
    }

    private static func context(_ chars: [Character], around index: Int, radius: Int = 40) -> String {
        guard !chars.isEmpty else { return "(empty)" }
        let lower = max(0, index - radius)
        let upper = min(chars.count, index + radius)
        return String(chars[lower..<upper])
    }
}
