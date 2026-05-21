import AppKit
import Foundation

/// Builds a sequence of `NativeMarkdownGroup`s from the parsed block list.
///
/// V1 scope: collapses consecutive `.paragraph` and `.heading` blocks into a
/// single prose group rendered by one `NSTextView`. Everything else (lists,
/// blockquotes, code blocks, tables, math, mermaid, html, thematic breaks)
/// becomes its own widget group. Lists and blockquotes go through dedicated
/// `complexList` / `complexBlockQuote` cases that the renderer dispatches to
/// the legacy `BulletListView` / `OrderedListView` / `BlockQuoteView` code
/// path so we don't lose any existing behavior in the rare cases they
/// contain non-prose children.
enum NativeMarkdownGroupBuilder {
    static func build(blocks: [NativeMarkdownBlock], theme: MarkdownTheme) -> [NativeMarkdownGroup] {
        var groups: [NativeMarkdownGroup] = []
        var pendingProseBlocks: [NativeMarkdownBlock] = []

        func flushProse() {
            guard !pendingProseBlocks.isEmpty else { return }
            groups.append(makeProseGroup(blocks: pendingProseBlocks, theme: theme))
            pendingProseBlocks.removeAll(keepingCapacity: true)
        }

        for block in blocks {
            if isProseAggregatable(block) {
                pendingProseBlocks.append(block)
            } else {
                flushProse()
                groups.append(makeWidgetGroup(block: block))
            }
        }
        flushProse()
        return groups
    }

    // MARK: - Aggregation eligibility

    private static func isProseAggregatable(_ block: NativeMarkdownBlock) -> Bool {
        switch block {
        case .paragraph, .heading:
            return true
        default:
            return false
        }
    }

    // MARK: - Prose group construction

    private static func makeProseGroup(blocks: [NativeMarkdownBlock], theme: MarkdownTheme) -> NativeMarkdownGroup {
        let result = NSMutableAttributedString()
        var plainText = ""
        var translatedLinks: [LinkRange] = []
        var hasher = FNVHasher()

        for (index, block) in blocks.enumerated() {
            let isLast = index == blocks.count - 1
            switch block {
            case .paragraph(let run):
                hasher.combine("p")
                hasher.combine(run.plainText)
                appendInlineRun(
                    run,
                    paragraphStyle: MarkdownTheme.cachedBodyParagraphStyle,
                    fontOverride: nil,
                    into: result,
                    plainText: &plainText,
                    links: &translatedLinks
                )

            case .heading(let level, let content):
                hasher.combine("h\(level)")
                hasher.combine(content.plainText)
                appendInlineRun(
                    content,
                    paragraphStyle: MarkdownTheme.headingParagraphStyle(forLevel: level),
                    fontOverride: theme.headingFont(forLevel: level),
                    into: result,
                    plainText: &plainText,
                    links: &translatedLinks
                )

            default:
                continue
            }

            if !isLast {
                // Match the legacy `flatText` accumulation: a single newline
                // between blocks. The separator inherits the body paragraph
                // style so the line break behaves like a paragraph break,
                // not as a soft line break inside the previous block.
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: theme.bodyFont,
                    .foregroundColor: theme.baseColor,
                    .paragraphStyle: MarkdownTheme.cachedBodyParagraphStyle,
                ]))
                plainText.append("\n")
            }
        }

        return .prose(
            attributedString: result.copy() as! NSAttributedString,
            plainText: plainText,
            linkURLs: translatedLinks,
            signature: hasher.value
        )
    }

    private static func appendInlineRun(
        _ run: InlineRun,
        paragraphStyle: NSParagraphStyle,
        fontOverride: NSFont?,
        into result: NSMutableAttributedString,
        plainText: inout String,
        links: inout [LinkRange]
    ) {
        let startOffset = result.length
        let attr = NSMutableAttributedString(attributedString: run.attributedString)
        let fullRange = NSRange(location: 0, length: attr.length)
        if let fontOverride {
            attr.addAttribute(.font, value: fontOverride, range: fullRange)
        }
        attr.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        result.append(attr)
        plainText.append(run.plainText)
        for linkRange in run.linkURLs {
            links.append(LinkRange(
                range: NSRange(
                    location: linkRange.range.location + startOffset,
                    length: linkRange.range.length
                ),
                url: linkRange.url
            ))
        }
    }

    // MARK: - Widget groups

    private static func makeWidgetGroup(block: NativeMarkdownBlock) -> NativeMarkdownGroup {
        var hasher = FNVHasher()
        switch block {
        case .codeBlock(let language, let source, let isStreamingTail):
            hasher.combine("code-\(language ?? "")-\(isStreamingTail)")
            hasher.combine(source)
            return .codeBlock(
                language: language,
                source: source,
                isStreamingTail: isStreamingTail,
                signature: hasher.value
            )

        case .table(let header, let alignments, let rows):
            hasher.combine("table")
            for alignment in alignments {
                hasher.combine(String(describing: alignment))
            }
            for cell in header { hasher.combine(cell.plainText) }
            for row in rows {
                for cell in row { hasher.combine(cell.plainText) }
            }
            return .table(
                header: header,
                alignments: alignments,
                rows: rows,
                signature: hasher.value
            )

        case .mathBlock(let latex):
            hasher.combine("math")
            hasher.combine(latex)
            return .math(latex: latex, signature: hasher.value)

        case .mermaidBlock(let source):
            hasher.combine("mermaid")
            hasher.combine(source)
            return .mermaid(source: source, signature: hasher.value)

        case .htmlBlock(let text):
            hasher.combine("html")
            hasher.combine(text)
            return .htmlBlock(text: text, signature: hasher.value)

        case .thematicBreak:
            hasher.combine("hr")
            return .thematicBreak(signature: hasher.value)

        case .bulletList(let items, let tight):
            hasher.combine("ul-\(tight)")
            for item in items {
                hasher.combine(itemSignature(item))
            }
            return .complexList(
                kind: .bullet,
                start: 1,
                items: items,
                tight: tight,
                signature: hasher.value
            )

        case .orderedList(let start, let items, let tight):
            hasher.combine("ol-\(start)-\(tight)")
            for item in items {
                hasher.combine(itemSignature(item))
            }
            return .complexList(
                kind: .ordered,
                start: start,
                items: items,
                tight: tight,
                signature: hasher.value
            )

        case .blockQuote(let children):
            hasher.combine("bq")
            for child in children {
                hasher.combine(String(child.contentSignature))
            }
            return .complexBlockQuote(children: children, signature: hasher.value)

        case .paragraph, .heading:
            // `build()` filters these out before we get here.
            preconditionFailure("Prose blocks should be aggregated, not widget-wrapped")
        }
    }

    private static func itemSignature(_ item: ListItemContent) -> String {
        var combined = item.checkbox.map { $0 ? "[x]" : "[ ]" } ?? "[-]"
        for child in item.children {
            combined.append("|\(child.contentSignature)")
        }
        return combined
    }
}
