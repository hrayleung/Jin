import Foundation

/// Pure persist helpers for composer generation controls.
///
/// Control edits are not conversation activity: callers must write
/// `modelConfigData` only and must not bump `updatedAt` (that watermark
/// rebuilds the timeline and re-sorts the sidebar).
enum ChatGenerationControlsPersistenceSupport {
    static func mergedForPersist(
        live: GenerationControls,
        stored: GenerationControls?
    ) -> GenerationControls {
        var merged = live
        merged.claudeManagedSessionID = stored?.claudeManagedSessionID
        merged.claudeManagedSessionModelID = stored?.claudeManagedSessionModelID
        merged.claudeManagedPendingCustomToolResults =
            stored?.claudeManagedPendingCustomToolResults ?? []
        return merged
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func encodedPayloadIfChanged(
        merged: GenerationControls,
        currentData: Data,
        encoder: JSONEncoder = ChatGenerationControlsPersistenceSupport.makeEncoder()
    ) -> Data? {
        guard let encoded = try? encoder.encode(merged) else { return nil }
        guard encoded != currentData else { return nil }
        return encoded
    }

    static func googleMapsLocationBias(
        from controls: GenerationControls
    ) -> GoogleMapsLocationBias? {
        guard let latitude = controls.googleMaps?.latitude,
              let longitude = controls.googleMaps?.longitude else {
            return nil
        }
        return GoogleMapsLocationBias(latitude: latitude, longitude: longitude)
    }
}
