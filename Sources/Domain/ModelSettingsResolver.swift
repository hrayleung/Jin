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
        let catalogEntry = catalogEntry(for: model, providerType: providerType)

        let capabilities = resolvedCapabilities(
            overrides: overrides,
            catalogEntry: catalogEntry,
            fallback: model.capabilities
        )
        let contextWindow = max(
            1,
            resolvedContextWindow(
                overrides: overrides,
                catalogEntry: catalogEntry,
                fallback: model.contextWindow
            )
        )
        let reasoningConfig = resolvedReasoningConfig(
            overrides: overrides,
            catalogEntry: catalogEntry,
            fallback: model.reasoningConfig,
            capabilities: capabilities
        )
        let maxOutputTokens = resolvedMaxOutputTokens(
            overrides: overrides,
            catalogEntry: catalogEntry,
            fallback: model.maxOutputTokens
        )
        let modelType = overrides?.modelType ?? inferModelType(capabilities: capabilities, modelID: model.id)
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
        if providerType == .together {
            return !isTogetherAlwaysOnReasoningModel(modelID)
        }
        if providerType == .sambanova {
            return !isSambaNovaAlwaysOnReasoningModel(modelID)
        }
        if providerType == .xai {
            return !xaiAlwaysOnReasoningModelIDs.contains(modelID.lowercased())
        }
        if providerType == .openrouter {
            return !openRouterAlwaysOnReasoningModelIDs.contains(modelID.lowercased())
        }
        if providerType == .vercelAIGateway {
            return !vercelAIGatewayAlwaysOnReasoningModelIDs.contains(modelID.lowercased())
        }
        if providerType == .meta {
            // Muse Spark's reasoning cannot be disabled (Meta docs: thinking
            // {type:"disabled"} / reasoning_effort "none" both return HTTP 400).
            return false
        }
        if providerType == .kimiForCoding {
            // Kimi K2.7 Code is thinking-always-on (Kimi Code docs: "Thinking: ON";
            // requests without thinking are silently routed to K2.6). K3 keeps its
            // reasoningConfig nil so this default is moot for it.
            return !kimiForCodingAlwaysOnReasoningModelIDs.contains(modelID.lowercased())
        }
        return true
    }

    private static func resolvedCapabilities(
        overrides: ModelOverrides?,
        catalogEntry: ModelCatalogEntry?,
        fallback: ModelCapability
    ) -> ModelCapability {
        overrides?.capabilities ?? catalogEntry?.capabilities ?? fallback
    }

    private static func resolvedContextWindow(
        overrides: ModelOverrides?,
        catalogEntry: ModelCatalogEntry?,
        fallback: Int
    ) -> Int {
        overrides?.contextWindow ?? catalogEntry?.contextWindow ?? fallback
    }

    private static func resolvedMaxOutputTokens(
        overrides: ModelOverrides?,
        catalogEntry: ModelCatalogEntry?,
        fallback: Int?
    ) -> Int? {
        normalizedPositiveInt(overrides?.maxOutputTokens)
            ?? normalizedPositiveInt(catalogEntry?.maxOutputTokens)
            ?? normalizedPositiveInt(fallback)
    }

    private static func resolvedReasoningConfig(
        overrides: ModelOverrides?,
        catalogEntry: ModelCatalogEntry?,
        fallback: ModelReasoningConfig?,
        capabilities: ModelCapability
    ) -> ModelReasoningConfig? {
        guard capabilities.contains(.reasoning) else {
            return nil
        }

        if let override = overrides?.reasoningConfig {
            return override
        }

        if let catalogEntry {
            return catalogEntry.reasoningConfig
        }

        return fallback
    }

    private static func catalogEntry(
        for model: ModelInfo,
        providerType: ProviderType?
    ) -> ModelCatalogEntry? {
        guard let providerType else { return nil }
        return ModelCatalog.entry(for: model.id, provider: providerType)
    }

    private static func normalizedPositiveInt(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    /// Exact-ID allowlist for SambaNova models where reasoning cannot be disabled.
    /// Keep this strict to avoid misclassifying unknown models by substring.
    private static let sambaNovaAlwaysOnReasoningModelIDs: Set<String> = [
        "gpt-oss-120b",
        "deepseek-r1-0528",
        "deepseek-r1-distill-llama-70b",
    ]

    /// Exact-ID allowlist for Together models whose documented controls expose
    /// reasoning effort only, not a true on/off toggle.
    private static let togetherAlwaysOnReasoningModelIDs: Set<String> = [
        "openai/gpt-oss-120b",
        "openai/gpt-oss-20b",
    ]

    /// xAI models where reasoning is always-on ("Reasoning cannot be disabled" per
    /// docs.x.ai for grok-4.5); only the effort is adjustable.
    private static let xaiAlwaysOnReasoningModelIDs: Set<String> = [
        "grok-4.5",
    ]

    /// OpenRouter models whose live /models metadata reports reasoning.mandatory=true
    /// (grok-4.5, fable-5, and fugu-ultra verified 2026-07-11; kimi-k3 verified 2026-07-18).
    private static let openRouterAlwaysOnReasoningModelIDs: Set<String> = [
        "x-ai/grok-4.5",
        "anthropic/claude-fable-5",
        "sakana/fugu-ultra",
        "moonshotai/kimi-k3",
    ]

    /// Vercel AI Gateway twins of upstream always-on reasoning models (grok-4.5 and
    /// Muse Spark both reject disabled reasoning upstream).
    private static let vercelAIGatewayAlwaysOnReasoningModelIDs: Set<String> = [
        "xai/grok-4.5",
        "meta/muse-spark-1.1",
    ]

    /// Kimi for Coding IDs whose thinking is always-on (Kimi Code docs list
    /// "Thinking: ON" for both K2.7 Code variants).
    private static let kimiForCodingAlwaysOnReasoningModelIDs: Set<String> = [
        "kimi-for-coding",
        "kimi-for-coding-highspeed",
    ]

    private static func isSambaNovaAlwaysOnReasoningModel(_ modelID: String) -> Bool {
        sambaNovaAlwaysOnReasoningModelIDs.contains(modelID.lowercased())
    }

    private static func isTogetherAlwaysOnReasoningModel(_ modelID: String) -> Bool {
        togetherAlwaysOnReasoningModelIDs.contains(modelID.lowercased())
    }
}
