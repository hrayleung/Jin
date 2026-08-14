import CoreGraphics
import Foundation

enum UserMessageImageStackSupport {
    static let thumbnailSize: CGFloat = 80
    static let thumbnailSpacing: CGFloat = JinSpacing.small
    static let maxInlineCount = 3
    static let collapsedPreviewCount = 3
    static let stackPeekX: CGFloat = 11
    static let stackPeekY: CGFloat = 5
    static let stackRotationDegrees: Double = 6

    static func shouldStack(imageCount: Int) -> Bool {
        imageCount > maxInlineCount
    }

    static func previewCount(imageCount: Int) -> Int {
        min(max(0, imageCount), collapsedPreviewCount)
    }

    /// Origin of the first card inside `collapsedStackSize`, so rotation that
    /// swings left/up still sits inside the reserved frame.
    static func collapsedFanOrigin(imageCount: Int) -> CGPoint {
        let bounds = collapsedStackBounds(imageCount: imageCount)
        return CGPoint(x: -bounds.minX, y: -bounds.minY)
    }

    static func collapsedStackSize(imageCount: Int) -> CGSize {
        collapsedStackBounds(imageCount: imageCount).size
    }

    /// Axis-aligned bounds of the fanned cards in the first card's top-leading space.
    static func collapsedStackBounds(imageCount: Int) -> CGRect {
        let visible = previewCount(imageCount: imageCount)
        guard visible > 0 else { return .zero }

        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for index in 0..<visible {
            let radians = CGFloat(index) * stackRotationDegrees * .pi / 180
            let originX = CGFloat(index) * stackPeekX
            let originY = CGFloat(index) * stackPeekY
            for corner in rotatedCardCorners(radians: radians) {
                let x = corner.x + originX
                let y = corner.y + originY
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Clockwise rotation in a y-down view, pivot at the card's bottom leading corner.
    static func rotatedCardCorners(radians: CGFloat) -> [CGPoint] {
        let width = thumbnailSize
        let height = thumbnailSize
        let cosine = Foundation.cos(radians)
        let sine = Foundation.sin(radians)
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: width, y: 0),
            CGPoint(x: 0, y: height),
            CGPoint(x: width, y: height)
        ]
        return points.map { point in
            let dx = point.x
            let dy = point.y - height
            return CGPoint(
                x: dx * cosine + dy * sine,
                y: height - dx * sine + dy * cosine
            )
        }
    }

    static func titleText(imageCount: Int) -> String {
        imageCount == 1 ? "1 image" : "\(imageCount) images"
    }

    static func actionText(isExpanded: Bool) -> String {
        isExpanded ? "Hide" : "Show all"
    }
}
