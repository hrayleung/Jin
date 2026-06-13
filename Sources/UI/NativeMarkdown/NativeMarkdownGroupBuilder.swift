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
            // Fold prose-only lists (paragraphs + recursively prose-only
            // nested lists; loose and multi-paragraph items included) into
            // the prose text view instead of one NSTextView per item/
            // paragraph. Lists are the #1 resident-NSTextView multiplier in
            // LLM output, so this is the central scroll-cost reduction.
            // Lists carrying widget children (code blocks, tables, …) still
            // take the per-item ListView path.
            return isFoldableList(items)
        case .blockQuote(let children):
            // Same for quotes: paragraph/heading/foldable-list/nested-quote
            // content folds into the prose run; the vertical bar is drawn by
            // `JinMarkdownLayoutManager` from the `.jinBlockQuoteDepth`
            // attribute, so no extra views are needed.
            return isFoldableBlockQuote(children)
        default:
            return false
        }
    }

    /// A list we can render as attributed text inside the prose group: every
    /// item consists only of paragraphs and nested lists that are themselves
    /// foldable. Looseness and multi-paragraph items are spacing/indent
    /// concerns, not structural ones.
    private static func isFoldableList(_ items: [ListItemContent]) -> Bool {
        guard !items.isEmpty else { return false }
        for item in items {
            guard !item.children.isEmpty else { return false }
            for child in item.children {
                switch child {
                case .paragraph:
                    continue
                case .bulletList(let nested, _), .orderedList(_, let nested, _):
                    guard isFoldableList(nested) else { return false }
                default:
                    return false
                }
            }
        }
        return true
    }

    private static func isFoldableBlockQuote(_ children: [NativeMarkdownBlock]) -> Bool {
        guard !children.isEmpty else { return false }
        for child in children {
            switch child {
            case .paragraph, .heading:
                continue
            case .bulletList(let items, _), .orderedList(_, let items, _):
                guard isFoldableList(items) else { return false }
            case .blockQuote(let nested):
                guard isFoldableBlockQuote(nested) else { return false }
            default:
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
                appendFoldedList(
                    kind: .bullet, start: 1, items: items, tight: tight, theme: theme,
                    quoteDepth: 0,
                    into: result, plainText: &plainText, links: &translatedLinks, hasher: &hasher
                )

            case .orderedList(let start, let items, let tight):
                appendFoldedList(
                    kind: .ordered, start: start, items: items, tight: tight, theme: theme,
                    quoteDepth: 0,
                    into: result, plainText: &plainText, links: &translatedLinks, hasher: &hasher
                )

            case .blockQuote(let children):
                appendFoldedBlockQuote(
                    children: children, depth: 1, theme: theme,
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

    /// Renders a (possibly nested, possibly loose) prose-only list into the
    /// prose attributed string: one hanging-indent paragraph per item
    /// paragraph (`marker \t text`), nested lists indented one unit deeper,
    /// continuation paragraphs of a loose item indented to the text column
    /// with no marker. Markers go into BOTH the attributed string AND
    /// plainText so NSTextView char positions stay equal to plainText
    /// offsets (selection/highlight mapping stays correct) — the contract
    /// the original simple-list fold established.
    private static func appendFoldedList(
        kind: NativeMarkdownGroup.ComplexListKind,
        start: Int,
        items: [ListItemContent],
        tight: Bool,
        theme: MarkdownTheme,
        quoteDepth: Int,
        into result: NSMutableAttributedString,
        plainText: inout String,
        links: inout [LinkRange],
        hasher: inout FNVHasher
    ) {
        var previousUnitStyle: NSParagraphStyle?

        func separateUnit(next style: NSParagraphStyle) {
            if let previous = previousUnitStyle {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: theme.bodyFont,
                    .foregroundColor: theme.baseColor,
                    .paragraphStyle: previous,
                ]))
                plainText.append("\n")
            }
            previousUnitStyle = style
        }

        func appendRun(_ run: InlineRun, style: NSParagraphStyle) {
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
        }

        func walk(
            kind: NativeMarkdownGroup.ComplexListKind,
            start: Int,
            items: [ListItemContent],
            tight: Bool,
            level: Int
        ) {
            let geometry = listIndentGeometry(
                kind: kind, start: start, count: items.count,
                level: level, quoteDepth: quoteDepth, theme: theme
            )
            let itemStyle = MarkdownTheme.listParagraphStyle(
                firstLineHeadIndent: geometry.markerIndent,
                headIndent: geometry.textIndent,
                paragraphSpacing: tight ? 2 : 6
            )
            let continuationStyle = MarkdownTheme.listParagraphStyle(
                firstLineHeadIndent: geometry.textIndent,
                headIndent: geometry.textIndent,
                paragraphSpacing: 6
            )

            for (offset, item) in items.enumerated() {
                var isItemLead = true
                for child in item.children {
                    switch child {
                    case .paragraph(let run):
                        let style = isItemLead ? itemStyle : continuationStyle
                        separateUnit(next: style)
                        if isItemLead {
                            let marker = listMarker(kind: kind, start: start, offset: offset, checkbox: item.checkbox, level: level)
                            hasher.combine("li-\(kind == .ordered ? "o" : "u")-\(tight)-L\(level)")
                            hasher.combine(marker)
                            result.append(NSAttributedString(string: marker, attributes: [
                                .font: theme.bodyFont,
                                .foregroundColor: theme.secondaryColor,
                                .paragraphStyle: style,
                            ]))
                            plainText.append(marker)
                        }
                        hasher.combine(run.plainText)
                        appendRun(run, style: style)
                        isItemLead = false

                    case .bulletList(let nested, let nestedTight):
                        walk(kind: .bullet, start: 1, items: nested, tight: nestedTight, level: level + 1)
                        isItemLead = false

                    case .orderedList(let nestedStart, let nested, let nestedTight):
                        walk(kind: .ordered, start: nestedStart, items: nested, tight: nestedTight, level: level + 1)
                        isItemLead = false

                    default:
                        // Unreachable: `isFoldableList` admits only the
                        // cases above.
                        continue
                    }
                }
            }
        }

        walk(kind: kind, start: start, items: items, tight: tight, level: 0)
    }

    private struct ListIndentGeometry {
        let markerIndent: CGFloat
        let textIndent: CGFloat
    }

    /// Per-level hanging-indent geometry. The marker column widens for
    /// ordered lists whose widest ordinal (`97.`) exceeds the default 22pt
    /// unit, so the tab stop never overshoots into the next tab interval.
    private static func listIndentGeometry(
        kind: NativeMarkdownGroup.ComplexListKind,
        start: Int,
        count: Int,
        level: Int,
        quoteDepth: Int,
        theme: MarkdownTheme
    ) -> ListIndentGeometry {
        let base = CGFloat(quoteDepth) * 13 + CGFloat(level) * 22
        var unit: CGFloat = 22
        if kind == .ordered {
            // Approximate digit width deterministically (no off-main TextKit
            // measurement): digits ≈ 0.62 em in UI fonts, plus the period.
            let widestOrdinal = start + max(0, count - 1)
            let digits = CGFloat(String(widestOrdinal).count)
            unit = max(22, ceil(digits * theme.bodyFont.pointSize * 0.62 + 6) + 8)
        }
        return ListIndentGeometry(markerIndent: base + 2, textIndent: base + unit)
    }

    private static func listMarker(
        kind: NativeMarkdownGroup.ComplexListKind,
        start: Int,
        offset: Int,
        checkbox: Bool?,
        level: Int
    ) -> String {
        if let checked = checkbox {
            return checked ? "☑\t" : "☐\t"
        }
        if kind == .ordered {
            return "\(start + offset).\t"
        }
        switch level {
        case 0: return "•\t"
        case 1: return "◦\t"
        default: return "▪\t"
        }
    }

    // MARK: - Folded blockquotes

    /// Folds a prose-only blockquote into the prose run: paragraphs/headings
    /// indented 13pt per depth (3pt bar + 10pt gap, matching the legacy
    /// `BlockQuoteView` geometry), body text re-tinted to the quote color,
    /// and the whole range tagged with `.jinBlockQuoteDepth` so
    /// `JinMarkdownLayoutManager` draws the vertical bar(s) — no extra views.
    private static func appendFoldedBlockQuote(
        children: [NativeMarkdownBlock],
        depth: Int,
        theme: MarkdownTheme,
        into result: NSMutableAttributedString,
        plainText: inout String,
        links: inout [LinkRange],
        hasher: inout FNVHasher
    ) {
        let quoteStart = result.length
        let indent = CGFloat(depth) * 13
        let bodyStyle = MarkdownTheme.listParagraphStyle(
            firstLineHeadIndent: indent,
            headIndent: indent,
            paragraphSpacing: 6
        )
        hasher.combine("bq-fold-\(depth)")

        var isFirstChild = true
        func separator(style: NSParagraphStyle) {
            if !isFirstChild {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: theme.bodyFont,
                    .foregroundColor: theme.blockQuoteText,
                    .paragraphStyle: style,
                ]))
                plainText.append("\n")
            }
            isFirstChild = false
        }

        for child in children {
            switch child {
            case .paragraph(let run):
                separator(style: bodyStyle)
                hasher.combine(run.plainText)
                let runStart = result.length
                appendInlineRun(run, paragraphStyle: bodyStyle, fontOverride: nil, into: result, plainText: &plainText, links: &links)
                retintQuoteBody(in: result, range: NSRange(location: runStart, length: result.length - runStart), theme: theme)

            case .heading(let level, let content):
                separator(style: bodyStyle)
                hasher.combine("h\(level)")
                hasher.combine(content.plainText)
                appendInlineRun(
                    content,
                    paragraphStyle: MarkdownTheme.indentedHeadingParagraphStyle(level: level, indent: indent),
                    fontOverride: theme.headingFont(forLevel: level),
                    into: result, plainText: &plainText, links: &links
                )

            case .bulletList(let items, let tight):
                separator(style: bodyStyle)
                appendFoldedList(
                    kind: .bullet, start: 1, items: items, tight: tight, theme: theme,
                    quoteDepth: depth,
                    into: result, plainText: &plainText, links: &links, hasher: &hasher
                )

            case .orderedList(let start, let items, let tight):
                separator(style: bodyStyle)
                appendFoldedList(
                    kind: .ordered, start: start, items: items, tight: tight, theme: theme,
                    quoteDepth: depth,
                    into: result, plainText: &plainText, links: &links, hasher: &hasher
                )

            case .blockQuote(let nested):
                separator(style: bodyStyle)
                appendFoldedBlockQuote(
                    children: nested, depth: depth + 1, theme: theme,
                    into: result, plainText: &plainText, links: &links, hasher: &hasher
                )

            default:
                // Unreachable: `isFoldableBlockQuote` admits only the cases
                // above.
                continue
            }
        }

        // Tag the quote's full range (including internal separators) so the
        // layout manager draws ONE continuous bar per depth. Nested quotes
        // re-tag their sub-range with a deeper value, which wins because it
        // is applied later over a narrower range — except here the OUTER
        // call runs after the nested one returned, so apply only where no
        // deeper tag exists yet.
        let quoteRange = NSRange(location: quoteStart, length: result.length - quoteStart)
        result.enumerateAttribute(.jinBlockQuoteDepth, in: quoteRange, options: []) { value, range, _ in
            guard value == nil else { return }
            result.addAttribute(.jinBlockQuoteDepth, value: NSNumber(value: depth), range: range)
            result.addAttribute(.jinBlockQuoteBarColor, value: theme.blockQuoteBorder, range: range)
        }
    }

    /// Quoted body text reads dimmer than regular prose. Only runs still in
    /// the base color are re-tinted — links, inline code, and other special
    /// colors keep their meaning.
    private static func retintQuoteBody(
        in result: NSMutableAttributedString,
        range: NSRange,
        theme: MarkdownTheme
    ) {
        result.enumerateAttribute(.foregroundColor, in: range, options: []) { value, runRange, _ in
            guard let color = value as? NSColor, color == theme.baseColor else { return }
            result.addAttribute(.foregroundColor, value: theme.blockQuoteText, range: runRange)
        }
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
        // The signature is the single source of truth on `NativeMarkdownBlock` so the
        // group's `ForEach` id stays in lockstep with `contentSignature` (used as the
        // block id elsewhere) and cannot drift from a second hashing implementation.
        let signature = block.contentSignature
        switch block {
        case .codeBlock(let language, let source, let isStreamingTail):
            return .codeBlock(
                language: language,
                source: source,
                isStreamingTail: isStreamingTail,
                signature: signature
            )

        case .table(let header, let alignments, let rows):
            return .table(
                header: header,
                alignments: alignments,
                rows: rows,
                signature: signature
            )

        case .mathBlock(let latex):
            return .math(latex: latex, signature: signature)

        case .mermaidBlock(let source):
            return .mermaid(source: source, signature: signature)

        case .htmlBlock(let text):
            return .htmlBlock(text: text, signature: signature)

        case .thematicBreak:
            return .thematicBreak(signature: signature)

        case .bulletList(let items, let tight):
            return .complexList(
                kind: .bullet,
                start: 1,
                items: items,
                tight: tight,
                signature: signature
            )

        case .orderedList(let start, let items, let tight):
            return .complexList(
                kind: .ordered,
                start: start,
                items: items,
                tight: tight,
                signature: signature
            )

        case .blockQuote(let children):
            return .complexBlockQuote(children: children, signature: signature)

        case .paragraph, .heading:
            // `build()` filters these out before we get here.
            preconditionFailure("Prose blocks should be aggregated, not widget-wrapped")
        }
    }
}
