import Foundation

/// Decides what the post-settle height audit does for one resident row.
///
/// The audit is the timeline's self-healing backstop: the row height the
/// table applied and the height the cell actually paints are separate
/// numbers, and any defect that leaves the applied one short used to render
/// as content clipped at the cell's bottom mask FOREVER (nothing re-examines
/// a settled row). The audit re-compares them after every apply settles and
/// converts residue into a one-shot correction. Pure logic so the thresholds
/// are unit-testable.
enum ChatTimelineHeightAuditPlanner {
    enum Action: Equatable {
        /// Applied height matches the measurement — nothing to do.
        case none
        /// The height cache already holds the measured value but the table
        /// was never re-noted (the "correct-but-never-queried" states:
        /// equality-guard refusals, orphaned measurements that missed every
        /// drain). `cellDidMeasureHeight` would early-return on its own
        /// cache guard for these, so the audit must call `noteHeightOfRows`
        /// directly.
        case renoteOnly
        /// Cache and table both disagree with the measurement — route
        /// through the full report path (cache write, warm-store
        /// write-through, anchor compensation, pin).
        case reportMeasurement
    }

    static func action(
        appliedRowHeight: CGFloat,
        measuredHeight: CGFloat,
        cachedHeight: CGFloat?,
        tolerance: CGFloat = 1.0
    ) -> Action {
        guard measuredHeight > 0 else { return .none }
        guard abs(appliedRowHeight - measuredHeight) > tolerance else { return .none }
        if let cachedHeight, abs(cachedHeight - measuredHeight) <= 0.5 {
            return .renoteOnly
        }
        return .reportMeasurement
    }
}
