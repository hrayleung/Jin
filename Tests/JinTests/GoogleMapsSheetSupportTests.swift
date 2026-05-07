import Foundation
import XCTest
#if canImport(CoreLocation)
import CoreLocation
#endif
@testable import Jin

final class GoogleMapsSheetSupportTests: XCTestCase {
    func testCoordinateDraftsTrimAndExposePresenceStates() {
        let complete = GoogleMapsSheetSupport.coordinateDrafts(
            latitudeDraft: " 34.050481 ",
            longitudeDraft: "\n-118.248526"
        )

        XCTAssertEqual(complete.latitude, "34.050481")
        XCTAssertEqual(complete.longitude, "-118.248526")
        XCTAssertTrue(complete.hasAnyValue)
        XCTAssertTrue(complete.hasLiveLocation)

        let partial = GoogleMapsSheetSupport.coordinateDrafts(
            latitudeDraft: " ",
            longitudeDraft: "-118.248526"
        )

        XCTAssertNil(partial.latitude)
        XCTAssertEqual(partial.longitude, "-118.248526")
        XCTAssertTrue(partial.hasAnyValue)
        XCTAssertFalse(partial.hasLiveLocation)

        let empty = GoogleMapsSheetSupport.coordinateDrafts(
            latitudeDraft: "\n",
            longitudeDraft: " "
        )

        XCTAssertNil(empty.latitude)
        XCTAssertNil(empty.longitude)
        XCTAssertFalse(empty.hasAnyValue)
        XCTAssertFalse(empty.hasLiveLocation)
    }

    func testHasCoordinateDraftsAllowsPartialDraftsForClearing() {
        XCTAssertTrue(
            GoogleMapsSheetSupport.hasCoordinateDrafts(
                latitudeDraft: "34.050481",
                longitudeDraft: " "
            )
        )
        XCTAssertTrue(
            GoogleMapsSheetSupport.hasCoordinateDrafts(
                latitudeDraft: "",
                longitudeDraft: "-118.248526"
            )
        )
        XCTAssertFalse(
            GoogleMapsSheetSupport.hasCoordinateDrafts(
                latitudeDraft: " ",
                longitudeDraft: "\n"
            )
        )
    }

    func testHasLiveLocationRequiresBothDrafts() {
        XCTAssertTrue(
            GoogleMapsSheetSupport.hasLiveLocation(
                latitudeDraft: " 34.050481 ",
                longitudeDraft: "\n-118.248526"
            )
        )
        XCTAssertFalse(
            GoogleMapsSheetSupport.hasLiveLocation(
                latitudeDraft: "34.050481",
                longitudeDraft: " "
            )
        )
        XCTAssertFalse(
            GoogleMapsSheetSupport.hasLiveLocation(
                latitudeDraft: "",
                longitudeDraft: "-118.248526"
            )
        )
    }

    func testSummaryTextCoversEnabledAndLocationStates() {
        XCTAssertEqual(
            GoogleMapsSheetSupport.summaryText(isEnabled: true, hasLiveLocation: true),
            "Maps grounding is on and uses your pinned coordinates."
        )
        XCTAssertEqual(
            GoogleMapsSheetSupport.summaryText(isEnabled: true, hasLiveLocation: false),
            "Maps grounding is on."
        )
        XCTAssertEqual(
            GoogleMapsSheetSupport.summaryText(isEnabled: false, hasLiveLocation: true),
            "A location is saved, but grounding is off."
        )
        XCTAssertEqual(
            GoogleMapsSheetSupport.summaryText(isEnabled: false, hasLiveLocation: false),
            "Turn Maps grounding on for place-aware answers."
        )
    }

    func testComposerPresentationTextMatchesControlState() {
        XCTAssertNil(GoogleMapsSheetSupport.composerBadgeText(isEnabled: false, hasLocation: true))
        XCTAssertNil(GoogleMapsSheetSupport.composerBadgeText(isEnabled: true, hasLocation: false))
        XCTAssertEqual(GoogleMapsSheetSupport.composerBadgeText(isEnabled: true, hasLocation: true), "Loc")

        XCTAssertEqual(
            GoogleMapsSheetSupport.composerHelpText(isEnabled: false, hasLocation: true),
            "Google Maps: Off"
        )
        XCTAssertEqual(
            GoogleMapsSheetSupport.composerHelpText(isEnabled: true, hasLocation: false),
            "Google Maps: On"
        )
        XCTAssertEqual(
            GoogleMapsSheetSupport.composerHelpText(isEnabled: true, hasLocation: true),
            "Google Maps: On (with location)"
        )
    }

    func testTrimmedLanguageCodeReturnsNilForBlankDraft() {
        XCTAssertEqual(GoogleMapsSheetSupport.trimmedLanguageCode(" en_US\n"), "en_US")
        XCTAssertNil(GoogleMapsSheetSupport.trimmedLanguageCode(" \n "))
    }

    func testFormattedCoordinateValueTrimsTrailingZeros() {
        XCTAssertEqual(GoogleMapsSheetSupport.formattedCoordinateValue(34.050481), "34.050481")
        XCTAssertEqual(GoogleMapsSheetSupport.formattedCoordinateValue(-118.2), "-118.2")
        XCTAssertEqual(GoogleMapsSheetSupport.formattedCoordinateValue(0), "0")
    }

    #if canImport(CoreLocation)
    func testLocationErrorMessageMapsKnownCoreLocationErrors() {
        XCTAssertEqual(
            GoogleMapsSheetSupport.locationErrorMessage(for: CLError(.denied)),
            "Location access was denied."
        )
        XCTAssertEqual(
            GoogleMapsSheetSupport.locationErrorMessage(for: CLError(.locationUnknown)),
            "Current location is temporarily unavailable. Try again in a moment."
        )
    }
    #endif

    func testLocationErrorMessageFallsBackToLocalizedDescription() {
        XCTAssertEqual(
            GoogleMapsSheetSupport.locationErrorMessage(for: StubError(message: "  Unable to resolve location. \n")),
            "Unable to resolve location."
        )
        XCTAssertEqual(
            GoogleMapsSheetSupport.locationErrorMessage(for: StubError(message: " \n")),
            "Current location could not be determined."
        )
    }

    private struct StubError: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
    }
}
