import XCTest
@testable import Jin

final class ModelCatalogMetadataTests: XCTestCase {
    func testIsEmptyTreatsNilAndBlankFieldsAsEmpty() {
        XCTAssertTrue(ModelCatalogMetadata().isEmpty)
        XCTAssertTrue(
            ModelCatalogMetadata(
                availabilityMessage: " \n\t ",
                upgradeTargetModelID: nil,
                upgradeMessage: " "
            ).isEmpty
        )
    }

    func testIsEmptyDetectsAnyTrimmedNonBlankField() {
        XCTAssertFalse(ModelCatalogMetadata(availabilityMessage: " Limited ").isEmpty)
        XCTAssertFalse(ModelCatalogMetadata(upgradeTargetModelID: " gpt-5 ").isEmpty)
        XCTAssertFalse(ModelCatalogMetadata(upgradeMessage: " Upgrade available ").isEmpty)
    }
}
