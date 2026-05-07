import Foundation

extension ChatControlNormalizationSupport {
    static func normalizeGoogleMapsControls(
        controls: inout GenerationControls,
        providerType: ProviderType?,
        supportsGoogleMapsControl: Bool
    ) {
        guard var googleMaps = controls.googleMaps else { return }

        guard supportsGoogleMapsControl else {
            controls.googleMaps = nil
            return
        }

        if providerType != .vertexai {
            googleMaps.languageCode = nil
        }

        if googleMaps.enableWidget != true {
            googleMaps.enableWidget = nil
        }

        controls.googleMaps = googleMaps.isEmpty ? nil : googleMaps
    }
}
