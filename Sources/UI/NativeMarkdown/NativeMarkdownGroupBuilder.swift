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
        case .bulletList(let items, _), .orderedList(_, let items, _):
            // Fold SIMPLE lists (each item is a single paragraph, no nesting)
            // into the prose text view instead of one NSTextView per item.
            // Lists are the #1 resident-NSTextView multiplier in LLM output, so
            // this is the central scroll-cost reduction. Complex/nested lists
            // still take the per-item ListView path.
            return isSimpleProseList(items)
        default:
            return false
        }
    }

    /// A list we can render as attributed text inside the prose group: every
    /// item is exactly one paragraph with no nested blocks.
    private static func isSimpleProseList(_ items: [ListItemContent]) -> Bool {
        guard !items.isEmpty else { return false }
        for item in items {
            guard item.children.count == 1, case .paragraph = item.children[0] else {
                return false
            }
        }
        return true
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

            case .bulletList(let items, let tight):
                appendSimpleList(
                    kind: .bullet, start: 1, items: items, tight: tight, theme: theme,
                    into: result, plainText: &plainText, links: &translatedLinks, hasher: &hasher
                )

            case .orderedList(let start, let items, let tight):
                appendSimpleList(
                    kind: .ordered, start: start, items: items, tight: tight, theme: theme,
                    into: result, plainText: &plainText, links: &translatedLinks, hasher: &hasher
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

        let attributedString = result.copy() as! NSAttributedString
        combineRenderAttributes(of: attributedString, links: translatedLinks, into: &hasher)

        return .prose(
            attributedString: attributedString,
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

    /// Renders a simple list's items into the prose attributed string as one
    /// hanging-indent paragraph per item (`marker \t text`). Markers go into BOTH
    /// the attributed string AND plainText so NSTextView char positions stay
    /// equal to plainText offsets (selection/highlight mapping stays correct).
    private static func appendSimpleList(
        kind: NativeMarkdownGroup.ComplexListKind,
        start: Int,
        items: [ListItemContent],
        tight: Bool,
        theme: MarkdownTheme,
        into result: NSMutableAttributedString,
        plainText: inout String,
        links: inout [LinkRange],
        hasher: inout FNVHasher
    ) {
        let style = simpleListParagraphStyle(tight: tight)
        for (offset, item) in items.enumerated() {
            guard case .paragraph(let run)? = item.children.first else { continue }

            let marker: String
            if let checked = item.checkbox {
                marker = checked ? "☑\t" : "☐\t"
            } else if kind == .ordered {
                marker = "\(start + offset).\t"
            } else {
                marker = "•\t"
            }

            hasher.combine("li-\(kind == .ordered ? "o" : "u")-\(tight)")
            hasher.combine(marker)
            hasher.combine(run.plainText)

            result.append(NSAttributedString(string: marker, attributes: [
                .font: theme.bodyFont,
                .foregroundColor: theme.secondaryColor,
                .paragraphStyle: style,
            ]))
            plainText.append(marker)

            let runStart = result.length
            let attr = NSMutableAttributedString(attributedString: run.attributedString)
            attr.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: attr.length))
            result.append(attr)
            plainText.append(run.plainText)
            for linkRange in run.linkURLs {
                links.append(LinkRange(
                    range: NSRange(location: linkRange.range.location + runStart, length: linkRange.range.length),
                    url: linkRange.url
                ))
            }

            if offset != items.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: theme.bodyFont,
                    .foregroundColor: theme.baseColor,
                    .paragraphStyle: style,
                ]))
                plainText.append("\n")
            }
        }
    }

    private static func simpleListParagraphStyle(tight: Bool) -> NSParagraphStyle {
        let style = (MarkdownTheme.cachedBodyParagraphStyle.mutableCopy() as? NSMutableParagraphStyle)
            ?? NSMutableParagraphStyle()
        // Marker sits at ~2pt; a left tab stop + headIndent at 22pt put the item
        // text (and any wrapped lines) in a hanging-indent column after the marker.
        style.firstLineHeadIndent = 2
        style.headIndent = 22
        style.tabStops = [NSTextTab(textAlignment: .left, location: 22)]
        style.defaultTabInterval = 22
        style.paragraphSpacing = tight ? 2 : 6
        return style
    }

    private static func combineRenderAttributes(
        of attributedString: NSAttributedString,
        links: [LinkRange],
        into hasher: inout FNVHasher
    ) {
        let fullRange = NSRange(location: 0, length: attributedString.length)
        guard fullRange.length > 0 else { return }

        attributedString.enumerateAttributes(in: fullRange) { attributes, range, _ in
            hasher.combine("range:\(range.location):\(range.length)")
            for key in attributes.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                hasher.combine(key.rawValue)
                combineAttributeValue(attributes[key] ?? "", into: &hasher)
            }
        }

        for link in links {
            hasher.combine("link:\(link.range.location):\(link.range.length):\(link.url.absoluteString)")
        }
    }

    private static func combineAttributeValue(_ value: Any, into hasher: inout FNVHasher) {
        switch value {
        case let font as NSFont:
            hasher.combine("font:\(font.fontName):\(font.pointSize):\(font.fontDescriptor.symbolicTraits.rawValue)")

        case let color as NSColor:
            let rgb = color.usingColorSpace(.deviceRGB)
            hasher.combine(
                "color:\(rgb?.redComponent ?? 0):\(rgb?.greenComponent ?? 0):\(rgb?.blueComponent ?? 0):\(rgb?.alphaComponent ?? color.alphaComponent)"
            )

        case let style as NSParagraphStyle:
            hasher.combine("""
            paragraph:\(style.alignment.rawValue):\(style.lineBreakMode.rawValue):\(style.lineSpacing):\(style.paragraphSpacing):\(style.paragraphSpacingBefore):\(style.headIndent):\(style.firstLineHeadIndent):\(style.tailIndent):\(style.minimumLineHeight):\(style.maximumLineHeight):\(style.lineHeightMultiple)
            """)

        case let url as URL:
            hasher.combine("url:\(url.absoluteString)")

        case let string as String:
            hasher.combine("string:\(string)")

        case let number as NSNumber:
            hasher.combine("number:\(number.stringValue)")

        default:
            hasher.combine(String(describing: value))
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
