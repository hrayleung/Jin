import AppKit
import SwiftUI
import XCTest
@testable import Jin

/// `ChatTimelineHostingCell` publishes the height its hosted SwiftUI tree
/// reports, and the controller caches that number under a WIDTH-keyed key.
/// So every path that invalidates the width has to invalidate the banked
/// height with it.
@MainActor
final class ChatTimelineHostingCellHeightBaselineTests: XCTestCase {

    private func makeCell(contentHeight: CGFloat) -> ChatTimelineHostingCell {
        let cell = ChatTimelineHostingCell()
        cell.frame = NSRect(x: 0, y: 0, width: 600, height: contentHeight)
        cell.configure(
            identity: "baseline-probe",
            content: AnyView(Color.clear.frame(width: 600, height: contentHeight))
        )
        cell.layoutSubtreeIfNeeded()
        return cell
    }

    /// The reset exists for width changes: the controller wipes its
    /// width-keyed height cache and asks every resident cell to re-measure.
    /// A cell that survives the apply without a `configure()` (an append or a
    /// diff that leaves it in place) would otherwise hand the OLD width's
    /// height straight back — into the fresh cache and the warm store, under
    /// the new width's key.
    func testResettingTheBaselineDropsTheHeightMeasuredAtTheOldWidth() {
        let cell = makeCell(contentHeight: 120)

        // Stand in for the previous width's measurement.
        cell.reportSwiftUIContentHeight(940)
        XCTAssertEqual(cell.measuredContentHeight(), 940, accuracy: 0.5)

        cell.resetHeightReportingBaseline()

        XCTAssertNotEqual(
            cell.measuredContentHeight(),
            940,
            accuracy: 0.5,
            "the cell still reports the height it measured at the previous width — that number "
                + "gets published under the NEW width's cache key and pins the row to a stale height"
        )
        XCTAssertEqual(
            cell.measuredContentHeight(),
            120,
            accuracy: 1,
            "after the reset the cell must fall back to what it actually hosts"
        )
    }

    /// `configure()` already cleared it; the reset must not be weaker than the
    /// path it mirrors.
    func testConfiguringForNewContentAlsoDropsTheBankedHeight() {
        let cell = makeCell(contentHeight: 120)
        cell.reportSwiftUIContentHeight(940)

        cell.configure(
            identity: "second-row",
            content: AnyView(Color.clear.frame(width: 600, height: 200))
        )
        cell.layoutSubtreeIfNeeded()

        XCTAssertNotEqual(cell.measuredContentHeight(), 940, accuracy: 0.5)
    }
}
