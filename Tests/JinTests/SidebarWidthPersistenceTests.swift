import CoreGraphics
import XCTest
@testable import Jin

final class SidebarWidthPersistenceTests: XCTestCase {
    func testResolvedWidthClampsStoredWidthIntoSupportedRange() {
        XCTAssertEqual(
            SidebarWidthPersistence.resolvedWidth(from: 120),
            SidebarWidthPersistence.minimumWidth
        )
        XCTAssertEqual(
            SidebarWidthPersistence.resolvedWidth(from: 312),
            312
        )
        XCTAssertEqual(
            SidebarWidthPersistence.resolvedWidth(from: 512),
            SidebarWidthPersistence.maximumWidth
        )
    }

    func testPersistedWidthIgnoresMissingAndBootstrapMeasurements() {
        XCTAssertNil(SidebarWidthPersistence.persistedWidth(from: nil))
        XCTAssertNil(SidebarWidthPersistence.persistedWidth(from: 0))
        XCTAssertNil(SidebarWidthPersistence.persistedWidth(from: .nan))
        XCTAssertNil(SidebarWidthPersistence.persistedWidth(from: .infinity))
    }

    func testPersistedWidthClampsMeasuredWidthsBeforeSaving() {
        XCTAssertEqual(
            SidebarWidthPersistence.persistedWidth(from: 180),
            Double(SidebarWidthPersistence.minimumWidth)
        )
        XCTAssertEqual(
            SidebarWidthPersistence.persistedWidth(from: 301.5),
            301.5
        )
        XCTAssertEqual(
            SidebarWidthPersistence.persistedWidth(from: 420),
            Double(SidebarWidthPersistence.maximumWidth)
        )
    }

    func testDebouncedPersistorCoalescesResizeNotifications() {
        var persistedWidths: [Double] = []
        var scheduledActions: [() -> Void] = []
        let persistor = SidebarWidthPersistence.DebouncedPersistor(
            delay: 0,
            schedule: { _, action in scheduledActions.append(action) },
            persist: { persistedWidths.append($0) }
        )

        persistor.schedule(width: 280)
        persistor.schedule(width: 300)
        persistor.schedule(width: 320)
        scheduledActions.forEach { $0() }

        XCTAssertEqual(persistedWidths, [320])
    }
}
