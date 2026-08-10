import Foundation

/// Counters for the timeline's layout hot paths, so "scrolling got laggy" can
/// be answered with numbers instead of by reading diffs. Read and asserted by
/// `ChatTimelineScrollCostTests`; incremented from the layout paths themselves,
/// which are all main-actor.
///
/// `shadowLayouts` is the one with a standing budget: it counts `ensureLayout`
/// passes on the per-view SHADOW layout manager (the off-live-width probe
/// path). That manager shares the live `NSTextStorage`, so every storage edit
/// invalidates it — if a routine edit stream (streaming deltas) ever started
/// driving it, this counter is where it shows up first.
/// `midEditMeasurements` counts the safety valve: sizing probes that arrived
/// while a text storage's edit was still fanning out to its layout managers and
/// had to be answered on the isolated `JinTextMeasurementStack` instead. Every
/// one of those would have been the build-658 crash. It should be rare — a
/// steady stream means something is measuring from inside an edit on a hot
/// path, and each one costs a full string copy.
@MainActor
enum JinLayoutCostCounters {
    static var shadowLayouts = 0
    static var liveMeasureLayouts = 0
    static var midEditMeasurements = 0
    static var cellFrameSyncs = 0
    static var cellConfigures = 0
    static var heightAudits = 0
    static var auditRowsSampled = 0

    static func reset() {
        shadowLayouts = 0
        liveMeasureLayouts = 0
        midEditMeasurements = 0
        cellFrameSyncs = 0
        cellConfigures = 0
        heightAudits = 0
        auditRowsSampled = 0
    }
}
