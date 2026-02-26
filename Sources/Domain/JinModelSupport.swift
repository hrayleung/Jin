import Foundation

enum JinModelSupport {
    static let fullSupportSymbol = "✦"

    static func isFullySupported(providerType: ProviderType, modelID: String) -> Bool {
        ModelCatalog.isFullySupported(modelID: modelID, provider: providerType)
    }

    static func supportsNativePDF(providerType: ProviderType, modelID: String) -> Bool {
        ModelCatalog.entry(for: modelID, provider: providerType)?.capabilities.contains(.nativePDF) ?? false
    }
}
