import Foundation
import Markdown

/// Shields inline LaTeX before CommonMark can consume its escapes, emphasis
/// markers or table pipes. The side table retains the exact source for copy
/// and unsupported-formula fallback; tokens never reach the displayed text.
enum MarkdownInlineMathPreprocessor {
    struct Result {
        let text: String
        fileprivate let prefix: String
        fileprivate let formulas: [InlineMath.Segment]

        func split(_ text: String) -> [InlineMath.Segment] {
            guard !formulas.isEmpty else { return [.text(text)] }
            var result: [InlineMath.Segment] = []
            var cursor = text.startIndex
            while let start = text.range(of: prefix, range: cursor..<text.endIndex),
                  let end = text[start.upperBound...].firstIndex(of: "Z"),
                  let index = Int(text[start.upperBound..<end]),
                  formulas.indices.contains(index) {
                if cursor < start.lowerBound {
                    result.append(.text(String(text[cursor..<start.lowerBound])))
                }
                result.append(formulas[index])
                cursor = text.index(after: end)
            }
            if cursor < text.endIndex { result.append(.text(String(text[cursor...]))) }
            return result
        }
    }

    static func prepare(_ source: String) -> Result {
        guard InlineMath.mightContainMath(source) else {
            return Result(text: source, prefix: "", formulas: [])
        }

        // Alphanumeric tokens stay in one Text node, including inside emphasis
        // and links. A per-document namespace cannot collide with user content.
        var hasher = FNVHasher()
        hasher.combine(source)
        var prefix = "JINMATH" + String(hasher.value, radix: 16) + "Z"
        if source.contains(prefix) {
            repeat {
                prefix = "JINMATH" + UUID().uuidString.replacingOccurrences(of: "-", with: "") + "Z"
            } while source.contains(prefix)
        }

        let bytes = Array(source.utf8)
        var lineStarts = [0]
        for (index, byte) in bytes.enumerated() where byte == 10 { lineStarts.append(index + 1) }
        func offset(_ location: SourceLocation) -> Int? {
            guard lineStarts.indices.contains(location.line - 1), location.column > 0 else { return nil }
            let value = lineStarts[location.line - 1] + location.column - 1
            return value <= bytes.count ? value : nil
        }

        // Let CommonMark identify code/HTML boundaries instead of guessing at
        // indentation or multiline backtick spans. Its interpretation of math
        // is ignored here; the final parse happens only after shielding math.
        var protected: [Range<Int>] = []
        var prose: [Range<Int>] = []
        func visit(_ markup: any Markup) {
            if markup is Paragraph || markup is Heading || markup is Markdown.Table,
               let range = markup.range,
               let lower = offset(range.lowerBound), let upper = offset(range.upperBound), lower < upper {
                prose.append(lower..<upper)
            }
            if markup is CodeBlock || markup is InlineCode || markup is HTMLBlock
                || markup is InlineHTML || markup is SymbolLink || markup is Image {
                if let range = markup.range,
                   let lower = offset(range.lowerBound), let upper = offset(range.upperBound), lower < upper {
                    protected.append(lower..<upper)
                }
                return
            }
            if let link = markup as? Link, let range = link.range,
               let lower = offset(range.lowerBound), let upper = offset(range.upperBound), lower < upper {
                if bytes[lower] != UInt8(ascii: "[") {
                    // Autolinks are destinations, not formula-bearing labels.
                    protected.append(lower..<upper)
                    return
                }
                let children = Array(link.children)
                if let first = children.first?.range, let last = children.last?.range,
                   let contentStart = offset(first.lowerBound), let contentEnd = offset(last.upperBound),
                   lower <= contentStart, contentStart <= contentEnd, contentEnd <= upper {
                    // A shortcut/collapsed reference uses its visible label as
                    // the lookup key. Keep it intact so tokenization cannot
                    // change which link definition it resolves to.
                    let suffix = String(decoding: bytes[contentEnd..<upper], as: UTF8.self)
                    if !suffix.contains("](") && !suffix.contains("][") {
                        protected.append(lower..<upper)
                        return
                    }
                    protected.append(lower..<contentStart)
                    protected.append(contentEnd..<upper)
                } else {
                    protected.append(lower..<upper)
                    return
                }
            }
            for child in markup.children { visit(child) }
        }
        visit(Document(parsing: source, options: [.parseSymbolLinks]))
        // Reference definitions and other non-visible source are absent from
        // the prose AST; never replace text inside their URLs or titles.
        var proseEnd = 0
        for range in prose.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if proseEnd < range.lowerBound { protected.append(proseEnd..<range.lowerBound) }
            proseEnd = max(proseEnd, range.upperBound)
        }
        if proseEnd < bytes.count { protected.append(proseEnd..<bytes.count) }
        protected.sort { $0.lowerBound < $1.lowerBound }

        var output = ""
        var formulas: [InlineMath.Segment] = []
        func appendProse(_ range: Range<Int>) {
            let prose = String(decoding: bytes[range], as: UTF8.self)
            for segment in InlineMath.split(prose) {
                switch segment {
                case .text(let text): output.append(text)
                case .math:
                    output.append("\(prefix)\(formulas.count)Z")
                    formulas.append(segment)
                }
            }
        }

        var cursor = 0
        for range in protected {
            guard range.upperBound > cursor else { continue }
            if cursor < range.lowerBound { appendProse(cursor..<range.lowerBound) }
            output.append(String(decoding: bytes[max(cursor, range.lowerBound)..<range.upperBound], as: UTF8.self))
            cursor = range.upperBound
        }
        appendProse(cursor..<bytes.count)
        return Result(text: output, prefix: prefix, formulas: formulas)
    }
}
