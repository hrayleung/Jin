//
//  File.swift
//
//
//  Created by Peter Tang on 12/9/2023.
//

import Foundation

#if os(iOS) || os(visionOS)
    import UIKit
#endif

#if os(macOS)
    import AppKit
#endif

public class MTMathImage {
    public var font: MTFont? = MTFontManager.fontManager.defaultFont
    public var fontSize:CGFloat {
        set {
            _fontSize = newValue
            let font = font?.copy(withSize: newValue)
            self.font = font  // also forces an update
        }
        get { _fontSize }
    }
    private var _fontSize:CGFloat = 0
    public let textColor: MTColor

    public let labelMode: MTMathUILabelMode
    public let textAlignment: MTTextAlignment

    public var contentInsets: MTEdgeInsets = MTEdgeInsetsZero

    public let latex: String
    private(set) var intrinsicContentSize = CGSize.zero

    // Jin fork addition: expose the rendered baseline metrics so callers can
    // align the produced image on a text baseline (e.g. as an NSTextAttachment
    // for inline math). Populated by `asImage()`.
    public private(set) var ascent: CGFloat = 0
    public private(set) var descent: CGFloat = 0

    public init(latex: String, fontSize: CGFloat, textColor: MTColor, labelMode: MTMathUILabelMode = .display, textAlignment: MTTextAlignment = .center) {
        self.latex = latex
        self.textColor = textColor
        self.labelMode = labelMode
        self.textAlignment = textAlignment
        self.fontSize = fontSize
    }
}
extension MTMathImage {
    public var currentStyle: MTLineStyle {
        switch labelMode {
            case .display: return .display
            case .text: return .text
        }
    }
    private func intrinsicContentSize(_ displayList: MTMathListDisplay) -> CGSize {
        CGSize(width: displayList.width + contentInsets.left + contentInsets.right,
               height: displayList.ascent + displayList.descent + contentInsets.top + contentInsets.bottom)
    }
    public func asImage() -> (NSError?, MTImage?) {
        func layoutImage(size: CGSize, displayList: MTMathListDisplay) {
            var textX = CGFloat(0)
            switch self.textAlignment {
                case .left:   textX = contentInsets.left
                case .center: textX = (size.width - contentInsets.left - contentInsets.right - displayList.width) / 2 + contentInsets.left
                case .right:  textX = size.width - displayList.width - contentInsets.right
            }
            let availableHeight = size.height - contentInsets.bottom - contentInsets.top

            // center things vertically
            var height = displayList.ascent + displayList.descent
            if height < fontSize/2 {
                height = fontSize/2  // set height to half the font size
            }
            let textY = (availableHeight - height) / 2 + displayList.descent + contentInsets.bottom
            displayList.position = CGPoint(x: textX, y: textY)
        }

        var error: NSError?
        guard let mathList = MTMathListBuilder.build(fromString: latex, error: &error), error == nil,
              let displayList = MTTypesetter.createLineForMathList(mathList, font: font, style: currentStyle) else {
            return (error, nil)
        }

        intrinsicContentSize = intrinsicContentSize(displayList)
        ascent = displayList.ascent
        descent = displayList.descent

        let size = intrinsicContentSize
        layoutImage(size: size, displayList: displayList)

        #if os(iOS) || os(visionOS)
            displayList.textColor = textColor
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { rendererContext in
                rendererContext.cgContext.saveGState()
                rendererContext.cgContext.concatenate(.flippedVertically(size.height))
                displayList.draw(rendererContext.cgContext)
                rendererContext.cgContext.restoreGState()
            }
            return (nil, image)
        #endif
        #if os(macOS)
            // Resolve dynamic NSColors at draw time under NSAppearance.currentDrawing()
            // so cached inline-math attachments automatically adapt when macOS or Jin
            // switches between Light and Dark mode without re-parsing the markdown.
            let dynamicTextColor = textColor
            let drawLock = NSLock()
            var lastDrawnCGColor: CGColor?
            let image = NSImage(size: size, flipped: false) { _ in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                let resolved = dynamicTextColor.usingColorSpace(.sRGB) ?? dynamicTextColor
                let cgColor = resolved.cgColor
                drawLock.lock()
                defer { drawLock.unlock() }
                if lastDrawnCGColor != cgColor {
                    displayList.textColor = resolved
                    lastDrawnCGColor = cgColor
                }
                context.saveGState()
                displayList.draw(context)
                context.restoreGState()
                return true
            }
            image.cacheMode = .never
            return (nil, image)
        #endif
    }
}
private extension CGAffineTransform {
    static func flippedVertically(_ height: CGFloat) -> CGAffineTransform {
        var transform = CGAffineTransform(scaleX: 1, y: -1)
        transform = transform.translatedBy(x: 0, y: -height)
        return transform
    }
}
