import AppKit
import Foundation

extension NSAttributedString.Key {
    /// Marks an inline-code character run. `JinMarkdownLayoutManager` draws a
    /// rounded, optionally stroked background behind these ranges so inline
    /// code visually matches the CSS `code { ... border-radius; border }`
    /// rendering the WebView era had.
    static let jinInlineCodeBackground = NSAttributedString.Key("jin.inline-code.background")
    static let jinInlineCodeBorder = NSAttributedString.Key("jin.inline-code.border")
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

        textStorage.enumerateAttribute(
            .jinInlineCodeBackground,
            in: charRange,
            options: []
        ) { value, attrRange, _ in
            guard let fillColor = value as? NSColor else { return }
            let borderColor = textStorage.attribute(.jinInlineCodeBorder, at: attrRange.location, effectiveRange: nil) as? NSColor

            let glyphRange = self.glyphRange(forCharacterRange: attrRange, actualCharacterRange: nil)
            enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { rect, _ in
                let inset: CGFloat = 1.5
                let horizontalPad: CGFloat = 1
                let drawRect = NSRect(
                    x: rect.origin.x + origin.x - horizontalPad,
                    y: rect.origin.y + origin.y + inset,
                    width: rect.size.width + 2 * horizontalPad,
                    height: max(0, rect.size.height - 2 * inset)
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
}
