import Foundation
import Markdown

/// Translates a `swift-markdown` `Document` into a flat array of
/// `NativeMarkdownBlock`s.
struct MarkdownASTWalker {
    let theme: MarkdownTheme
    /// When `true`, the trailing code/math/mermaid block is flagged as a
    /// streaming tail so views can suppress copy buttons / collapse pills /
    /// other affordances that don't make sense for unfinished content.
    let isStreaming: Bool

    init(theme: MarkdownTheme, isStreaming: Bool = false) {
        self.theme = theme
        self.isStreaming = isStreaming
    }

    func walk(document: Document, source: String? = nil) -> [NativeMarkdownBlock] {
        let inlineRenderer = MarkdownInlineRenderer(theme: theme, source: source)
        var blocks: [NativeMarkdownBlock] = []
        let topLevel = Array(document.blockChildren)
        for (index, child) in topLevel.enumerated() {
            let isLast = index == topLevel.count - 1
            walk(blockChild: child, inlineRenderer: inlineRenderer, isLast: isLast, into: &blocks)
        }
        return blocks
    }

    private func walk(
        blockChild: any BlockMarkup,
        inlineRenderer: MarkdownInlineRenderer,
        isLast: Bool,
        into blocks: inout [NativeMarkdownBlock]
    ) {
        switch blockChild {
        case let paragraph as Paragraph:
            blocks.append(.paragraph(inlineRenderer.render(inlineChildren: paragraph.children)))

        case let heading as Heading:
            let level = max(1, min(6, heading.level))
            blocks.append(.heading(level: level, content: inlineRenderer.render(inlineChildren: heading.children)))

        case let bullet as UnorderedList:
            let items = Array(bullet.listItems).map { walkListItem($0, inlineRenderer: inlineRenderer) }
            blocks.append(.bulletList(items: items, tight: isTightList(items: items)))

        case let ordered as OrderedList:
            let items = Array(ordered.listItems).map { walkListItem($0, inlineRenderer: inlineRenderer) }
            let start = Int(ordered.startIndex)
            blocks.append(.orderedList(start: start, items: items, tight: isTightList(items: items)))

        case let blockquote as BlockQuote:
            var inner: [NativeMarkdownBlock] = []
            let children = Array(blockquote.blockChildren)
            for (index, child) in children.enumerated() {
                let innerIsLast = index == children.count - 1
                walk(blockChild: child, inlineRenderer: inlineRenderer, isLast: innerIsLast, into: &inner)
            }
            blocks.append(.blockQuote(children: inner))

        case let codeBlock as CodeBlock:
            let language = codeBlock.language?.lowercased()
            switch language {
            case "mermaid":
                blocks.append(.mermaidBlock(source: codeBlock.code))
            case "math", "latex", "tex":
                blocks.append(.mathBlock(latex: codeBlock.code))
            default:
                blocks.append(.codeBlock(
                    language: codeBlock.language,
                    source: codeBlock.code,
                    isStreamingTail: isStreaming && isLast
                ))
            }

        case let table as Markdown.Table:
            walkTable(table, inlineRenderer: inlineRenderer, into: &blocks)

        case is ThematicBreak:
            blocks.append(.thematicBreak)

        case let html as HTMLBlock:
            // A block of nothing but `<br>` is vertical spacing, not content;
            // block spacing already covers it, so emitting a literal code box
            // reading "<br>" is strictly worse than dropping it.
            if !MarkdownHTMLLineBreak.isBreakOnlyBlock(html.rawHTML) {
                blocks.append(.htmlBlock(text: html.rawHTML))
            }

        default:
            // Any block we don't yet handle renders as a paragraph from its
            // formatted source so the user still sees the content.
            let plain = blockChild.format()
            blocks.append(.paragraph(InlineRun(
                attributedString: NSAttributedString(
                    string: plain,
                    attributes: [.font: theme.bodyFont, .foregroundColor: theme.baseColor]
                ),
                plainText: plain,
                linkURLs: []
            )))
        }
    }

    private func walkListItem(_ item: ListItem, inlineRenderer: MarkdownInlineRenderer) -> ListItemContent {
        let checkbox: Bool?
        switch item.checkbox {
        case .checked: checkbox = true
        case .unchecked: checkbox = false
        case .none: checkbox = nil
        case .some: checkbox = nil
        }

        var children: [NativeMarkdownBlock] = []
        let itemChildren = Array(item.blockChildren)
        for (index, child) in itemChildren.enumerated() {
            let innerIsLast = index == itemChildren.count - 1
            walk(blockChild: child, inlineRenderer: inlineRenderer, isLast: innerIsLast, into: &children)
        }
        return ListItemContent(checkbox: checkbox, children: children)
    }

    private func walkTable(_ table: Markdown.Table, inlineRenderer: MarkdownInlineRenderer, into blocks: inout [NativeMarkdownBlock]) {
        let alignments: [TableColumnAlignment] = table.columnAlignments.map { alignment in
            switch alignment {
            case .left: return .left
            case .center: return .center
            case .right: return .right
            case .none: return .default
            }
        }

        let headerCells = Array(table.head.cells)
        let header = headerCells.map { inlineRenderer.render(inlineChildren: $0.children) }

        var rows: [[InlineRun]] = []
        for row in table.body.rows {
            let cells = Array(row.cells)
            rows.append(cells.map { inlineRenderer.render(inlineChildren: $0.children) })
        }

        blocks.append(.table(header: header, alignments: alignments, rows: rows))
    }

    /// Tight lists have items containing only a single paragraph (no block
    /// children beyond that). swift-markdown does not expose a tightness
    /// flag directly, so we infer it.
    private func isTightList(items: [ListItemContent]) -> Bool {
        for item in items {
            if item.children.count != 1 { return false }
            guard case .paragraph = item.children.first else { return false }
        }
        return true
    }
}
