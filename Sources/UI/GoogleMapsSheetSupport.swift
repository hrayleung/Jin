import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

enum GoogleMapsSheetSupport {
    struct CoordinateDrafts: Equatable {
        let latitude: String?
        let longitude: String?

        init(latitudeDraft: String, longitudeDraft: String) {
            latitude = latitudeDraft.trimmedNonEmpty
            longitude = longitudeDraft.trimmedNonEmpty
        }

        var hasAnyValue: Bool {
            latitude != nil || longitude != nil
        }

        var hasLiveLocation: Bool {
            latitude != nil && longitude != nil
        }
    }

    static func coordinateDrafts(
        latitudeDraft: String,
        longitudeDraft: String
    ) -> CoordinateDrafts {
        CoordinateDrafts(latitudeDraft: latitudeDraft, longitudeDraft: longitudeDraft)
    }

    static func hasCoordinateDrafts(latitudeDraft: String, longitudeDraft: String) -> Bool {
        coordinateDrafts(
            latitudeDraft: latitudeDraft,
            longitudeDraft: longitudeDraft
        ).hasAnyValue
    }

    static func hasLiveLocation(latitudeDraft: String, longitudeDraft: String) -> Bool {
        coordinateDrafts(
            latitudeDraft: latitudeDraft,
            longitudeDraft: longitudeDraft
        ).hasLiveLocation
    }

    static func summaryText(isEnabled: Bool, hasLiveLocation: Bool) -> String {
        if isEnabled {
            if hasLiveLocation {
                return "Maps grounding is on and uses your pinned coordinates."
            }
            return "Maps grounding is on."
        }
        if hasLiveLocation {
            return "A location is saved, but grounding is off."
        }
        return "Turn Maps grounding on for place-aware answers."
    }

    static func composerBadgeText(isEnabled: Bool, hasLocation: Bool) -> String? {
        guard isEnabled else { return nil }
        return hasLocation ? "Loc" : nil
    }

    static func composerHelpText(isEnabled: Bool, hasLocation: Bool) -> String {
        guard isEnabled else { return "Google Maps: Off" }
        return hasLocation ? "Google Maps: On (with location)" : "Google Maps: On"
    }

    static func trimmedLanguageCode(_ languageCodeDraft: String) -> String? {
        languageCodeDraft.trimmedNonEmpty
    }

    static func formattedCoordinateValue(_ value: Double) -> String {
        let formatted = String(format: "%.6f", value)
        return formatted.replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    static func locationErrorMessage(for error: Error) -> String {
        #if canImport(CoreLocation)
        if let locationError = error as? CLError {
            switch locationError.code {
            case .denied:
                return "Location access was denied."
            case .locationUnknown:
                return "Current location is temporarily unavailable. Try again in a moment."
            default:
                break
            }
        }
        #endif

        guard let message = error.localizedDescription.trimmedNonEmpty else {
            return "Current location could not be determined."
        }
        return message
    }
}
