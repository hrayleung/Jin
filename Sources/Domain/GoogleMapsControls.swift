import Foundation

/// Controls for Google Maps grounding (Gemini / Vertex AI).
///
/// When enabled, the adapter includes a `googleMaps` tool in the request,
/// optionally passing the user's coordinates via `toolConfig.retrievalConfig.latLng`.
struct GoogleMapsControls: Codable {
    var enabled: Bool

    /// Whether to request the `googleMapsWidgetContextToken` in the response.
    var enableWidget: Bool?

    /// User latitude for location-aware results.
    var latitude: Double?

    /// User longitude for location-aware results.
    var longitude: Double?

    /// Optional language code for localising Maps results (e.g. "en_US").
    var languageCode: String?

    init(
        enabled: Bool = false,
        enableWidget: Bool? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        languageCode: String? = nil
    ) {
        self.enabled = enabled
        self.enableWidget = enableWidget
        self.latitude = latitude
        self.longitude = longitude
        self.languageCode = languageCode
    }

    var hasLocation: Bool {
        latitude != nil && longitude != nil
    }

    var isEmpty: Bool {
        !enabled
            && enableWidget == nil
            && latitude == nil
            && longitude == nil
            && (languageCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}
