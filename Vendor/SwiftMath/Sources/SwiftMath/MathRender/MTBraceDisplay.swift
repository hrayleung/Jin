import CoreGraphics
import Foundation

/// Draws a horizontal brace with fixed-size tips and cusp. Only the straight
/// sections grow with the expression, so long braces retain their shape.
final class MTBraceDisplay: MTDisplay {
    let inner: MTMathListDisplay
    let isOver: Bool
    let braceHeight: CGFloat
    let gap: CGFloat
    let thickness: CGFloat

    init(inner: MTMathListDisplay, isOver: Bool, fontSize: CGFloat, thickness: CGFloat, range: NSRange) {
        self.inner = inner
        self.isOver = isOver
        self.braceHeight = fontSize * 0.3
        self.gap = fontSize * 0.1
        self.thickness = thickness
        super.init()
        self.range = range
        width = max(inner.width, fontSize * 0.6)
        let extent = gap + braceHeight + thickness
        ascent = inner.ascent + (isOver ? extent : 0)
        descent = inner.descent + (isOver ? 0 : extent)
        position = .zero
    }

    override var position: CGPoint {
        get { super.position }
        set {
            super.position = newValue
            inner.position = CGPoint(x: newValue.x + (width - inner.width) / 2, y: newValue.y)
        }
    }

    override var textColor: MTColor? {
        get { super.textColor }
        set {
            super.textColor = newValue
            inner.textColor = newValue
        }
    }

    override func draw(_ context: CGContext) {
        super.draw(context)
        inner.draw(context)
        context.saveGState()
        defer { context.restoreGState() }
        let edge = isOver ? inner.ascent + gap : -inner.descent - gap
        context.translateBy(x: position.x, y: position.y + edge)
        context.scaleBy(x: 1, y: isOver ? 1 : -1)
        if let textColor { context.setStrokeColor(textColor.cgColor) }
        context.setLineWidth(thickness)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Leave half a stroke inside each boundary, including the outer cusp.
        let start = thickness / 2
        let end = width - start
        let middle = width / 2
        let h = braceHeight / 2
        let curl = min(braceHeight, (end - start) / 4)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: start, y: start))
        path.addCurve(to: CGPoint(x: start + curl, y: start + h),
                      control1: CGPoint(x: start, y: start + h),
                      control2: CGPoint(x: start + curl / 2, y: start + h))
        path.addLine(to: CGPoint(x: middle - curl, y: start + h))
        path.addCurve(to: CGPoint(x: middle, y: start + 2 * h),
                      control1: CGPoint(x: middle - curl / 2, y: start + h),
                      control2: CGPoint(x: middle, y: start + h))
        path.addCurve(to: CGPoint(x: middle + curl, y: start + h),
                      control1: CGPoint(x: middle, y: start + h),
                      control2: CGPoint(x: middle + curl / 2, y: start + h))
        path.addLine(to: CGPoint(x: end - curl, y: start + h))
        path.addCurve(to: CGPoint(x: end, y: start),
                      control1: CGPoint(x: end - curl / 2, y: start + h),
                      control2: CGPoint(x: end, y: start + h))
        context.addPath(path)
        context.strokePath()
    }
}
