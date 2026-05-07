import Foundation

extension ProviderFormSupport {
    static func updatedDraftValues(
        oldType: ProviderType,
        newType: ProviderType,
        name: String,
        baseURL: String,
        iconID: String?
    ) -> DraftValues {
        var values = DraftValues(name: name, baseURL: baseURL, iconID: iconID)

        let normalizedBaseURL = normalizedOptionalString(baseURL)
        if normalizedBaseURL == nil || oldType.defaultBaseURL == normalizedBaseURL {
            values.baseURL = newType.defaultBaseURL ?? ""
        }

        let oldDefaultIconID = LobeProviderIconCatalog.defaultIconID(for: oldType)
        let currentIconID = normalizedIconID(iconID)
        if currentIconID == nil || currentIconID == oldDefaultIconID {
            values.iconID = LobeProviderIconCatalog.defaultIconID(for: newType)
        }

        let normalizedName = normalizedOptionalString(name)
        if normalizedName == nil || normalizedName == oldType.displayName {
            values.name = newType.displayName
        }

        return values
    }
}
