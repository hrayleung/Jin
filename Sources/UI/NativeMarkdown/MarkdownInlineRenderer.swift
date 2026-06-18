import AppKit
import Foundation
import Markdown

/// Walks a sequence of inline `Markup` nodes and produces an `InlineRun`
/// containing the rendered `NSAttributedString`, the flat plain-text used for
/// selection offset bookkeeping, and the URL ranges for link clicks.
///
/// SoftBreak renders as " " (GFM `breaks: false` semantics — matches the
/// current `markdown-it` configuration). LineBreak renders as "\n".
/// Bare URLs in plain text are linkified via `NSDataDetector`.
struct MarkdownInlineRenderer {
    let theme: MarkdownTheme

    func render(inlineChildren: some Sequence<any Markup>) -> InlineRun {
        var acc = Accumulator(theme: theme)
        for child in inlineChildren {
            acc.render(child)
        }
        return acc.makeRun()
    }
}

private extension MarkdownInlineRenderer {
    struct Accumulator {
        let theme: MarkdownTheme
        var attrs = NSMutableAttributedString()
        var plain = ""
        var links: [LinkRange] = []
        var stack: [InlineAttributes]

        init(theme: MarkdownTheme) {
            self.theme = theme
            self.stack = [.base(theme: theme)]
        }

        mutating func render(_ markup: any Markup) {
            switch markup {
            case let text as Markdown.Text:
                appendText(text.string, frame: stack.last!)

            case let strong as Strong:
                stack.append(stack.last!.withBold(theme: theme))
                for child in strong.children { render(child) }
                stack.removeLast()

            case let emphasis as Emphasis:
                stack.append(stack.last!.withItalic(theme: theme))
                for child in emphasis.children { render(child) }
                stack.removeLast()

            case let strike as Strikethrough:
                stack.append(stack.last!.withStrikethrough(theme: theme))
                for child in strike.children { render(child) }
                stack.removeLast()

            case let code as InlineCode:
                let frame = stack.last!.withInlineCode(theme: theme)
                appendRaw(code.code, frame: frame)

            case let link as Link:
                let url = link.destination.flatMap { URL(string: $0) }
                let start = attrs.length
                stack.append(stack.last!.withLink(theme: theme, url: url))
                for child in link.children { render(child) }
                stack.removeLast()
                if let url, attrs.length > start {
                    links.append(LinkRange(range: NSRange(location: start, length: attrs.length - start), url: url))
                }

            case is SoftBreak:
                append(" ", frame: stack.last!)

            case is LineBreak:
                append("\n", frame: stack.last!)

            case let inlineHTML as InlineHTML:
                appendRaw(inlineHTML.rawHTML, frame: stack.last!.withInlineCode(theme: theme))

            case let symbol as SymbolLink:
                if let dest = symbol.destination, !dest.isEmpty {
                    appendRaw(dest, frame: stack.last!.withInlineCode(theme: theme))
                }

            case let image as Image:
                let alt = image.plainText
                if !alt.isEmpty {
                    append(alt, frame: stack.last!)
                }

            default:
                for child in markup.children { render(child) }
            }
        }

        /// Append a `Markdown.Text` run, rendering any inline math (`$…$` /
        /// `\(…\)`) natively. Prose segments still flow through `append` (which
        /// linkifies bare URLs); math segments become baseline-aligned image
        /// attachments, or their raw source on a parse failure.
        mutating func appendText(_ string: String, frame: InlineAttributes) {
            guard InlineMath.mightContainMath(string) else {
                append(string, frame: frame)
                return
            }
            for segment in InlineMath.split(string) {
                switch segment {
                case .text(let prose):
                    append(prose, frame: frame)
                case .math(let inner, let original):
                    appendInlineMath(inner: inner, original: original, frame: frame)
                }
            }
        }

        /// Appends one inline-math span. The attributed result is either a
        /// single attachment glyph (U+FFFC) or the raw source; in both cases
        /// `plain` mirrors `attrs.string` so selection offsets stay aligned.
        mutating func appendInlineMath(inner: String, original: String, frame: InlineAttributes) {
            let math = InlineMath.attributedString(
                inner: inner,
                original: original,
                font: frame.font,
                color: frame.color
            )
            attrs.append(math)
            plain.append(math.string)
        }

        /// Append text with linkify processing — bare URLs get split into
        /// link runs.
        mutating func append(_ string: String, frame: InlineAttributes) {
            guard !string.isEmpty else { return }
            if frame.linkURL != nil || frame.isInlineCode {
                appendRaw(string, frame: frame)
                return
            }
            // Cheap pre-filter: a URL needs at least a `.` plus a `:` or a
            // letter run. Skip the NSDataDetector pass for the ~80% of
            // text runs that obviously contain no URL.
            guard URLDetectionCache.mightContainURL(string) else {
                appendRaw(string, frame: frame)
                return
            }
            let ranges = URLDetectionCache.shared.detect(in: string)
            guard !ranges.isEmpty else {
                appendRaw(string, frame: frame)
                return
            }

            let nsString = string as NSString
            var cursor = 0
            for (range, url) in ranges {
                if range.location > cursor {
                    let pre = nsString.substring(with: NSRange(location: cursor, length: range.location - cursor))
                    appendRaw(pre, frame: frame)
                }
                let urlText = nsString.substring(with: range)
                let linkStart = attrs.length
                let linkFrame = frame.withLink(theme: theme, url: url)
                appendRaw(urlText, frame: linkFrame)
                links.append(LinkRange(
                    range: NSRange(location: linkStart, length: attrs.length - linkStart),
                    url: url
                ))
                cursor = range.location + range.length
            }
            if cursor < nsString.length {
                let suffix = nsString.substring(with: NSRange(location: cursor, length: nsString.length - cursor))
                appendRaw(suffix, frame: frame)
            }
        }

        mutating func appendRaw(_ string: String, frame: InlineAttributes) {
            guard !string.isEmpty else { return }
            attrs.append(NSAttributedString(string: string, attributes: frame.attributes))
            plain.append(string)
        }

        func makeRun() -> InlineRun {
            // Tighten fullwidth CJK brackets so they don't render with a half-em
            // blank floating off their open side (see `CJKPunctuationSpacing`).
            // Baked in here so every consumer of an `InlineRun` — folded prose
            // groups, list items, blockquote bodies, table cells, standalone
            // paragraphs — inherits the fix for free. Heading content is
            // re-tightened after its font override clobbers these fonts.
            CJKPunctuationSpacing.apply(to: attrs)
            return InlineRun(attributedString: attrs, plainText: plain, linkURLs: links)
        }
    }
}

/// Process-wide `NSDataDetector` cache for the URL linkify pass.
private final class URLDetectionCache {
    static let shared = URLDetectionCache()
    private let detector: NSDataDetector? = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    func detect(in string: String) -> [(NSRange, URL)] {
        guard let detector else { return [] }
        let full = NSRange(location: 0, length: (string as NSString).length)
        let matches = detector.matches(in: string, options: [], range: full)
        return matches.compactMap { match in
            guard let url = match.url else { return nil }
            return (match.range, url)
        }
    }

    /// Returns false when the string clearly contains no URL — saves the
    /// detector pass on the ~80% of prose paragraphs that don't.
    static func mightContainURL(_ string: String) -> Bool {
        guard string.contains(".") else { return false }
        if string.contains("://") || string.contains("www.") || string.contains("@") {
            return true
        }
        // Bare domains like `example.com` or `github.com/foo` carry none of
        // the markers above. Approximate a label.label pattern cheaply to
        // catch them without paying for the full detector on every prose
        // paragraph that just ends with a period.
        return string.range(
            of: #"[\p{L}\p{N}\-]+\.[\p{L}\p{N}\-]+"#,
            options: .regularExpression
        ) != nil
    }
}

/// One frame of the inline attribute stack. Each markdown emphasis level
/// pushes a new frame, the inner content uses the frame's attributes, and
/// the frame is popped on exit. Frame composition handles nested emphasis.
struct InlineAttributes {
    var font: NSFont
    var color: NSColor
    var strikethrough: Bool
    var isBold: Bool
    var isItalic: Bool
    var isInlineCode: Bool
    var linkURL: URL?
    var inlineCodeBackground: NSColor?
    var inlineCodeBorder: NSColor?

    var attributes: [NSAttributedString.Key: Any] {
        var dict: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        if strikethrough {
            dict[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            dict[.strikethroughColor] = color
        }
        if let background = inlineCodeBackground {
            // Route inline code through the custom layout manager so it gets
            // a rounded, padded, optionally-stroked background instead of the
            // default flat `.backgroundColor` block. Using a separate key
            // also keeps highlight `.backgroundColor` from colliding.
            dict[.jinInlineCodeBackground] = background
            if let border = inlineCodeBorder {
                dict[.jinInlineCodeBorder] = border
            }
        }
        if let linkURL {
            dict[.link] = linkURL
            dict[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return dict
    }

    static func base(theme: MarkdownTheme) -> InlineAttributes {
        InlineAttributes(
            font: theme.bodyFont,
            color: theme.baseColor,
            strikethrough: false,
            isBold: false,
            isItalic: false,
            isInlineCode: false,
            linkURL: nil,
            inlineCodeBackground: nil,
            inlineCodeBorder: nil
        )
    }

    func withBold(theme: MarkdownTheme) -> InlineAttributes {
        var copy = self
        copy.isBold = true
        copy.font = resolvedFont(theme: theme, isBold: true, isItalic: isItalic, isInlineCode: isInlineCode)
        return copy
    }

    func withItalic(theme: MarkdownTheme) -> InlineAttributes {
        var copy = self
        copy.isItalic = true
        copy.font = resolvedFont(theme: theme, isBold: isBold, isItalic: true, isInlineCode: isInlineCode)
        return copy
    }

    func withStrikethrough(theme: MarkdownTheme) -> InlineAttributes {
        var copy = self
        copy.strikethrough = true
        return copy
    }

    func withInlineCode(theme: MarkdownTheme) -> InlineAttributes {
        var copy = self
        copy.isInlineCode = true
        copy.font = resolvedFont(theme: theme, isBold: isBold, isItalic: isItalic, isInlineCode: true)
        copy.inlineCodeBackground = theme.inlineCodeBackground
        copy.inlineCodeBorder = theme.inlineCodeBorder
        return copy
    }

    func withLink(theme: MarkdownTheme, url: URL?) -> InlineAttributes {
        var copy = self
        copy.linkURL = url
        copy.color = theme.linkColor
        return copy
    }

    private func resolvedFont(theme: MarkdownTheme, isBold: Bool, isItalic: Bool, isInlineCode: Bool) -> NSFont {
        if isInlineCode { return theme.codeFont }
        switch (isBold, isItalic) {
        case (true, true): return theme.boldItalicFont()
        case (true, false): return theme.boldFont()
        case (false, true): return theme.italicFont()
        case (false, false): return theme.bodyFont
        }
    }
}
