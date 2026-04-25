import CoreGraphics
import Foundation

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

    final class DebouncedPersistor {
        typealias Scheduler = (_ delay: TimeInterval, _ action: @escaping () -> Void) -> Void

        private let delay: TimeInterval
        private let scheduleAction: Scheduler
        private let persist: (Double) -> Void
        private var pendingWidth: Double?
        private var generation = 0

        init(
            delay: TimeInterval,
            schedule: @escaping Scheduler,
            persist: @escaping (Double) -> Void
        ) {
            self.delay = delay
            self.scheduleAction = schedule
            self.persist = persist
        }

        func schedule(width: Double) {
            pendingWidth = width
            generation += 1
            let scheduledGeneration = generation
            scheduleAction(delay) { [weak self] in
                self?.flushIfCurrent(generation: scheduledGeneration)
            }
        }

        func flush() {
            generation += 1
            guard let width = pendingWidth else { return }
            pendingWidth = nil
            persist(width)
        }

        private func flushIfCurrent(generation scheduledGeneration: Int) {
            guard scheduledGeneration == generation else { return }
            flush()
        }
    }
}
