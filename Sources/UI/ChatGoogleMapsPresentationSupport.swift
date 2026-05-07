import Foundation

extension ChatModelCapabilitySupport {
    static func googleMapsBadgeText(isEnabled: Bool, hasLocation: Bool) -> String? {
        GoogleMapsSheetSupport.composerBadgeText(
            isEnabled: isEnabled,
            hasLocation: hasLocation
        )
    }

    static func googleMapsHelpText(isEnabled: Bool, hasLocation: Bool) -> String {
        GoogleMapsSheetSupport.composerHelpText(
            isEnabled: isEnabled,
            hasLocation: hasLocation
        )
    }
}
