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
}

/// `NSLayoutManager` subclass that paints rounded backgrounds for runs marked
/// with `.jinInlineCodeBackground`. Falls through to `super` for highlight
/// `.backgroundColor` runs and selection painting.
final class JinMarkdownLayoutManager: NSLayoutManager {

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage,
              let textContainer = textContainers.first,
              let context = NSGraphicsContext.current?.cgContext
        else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard charRange.length > 0 else { return }

        drawBlockQuoteBars(in: charRange, storage: textStorage, container: textContainer, origin: origin, context: context)

        textStorage.enumerateAttribute(
            .jinInlineCodeBackground,
            in: charRange,
            options: []
        ) { value, attrRange, _ in
            guard let fillColor = value as? NSColor else { return }
            let borderColor = textStorage.attribute(.jinInlineCodeBorder, at: attrRange.location, effectiveRange: nil) as? NSColor

            // Size the pill from the *code* font's metrics, anchored on the
            // text baseline — not by insetting the enclosing rect. That rect
            // is the full line-fragment height, which the larger body font
            // and `lineHeightMultiple` inflate well above the (smaller) code
            // glyphs; insetting it symmetrically left the fill floating high
            // with a big gap on top and the descenders clipped at the bottom.
            let codeFont = textStorage.attribute(.font, at: attrRange.location, effectiveRange: nil) as? NSFont
            let glyphRange = self.glyphRange(forCharacterRange: attrRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }
            // Baseline distance from the line-fragment top. Uniform within a
            // paragraph, so one sample anchors every enclosing rect.
            let baselineFromTop = self.location(forGlyphAt: glyphRange.location).y

            enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
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
}
