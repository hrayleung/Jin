import SwiftUI

/// Dispatcher used by `NativeMarkdownView` once a markdown document has been
/// grouped by `NativeMarkdownGroupBuilder`. Each case picks the right
/// SwiftUI view for its payload — `prose` flows into the aggregated
/// `ProseGroupView` (one `NSTextView` per group), while complex lists and
/// blockquotes fall back to the legacy per-block `ListView` / `BlockQuoteView`
/// path (still per-paragraph `NSTextView`s, but those code paths are rare).
struct NativeGroupView: View {
    let group: NativeMarkdownGroup
    let path: [Int]

    var body: some View {
        switch group {
        case .prose(let attributedString, let plainText, let linkURLs, let signature):
            ProseGroupView(
                attributedString: attributedString,
                plainText: plainText,
                linkURLs: linkURLs,
                path: path,
                contentSignature: signature
            )

        case .codeBlock(let language, let source, let isStreamingTail, _):
            CodeBlockView(
                language: language,
                source: source,
                isStreamingTail: isStreamingTail
            )

        case .table(let header, let alignments, let rows, _):
            MarkdownTableView(header: header, alignments: alignments, rows: rows)

        case .math(let latex, _):
            MathBlockView(latex: latex)

        case .mermaid(let source, _):
            MermaidBlockView(source: source)

        case .htmlBlock(let text, _):
            HTMLBlockView(text: text)

        case .thematicBreak:
            ThematicBreakView()

        case .complexList(let kind, let start, let items, let tight, _):
            switch kind {
            case .bullet:
                BulletListView(items: items, tight: tight, path: path)
            case .ordered:
                OrderedListView(start: start, items: items, tight: tight, path: path)
            }

        case .complexBlockQuote(let children, _):
            BlockQuoteView(children: children, path: path)
        }
    }
}
