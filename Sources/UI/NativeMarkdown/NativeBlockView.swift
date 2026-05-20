import SwiftUI

/// Dispatcher: picks the right SwiftUI view for a `NativeMarkdownBlock`.
/// Used both at the top level (by `NativeMarkdownView`) and recursively
/// inside `BlockQuoteView` / `ListItemRow` for nested content.
struct NativeBlockView: View {
    let block: NativeMarkdownBlock
    let path: [Int]

    init(block: NativeMarkdownBlock, path: [Int]) {
        self.block = block
        self.path = path
    }

    var body: some View {
        switch block {
        case .paragraph(let run):
            ParagraphView(run: run, path: path)

        case .heading(let level, let run):
            HeadingView(level: level, run: run, path: path)

        case .bulletList(let items, let tight):
            BulletListView(items: items, tight: tight, path: path)

        case .orderedList(let start, let items, let tight):
            OrderedListView(start: start, items: items, tight: tight, path: path)

        case .blockQuote(let children):
            BlockQuoteView(children: children, path: path)

        case .codeBlock(let language, let source, let isStreamingTail):
            CodeBlockView(language: language, source: source, isStreamingTail: isStreamingTail)

        case .table(let header, let alignments, let rows):
            MarkdownTableView(header: header, alignments: alignments, rows: rows)

        case .thematicBreak:
            ThematicBreakView()

        case .mathBlock(let latex):
            MathBlockView(latex: latex)

        case .mermaidBlock(let source):
            MermaidBlockView(source: source)

        case .htmlBlock(let text):
            HTMLBlockView(text: text)
        }
    }
}
