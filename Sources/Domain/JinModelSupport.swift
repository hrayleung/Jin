import Foundation

/// Single façade for model support queries used by UI and adapters.
///
/// Prefer this over calling `ModelCatalog` / `ModelCapabilityRegistry` separately so
/// dual-read (catalog features → registry fallback) stays consistent.
enum JinModelSupport {
    static let fullSupportSymbol = "✦"

    static func isFullySupported(providerType: ProviderType, modelID: String) -> Bool {
        ModelCatalog.isFullySupported(modelID: modelID, provider: providerType)
    }

    static func supportsNativePDF(providerType: ProviderType, modelID: String) -> Bool {
        ModelCatalog.entry(for: modelID, provider: providerType)?.capabilities.contains(.nativePDF) ?? false
    }

    static func supportsWebSearch(providerType: ProviderType?, modelID: String) -> Bool {
        ModelCapabilityRegistry.supportsWebSearch(for: providerType, modelID: modelID)
    }

    static func supportsCodeExecution(providerType: ProviderType?, modelID: String) -> Bool {
        ModelCapabilityRegistry.supportsCodeExecution(for: providerType, modelID: modelID)
    }

    static func supportsGoogleMaps(providerType: ProviderType?, modelID: String) -> Bool {
        ModelCapabilityRegistry.supportsGoogleMaps(for: providerType, modelID: modelID)
    }

    /// Resolve catalog features (record + declared feature tables) when present.
    static func features(providerType: ProviderType, modelID: String) -> ModelFeatures? {
        ModelCatalog.features(for: modelID, provider: providerType)
    }
}
