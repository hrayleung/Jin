import Foundation

enum ChatNamingModelSupport {
    static func isSupported(model: ModelInfo, providerType: ProviderType?) -> Bool {
        let resolved = ModelSettingsResolver.resolve(model: model, providerType: providerType)
        return resolved.modelType == .chat
    }

    static func isSupported(providerConfig: ProviderConfig, modelID: String) -> Bool {
        if let model = configuredModel(in: providerConfig, modelID: modelID) {
            return isSupported(model: model, providerType: providerConfig.type)
        }

        if let entry = ModelCatalog.entry(for: modelID, provider: providerConfig.type) {
            let model = ModelInfo(
                id: modelID,
                name: entry.displayName,
                capabilities: entry.capabilities,
                contextWindow: entry.contextWindow,
                maxOutputTokens: entry.maxOutputTokens,
                reasoningConfig: entry.reasoningConfig
            )
            return isSupported(model: model, providerType: providerConfig.type)
        }

        return true
    }

    static func supportedModels(
        from models: [ModelInfo],
        providerType: ProviderType?
    ) -> [ModelInfo] {
        models.filter { isSupported(model: $0, providerType: providerType) }
    }

    static func shouldRequestStreaming(providerConfig: ProviderConfig, modelID: String) -> Bool {
        if let model = configuredModel(in: providerConfig, modelID: modelID) {
            let resolved = ModelSettingsResolver.resolve(model: model, providerType: providerConfig.type)
            return resolved.capabilities.contains(.streaming)
        }

        if let entry = ModelCatalog.entry(for: modelID, provider: providerConfig.type) {
            return entry.capabilities.contains(.streaming)
        }

        return true
    }

    private static func configuredModel(in providerConfig: ProviderConfig, modelID: String) -> ModelInfo? {
        if let exact = providerConfig.models.first(where: { $0.id == modelID }) {
            return exact
        }

        let target = modelID.lowercased()
        return providerConfig.models.first { $0.id.lowercased() == target }
    }
}
