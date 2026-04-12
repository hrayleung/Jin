import CoreGraphics

enum SidebarWidthPersistence {
    static let defaultWidth: CGFloat = 280
    static let minimumWidth: CGFloat = 240
    static let maximumWidth: CGFloat = 340

    private static let minimumMeasuredWidthForPersistence: CGFloat = 1

    static func resolvedWidth(from storedWidth: Double) -> CGFloat {
        clamped(CGFloat(storedWidth))
    }

    static func persistedWidth(from measuredWidth: CGFloat?) -> Double? {
        guard let measuredWidth, measuredWidth.isFinite, measuredWidth >= minimumMeasuredWidthForPersistence else {
            return nil
        }
        return Double(clamped(measuredWidth))
    }

    static func clamped(_ width: CGFloat) -> CGFloat {
        min(max(width, minimumWidth), maximumWidth)
    }
}
