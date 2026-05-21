import Foundation
@testable import Jin

enum GoogleMapsCoordinateFixture {
    static let latitude = roundedCoordinate(Double.pi)
    static let longitude = roundedCoordinate(-Double.pi)
    static let alternateLatitude = roundedCoordinate(Double.pi / 2)
    static let alternateLongitude = roundedCoordinate(-Double.pi / 2)

    static var latitudeDraft: String {
        GoogleMapsSheetSupport.formattedCoordinateValue(latitude)
    }

    static var longitudeDraft: String {
        GoogleMapsSheetSupport.formattedCoordinateValue(longitude)
    }

    static var alternateLatitudeDraft: String {
        GoogleMapsSheetSupport.formattedCoordinateValue(alternateLatitude)
    }

    static var alternateLongitudeDraft: String {
        GoogleMapsSheetSupport.formattedCoordinateValue(alternateLongitude)
    }

    static var instructionLatitudeFragment: String {
        "latitude \(String(format: "%.6f", latitude))"
    }

    static var instructionLongitudeFragment: String {
        "longitude \(String(format: "%.6f", longitude))"
    }

    private static func roundedCoordinate(_ value: Double) -> Double {
        (value * 1_000_000).rounded() / 1_000_000
    }
}
