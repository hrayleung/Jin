import XCTest
@testable import Jin

/// The post-settle audit's decision table. `renoteOnly` vs
/// `reportMeasurement` matters: in the "cache correct but table never
/// re-noted" states, `cellDidMeasureHeight` early-returns on its own cache
/// guard — the audit must know to call `noteHeightOfRows` directly.
final class ChatTimelineHeightAuditPlannerTests: XCTestCase {

    func testMatchingHeightsRequireNoAction() {
        XCTAssertEqual(
            ChatTimelineHeightAuditPlanner.action(
                appliedRowHeight: 120, measuredHeight: 120, cachedHeight: 120
            ),
            .none
        )
    }

    func testDifferenceWithinToleranceRequiresNoAction() {
        XCTAssertEqual(
            ChatTimelineHeightAuditPlanner.action(
                appliedRowHeight: 120, measuredHeight: 121, cachedHeight: 121
            ),
            .none
        )
    }

    func testZeroMeasurementRequiresNoAction() {
        // Non-rendering rows (Color.clear at height 0) measure 0 — never
        // "correct" a real row down to nothing on a bad read.
        XCTAssertEqual(
            ChatTimelineHeightAuditPlanner.action(
                appliedRowHeight: 120, measuredHeight: 0, cachedHeight: nil
            ),
            .none
        )
    }

    func testStaleCacheRoutesThroughFullReport() {
        // Applied AND cache both hold the stale value: the classic
        // clipped-row state. Full report path (cache write, warm-store
        // write-through, anchor compensation).
        XCTAssertEqual(
            ChatTimelineHeightAuditPlanner.action(
                appliedRowHeight: 120, measuredHeight: 150, cachedHeight: 120
            ),
            .reportMeasurement
        )
    }

    func testMissingCacheRoutesThroughFullReport() {
        XCTAssertEqual(
            ChatTimelineHeightAuditPlanner.action(
                appliedRowHeight: 120, measuredHeight: 150, cachedHeight: nil
            ),
            .reportMeasurement
        )
    }

    func testCorrectCacheNeverNotedRenotesDirectly() {
        // The equality-guard / orphaned-measurement states: cache already
        // matches the measurement, only the table lags.
        XCTAssertEqual(
            ChatTimelineHeightAuditPlanner.action(
                appliedRowHeight: 120, measuredHeight: 150, cachedHeight: 150
            ),
            .renoteOnly
        )
    }

    func testToleranceBoundaryIsExclusive() {
        XCTAssertEqual(
            ChatTimelineHeightAuditPlanner.action(
                appliedRowHeight: 120, measuredHeight: 121.0, cachedHeight: nil, tolerance: 1.0
            ),
            .none
        )
        XCTAssertEqual(
            ChatTimelineHeightAuditPlanner.action(
                appliedRowHeight: 120, measuredHeight: 121.1, cachedHeight: nil, tolerance: 1.0
            ),
            .reportMeasurement
        )
    }

    func testCacheMatchBoundaryUsesHalfPoint() {
        XCTAssertEqual(
            ChatTimelineHeightAuditPlanner.action(
                appliedRowHeight: 120, measuredHeight: 150, cachedHeight: 150.5
            ),
            .renoteOnly
        )
        XCTAssertEqual(
            ChatTimelineHeightAuditPlanner.action(
                appliedRowHeight: 120, measuredHeight: 150, cachedHeight: 151
            ),
            .reportMeasurement
        )
    }
}
