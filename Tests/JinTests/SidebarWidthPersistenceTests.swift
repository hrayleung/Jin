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
}
