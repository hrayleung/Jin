import Foundation

struct ResolvedModelSettings {
    let modelType: ModelType
    let capabilities: ModelCapability
    let contextWindow: Int
    let maxOutputTokens: Int?
    let reasoningConfig: ModelReasoningConfig?
    let reasoningCanDisable: Bool
    let supportsWebSearch: Bool
    let requestShape: ModelRequestShape
    let supportsOpenAIStyleReasoningEffort: Bool
    let supportsOpenAIStyleExtremeEffort: Bool
}

enum ModelSettingsResolver {

    static func resolve(model: ModelInfo, providerType: ProviderType?) -> ResolvedModelSettings {
        let overrides = model.overrides

        let capabilities = overrides?.capabilities ?? model.capabilities
        let inferredContextWindow = inferredContextWindow(
            for: providerType,
            modelID: model.id,
            fallback: model.contextWindow
        )
        let contextWindow = max(1, overrides?.contextWindow ?? inferredContextWindow)
        let inferredReasoningConfig = inferredReasoningConfig(
            for: providerType,
            modelID: model.id,
            fallback: model.reasoningConfig
        )
        var reasoningConfig = overrides?.reasoningConfig ?? inferredReasoningConfig
        if !capabilities.contains(.reasoning) {
            // Backward compatibility: older overrides could remove reasoning capability
            // without persisting an explicit reasoningConfig override.
            reasoningConfig = nil
        }
        let maxOutputTokens = normalizedPositiveInt(overrides?.maxOutputTokens)

        let modelType = overrides?.modelType
            ?? inferModelType(capabilities: capabilities, modelID: model.id)

        let reasoningCanDisable = overrides?.reasoningCanDisable
            ?? defaultReasoningCanDisable(for: providerType, modelID: model.id)
        let supportsWebSearch = overrides?.webSearchSupported
            ?? ModelCapabilityRegistry.supportsWebSearch(for: providerType, modelID: model.id)

        let requestShape = ModelCapabilityRegistry.requestShape(for: providerType, modelID: model.id)
        let supportsOpenAIStyleReasoningEffort = ModelCapabilityRegistry.supportsOpenAIStyleReasoningEffort(
            for: providerType,
            modelID: model.id
        )
        let supportsOpenAIStyleExtremeEffort = ModelCapabilityRegistry.supportsOpenAIStyleExtremeEffort(
            for: providerType,
            modelID: model.id
        )

        return ResolvedModelSettings(
            modelType: modelType,
            capabilities: capabilities,
            contextWindow: contextWindow,
            maxOutputTokens: maxOutputTokens,
            reasoningConfig: reasoningConfig,
            reasoningCanDisable: reasoningCanDisable,
            supportsWebSearch: supportsWebSearch,
            requestShape: requestShape,
            supportsOpenAIStyleReasoningEffort: supportsOpenAIStyleReasoningEffort,
            supportsOpenAIStyleExtremeEffort: supportsOpenAIStyleExtremeEffort
        )
    }

    static func inferModelType(capabilities: ModelCapability, modelID _: String) -> ModelType {
        if capabilities.contains(.videoGeneration) {
            return .video
        }
        if capabilities.contains(.imageGeneration) {
            return .image
        }
        return .chat
    }

    static func defaultReasoningCanDisable(for providerType: ProviderType?, modelID: String) -> Bool {
        guard let providerType else { return true }
        if providerType == .fireworks {
            return !isFireworksMiniMaxM2FamilyModel(modelID)
        }
        return true
    }

    private static func normalizedPositiveInt(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func inferredContextWindow(for providerType: ProviderType?, modelID: String, fallback: Int) -> Int {
        guard let providerType else { return fallback }
        return ModelCatalog.entry(for: modelID, provider: providerType)?.contextWindow ?? fallback
    }

    private static func inferredReasoningConfig(
        for providerType: ProviderType?,
        modelID: String,
        fallback: ModelReasoningConfig?
    ) -> ModelReasoningConfig? {
        guard let providerType else { return fallback }
        guard let entry = ModelCatalog.entry(for: modelID, provider: providerType) else {
            return fallback
        }
        return entry.reasoningConfig
    }

}
