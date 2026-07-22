import AppKit
import Foundation

extension NSAttributedString.Key {
    /// Marks an inline-code character run. `JinMarkdownLayoutManager` draws a
    /// rounded, optionally stroked background behind these ranges so inline
    /// code visually matches the CSS `code { ... border-radius; border }`
    /// rendering the WebView era had.
    static let jinInlineCodeBackground = NSAttributedString.Key("jin.inline-code.background")
    static let jinInlineCodeBorder = NSAttributedString.Key("jin.inline-code.border")

    /// Marks folded blockquote content (value: `NSNumber` nesting depth ≥ 1).
    /// `JinMarkdownLayoutManager` draws one vertical bar per depth level
    /// beside these ranges — the same mechanism as the inline-code
    /// background, chosen over NSTextBlock (rectangular borders + its own
    /// width model that fights `widthTracksTextView`) and over SwiftUI
    /// overlays (re-introduces per-paragraph bridge churn). Custom keys are
    /// dropped by the pasteboard's plain-text flavor, so copy is unaffected.
    static let jinBlockQuoteDepth = NSAttributedString.Key("jin.blockquote.depth")
    static let jinBlockQuoteBarColor = NSAttributedString.Key("jin.blockquote.bar-color")

    /// Carries the original delimited LaTeX source (`$…$` / `\(…\)`) on the
    /// single `U+FFFC` attachment glyph that an inline-math span renders to
    /// (see `InlineMath`). The rendered glyph itself has no recoverable text,
    /// so copy (`JinMessageTextView.writeSelection`) and quote
    /// (`SelectionAggregator`) read this key to substitute the LaTeX source
    /// back into the outgoing string. Like the other `jin.*` keys it is
    /// layout-inert (the layout manager never reads it) and is dropped by the
    /// pasteboard's plain/RTF flavors — it exists purely as a side-channel.
    /// Length-preserving: added over the existing length-1 attachment range,
    /// so it never perturbs the `plainText`↔attributed UTF-16 offset alignment
    /// that selection/highlight bookkeeping depends on.
    static let jinInlineMathSource = NSAttributedString.Key("jin.inline-math.source")
}

/// `NSLayoutManager` subclass that paints rounded backgrounds for runs marked
/// with `.jinInlineCodeBackground` and blockquote gutter bars. Decorative
/// fills are drawn **before** `super.drawBackground` so selection and
/// persisted-highlight `.backgroundColor` runs paint on top of the nearly
/// opaque inline-code pill (otherwise the gray fill hides the blue selection).
final class JinMarkdownLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    // ponytail: only short bilingual parentheticals are protected; use a real line-breaker if longer phrases matter.
    private static let protectedParentheticalMaxUTF16Length = 40

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldBreakLineByWordBeforeCharacterAt charIndex: Int
    ) -> Bool {
        !shouldKeepShortParentheticalWithCJKContext(beforeCharacterAt: charIndex)
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        // Decorative fills first so selection / highlight `.backgroundColor`
        // from `super` paint on top. Drawing them after covers the blue
        // selection with the nearly-opaque inline-code gray.
        if let textStorage,
           let textContainer = textContainers.first,
           let context = NSGraphicsContext.current?.cgContext {
            let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            if charRange.length > 0 {
                drawBlockQuoteBars(
                    in: charRange,
                    storage: textStorage,
                    container: textContainer,
                    origin: origin,
                    context: context
                )
                drawInlineCodeBackgrounds(
                    in: charRange,
                    storage: textStorage,
                    container: textContainer,
                    origin: origin,
                    context: context
                )
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    /// Rounded, padded pills for `.jinInlineCodeBackground` runs. Sized from
    /// the code font's metrics and anchored on the text baseline — not by
    /// insetting the full line-fragment rect (body font + `lineHeightMultiple`
    /// inflate that rect well above the smaller code glyphs).
    private func drawInlineCodeBackgrounds(
        in charRange: NSRange,
        storage: NSTextStorage,
        container: NSTextContainer,
        origin: NSPoint,
        context: CGContext
    ) {
        storage.enumerateAttribute(
            .jinInlineCodeBackground,
            in: charRange,
            options: []
        ) { value, attrRange, _ in
            guard let fillColor = value as? NSColor else { return }
            let borderColor = storage.attribute(
                .jinInlineCodeBorder,
                at: attrRange.location,
                effectiveRange: nil
            ) as? NSColor

            let codeFont = storage.attribute(.font, at: attrRange.location, effectiveRange: nil) as? NSFont
            let glyphRange = self.glyphRange(forCharacterRange: attrRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }
            // Baseline distance from the line-fragment top. Uniform within a
            // paragraph, so one sample anchors every enclosing rect.
            let baselineFromTop = self.location(forGlyphAt: glyphRange.location).y

            enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: container
            ) { rect, _ in
                // `capHeight` clears caps, digits and lowercase ascenders;
                // `descender` clears the tails. A little breathing room above,
                // almost none below — the baseline sits low in the line box.
                let ascent = codeFont?.capHeight ?? rect.height * 0.45
                let descent = abs(codeFont?.descender ?? 0)
                let padTop: CGFloat = 2.5
                let padBottom: CGFloat = 1
                let horizontalPad: CGFloat = 2.5

                let lineTop = rect.minY + origin.y
                let lineBottom = rect.maxY + origin.y
                let baselineY = lineTop + baselineFromTop
                // Hug the glyphs, but never spill into the neighbouring lines.
                let top = max(baselineY - ascent - padTop, lineTop)
                let bottom = min(baselineY + descent + padBottom, lineBottom)
                let drawRect = NSRect(
                    x: rect.minX + origin.x - horizontalPad,
                    y: top,
                    width: rect.width + 2 * horizontalPad,
                    height: bottom - top
                )
                guard drawRect.height > 0, drawRect.width > 0 else { return }

                context.saveGState()
                let radius: CGFloat = 4
                let path = NSBezierPath(roundedRect: drawRect, xRadius: radius, yRadius: radius)
                fillColor.setFill()
                path.fill()
                if let borderColor {
                    borderColor.setStroke()
                    path.lineWidth = 0.5
                    path.stroke()
                }
                context.restoreGState()
            }
        }
    }

    /// One 3pt rounded vertical bar per quote depth level, spanning each
    /// contiguous `.jinBlockQuoteDepth` run (`enumerateAttribute` coalesces
    /// adjacent equal values, so a multi-paragraph quote gets one continuous
    /// bar). Bars sit in the indent gutter the folded quote's paragraph
    /// style reserves (13pt per depth: 3pt bar + 10pt gap).
    private func drawBlockQuoteBars(
        in charRange: NSRange,
        storage: NSTextStorage,
        container: NSTextContainer,
        origin: NSPoint,
        context: CGContext
    ) {
        storage.enumerateAttribute(.jinBlockQuoteDepth, in: charRange, options: []) { value, attrRange, _ in
            guard let depth = (value as? NSNumber)?.intValue, depth > 0 else { return }
            let barColor = (storage.attribute(.jinBlockQuoteBarColor, at: attrRange.location, effectiveRange: nil) as? NSColor)
                ?? NSColor.separatorColor

            let glyphRange = self.glyphRange(forCharacterRange: attrRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }
            let bounding = self.boundingRect(forGlyphRange: glyphRange, in: container)
            guard bounding.height > 1 else { return }

            context.saveGState()
            barColor.setFill()
            for level in 0..<depth {
                let barRect = NSRect(
                    x: origin.x + CGFloat(level) * 13,
                    y: origin.y + bounding.minY + 1,
                    width: 3,
                    height: max(0, bounding.height - 2)
                )
                NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5).fill()
            }
            context.restoreGState()
        }
    }

    private func shouldKeepShortParentheticalWithCJKContext(beforeCharacterAt charIndex: Int) -> Bool {
        guard let rawString = textStorage?.string else {
            return false
        }
        let string = rawString as NSString
        guard charIndex > 0, charIndex < string.length else {
            return false
        }

        let unit = string.character(at: charIndex)
        if isOpeningParenthesis(unit),
           hasCJKBeforeSkippingWhitespace(charIndex, in: string),
           shortASCIIParentheticalEnds(startingAt: charIndex, in: string) != nil {
            return true
        }

        guard isCJK(unit),
              let closeIndex = previousNonWhitespace(before: charIndex, in: string),
              isClosingParenthesis(string.character(at: closeIndex)),
              let openIndex = shortASCIIParentheticalStarts(endingAt: closeIndex, in: string)
        else {
            return false
        }
        return hasCJKBeforeSkippingWhitespace(openIndex, in: string)
    }

    private func shortASCIIParentheticalEnds(startingAt openIndex: Int, in string: NSString) -> Int? {
        let open = string.character(at: openIndex)
        guard let close = matchingCloseParenthesis(for: open) else { return nil }
        let limit = min(string.length, openIndex + Self.protectedParentheticalMaxUTF16Length)
        var index = openIndex + 1
        while index < limit {
            let unit = string.character(at: index)
            if unit == close { return index }
            guard isPrintableASCII(unit) else { return nil }
            index += 1
        }
        return nil
    }

    private func shortASCIIParentheticalStarts(endingAt closeIndex: Int, in string: NSString) -> Int? {
        let close = string.character(at: closeIndex)
        guard let open = matchingOpenParenthesis(for: close) else { return nil }
        let limit = max(0, closeIndex - Self.protectedParentheticalMaxUTF16Length)
        var index = closeIndex - 1
        while index >= limit {
            let unit = string.character(at: index)
            if unit == open { return index }
            guard isPrintableASCII(unit) else { return nil }
            index -= 1
        }
        return nil
    }

    private func hasCJKBeforeSkippingWhitespace(_ index: Int, in string: NSString) -> Bool {
        guard let previous = previousNonWhitespace(before: index, in: string) else { return false }
        return isCJK(string.character(at: previous))
    }

    private func previousNonWhitespace(before index: Int, in string: NSString) -> Int? {
        var cursor = index - 1
        while cursor >= 0 {
            if !isInlineWhitespace(string.character(at: cursor)) {
                return cursor
            }
            cursor -= 1
        }
        return nil
    }

    private func isOpeningParenthesis(_ unit: unichar) -> Bool {
        unit == 0x0028 || unit == 0xFF08
    }

    private func isClosingParenthesis(_ unit: unichar) -> Bool {
        unit == 0x0029 || unit == 0xFF09
    }

    private func matchingCloseParenthesis(for open: unichar) -> unichar? {
        switch open {
        case 0x0028: return 0x0029
        case 0xFF08: return 0xFF09
        default: return nil
        }
    }

    private func matchingOpenParenthesis(for close: unichar) -> unichar? {
        switch close {
        case 0x0029: return 0x0028
        case 0xFF09: return 0xFF08
        default: return nil
        }
    }

    private func isPrintableASCII(_ unit: unichar) -> Bool {
        (0x20...0x7E).contains(unit)
    }

    private func isInlineWhitespace(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x00A0
    }

    private func isCJK(_ unit: unichar) -> Bool {
        switch unit {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
             0x3040...0x30FF, 0xAC00...0xD7AF:
            return true
        default:
            return false
        }
    }
}
