import Foundation

struct CompactComposerTextHeightMetrics: Equatable {
    static let minimumHeight: CGFloat = 36
    static let maximumHeight: CGFloat = 120
    static let updateThreshold: CGFloat = 0.5

    static func clampedHeight(for measuredHeight: CGFloat) -> CGFloat {
        max(minimumHeight, min(measuredHeight, maximumHeight))
    }

    static func updatedHeight(current: CGFloat, measured: CGFloat) -> CGFloat? {
        let clamped = clampedHeight(for: measured)
        guard abs(current - clamped) > updateThreshold else {
            return nil
        }
        return clamped
    }
}
