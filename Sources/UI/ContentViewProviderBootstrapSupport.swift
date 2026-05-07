import Foundation

enum ContentViewProviderBootstrapSupport {
    static func defaultIconIDIfNeeded(
        currentIconID: String?,
        providerType: ProviderType?
    ) -> String? {
        guard currentIconID?.trimmedNonEmpty == nil else { return nil }
        guard let providerType else { return nil }
        return LobeProviderIconCatalog.defaultIconID(for: providerType)
    }
}
