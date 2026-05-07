import Foundation

struct PreparedGoogleMapsEditorDraft {
    let draft: GoogleMapsControls
    let latitudeDraft: String
    let longitudeDraft: String
    let languageCodeDraft: String
}

struct AppliedGoogleMapsControls {
    let controls: GenerationControls
    let googleMaps: GoogleMapsControls?
}

extension ChatAuxiliaryControlSupport {
    static func prepareGoogleMapsEditorDraft(
        current: GoogleMapsControls?,
        isEnabled: Bool
    ) -> PreparedGoogleMapsEditorDraft {
        let draft = current ?? GoogleMapsControls(enabled: isEnabled)
        return PreparedGoogleMapsEditorDraft(
            draft: draft,
            latitudeDraft: draft.latitude.map { String($0) } ?? "",
            longitudeDraft: draft.longitude.map { String($0) } ?? "",
            languageCodeDraft: draft.languageCode ?? ""
        )
    }

    static func isGoogleMapsDraftValid(
        latitudeDraft: String,
        longitudeDraft: String
    ) -> Bool {
        switch validatedGoogleMapsCoordinates(
            latitudeDraft: latitudeDraft,
            longitudeDraft: longitudeDraft
        ) {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    static func applyGoogleMapsDraft(
        draft: GoogleMapsControls,
        latitudeDraft: String,
        longitudeDraft: String,
        languageCodeDraft: String,
        providerType: ProviderType?
    ) -> Result<GoogleMapsControls?, ChatEditorDraftError> {
        var draft = draft

        switch validatedGoogleMapsCoordinates(
            latitudeDraft: latitudeDraft,
            longitudeDraft: longitudeDraft
        ) {
        case .success(let coordinates):
            draft.latitude = coordinates.latitude
            draft.longitude = coordinates.longitude
        case .failure(let error):
            return .failure(error)
        }

        if providerType == .vertexai, let languageCode = languageCodeDraft.trimmedNonEmpty {
            draft.languageCode = languageCode
        } else {
            draft.languageCode = nil
        }

        if draft.enableWidget != true {
            draft.enableWidget = nil
        }

        return .success(draft.isEmpty ? nil : draft)
    }

    static func applyGoogleMapsDraft(
        draft: GoogleMapsControls,
        latitudeDraft: String,
        longitudeDraft: String,
        languageCodeDraft: String,
        providerType: ProviderType?,
        controls: GenerationControls
    ) -> Result<AppliedGoogleMapsControls, ChatEditorDraftError> {
        applyGoogleMapsDraft(
            draft: draft,
            latitudeDraft: latitudeDraft,
            longitudeDraft: longitudeDraft,
            languageCodeDraft: languageCodeDraft,
            providerType: providerType
        ).map { googleMaps in
            var controls = controls
            controls.googleMaps = googleMaps
            return AppliedGoogleMapsControls(
                controls: controls,
                googleMaps: googleMaps
            )
        }
    }

    static func clearGoogleMapsLocation(controls: GenerationControls) -> GenerationControls {
        var controls = controls
        controls.googleMaps?.latitude = nil
        controls.googleMaps?.longitude = nil
        return controls
    }

    static func setGoogleMapsEnabled(
        _ isEnabled: Bool,
        controls: GenerationControls
    ) -> GenerationControls {
        var controls = controls
        var updated = controls.googleMaps ?? GoogleMapsControls(enabled: isEnabled)
        updated.enabled = isEnabled
        controls.googleMaps = updated.isEmpty ? nil : updated
        return controls
    }

    private static func validatedGoogleMapsCoordinates(
        latitudeDraft: String,
        longitudeDraft: String
    ) -> Result<(latitude: Double?, longitude: Double?), ChatEditorDraftError> {
        let coordinateDrafts = GoogleMapsSheetSupport.coordinateDrafts(
            latitudeDraft: latitudeDraft,
            longitudeDraft: longitudeDraft
        )

        if !coordinateDrafts.hasAnyValue {
            return .success((nil, nil))
        }

        guard let trimmedLatitude = coordinateDrafts.latitude,
              let trimmedLongitude = coordinateDrafts.longitude else {
            return .failure(.message("Enter both latitude and longitude, or leave both empty."))
        }

        guard let latitude = Double(trimmedLatitude), (-90...90).contains(latitude) else {
            return .failure(.message("Latitude must be a number between -90 and 90."))
        }

        guard let longitude = Double(trimmedLongitude), (-180...180).contains(longitude) else {
            return .failure(.message("Longitude must be a number between -180 and 180."))
        }

        return .success((latitude, longitude))
    }
}
