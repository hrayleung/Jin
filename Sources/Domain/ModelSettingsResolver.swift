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
        let lookupID = ModalEndpointSupport.catalogModelID(for: model)
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
        let modelType = overrides?.modelType ?? inferModelType(capabilities: capabilities, modelID: lookupID)
        let reasoningCanDisable = overrides?.reasoningCanDisable
            ?? defaultReasoningCanDisable(
                for: providerType,
                modelID: lookupID,
                declaredEfforts: reasoningConfig?.supportedEfforts
            )
        let supportsWebSearch = overrides?.webSearchSupported
            ?? ModelCapabilityRegistry.supportsWebSearch(for: providerType, modelID: lookupID)
        let requestShape = ModelCapabilityRegistry.requestShape(for: providerType, modelID: lookupID)
        let supportsOpenAIStyleReasoningEffort = ModelCapabilityRegistry.supportsOpenAIStyleReasoningEffort(
            for: providerType,
            modelID: lookupID
        )
        let supportsOpenAIStyleExtremeEffort = ModelCapabilityRegistry.supportsOpenAIStyleExtremeEffort(
            for: providerType,
            modelID: lookupID
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

    static func defaultReasoningCanDisable(
        for providerType: ProviderType?,
        modelID: String,
        declaredEfforts: [ReasoningEffort]? = nil
    ) -> Bool {
        guard let providerType else { return true }
        if providerType == .fireworks {
            return !isFireworksAlwaysOnReasoningModel(modelID)
        }
        if providerType == .together {
            return !isTogetherAlwaysOnReasoningModel(modelID)
        }
        if providerType == .deepinfra {
            return !deepInfraAlwaysOnReasoningModelIDs.contains(modelID.lowercased())
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
        if providerType == .opencodeGo {
            return !opencodeGoAlwaysOnReasoningModelIDs.contains(modelID.lowercased())
        }
        if providerType == .zhipuCodingPlan {
            return !zhipuAlwaysOnReasoningModelIDs.contains(modelID.lowercased())
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
        if providerType == .router {
            // Router publishes an exact effort band per model and rejects anything
            // outside it. A band without `none` means thinking cannot be turned off,
            // so derive the answer instead of maintaining a second always-on list
            // that could drift out of sync with the bands.
            return ModelCapabilityRegistry
                .supportedReasoningEfforts(
                    for: .router,
                    modelID: modelID,
                    declaredEfforts: declaredEfforts
                )
                .contains(ReasoningEffort.none)
        }
        if providerType == .modal {
            // Qwen3.8-2.4T-A95B requires thinking on every turn (HF card + Modal
            // library, 2026-08-12). Kimi K3 / Inkling stay toggleable via `none`.
            return !modalAlwaysOnReasoningModelIDs.contains(modelID.lowercased())
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
        return ModelCatalog.entry(
            for: ModalEndpointSupport.catalogModelID(for: model),
            provider: providerType
        )
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
    /// reasoning effort only, not a true on/off toggle. Inkling behaves the same:
    /// Jin sends `reasoning_effort` but nothing when "off", so thinking would stay
    /// on at the server default anyway (Together docs, verified 2026-07-18).
    private static let togetherAlwaysOnReasoningModelIDs: Set<String> = [
        "openai/gpt-oss-120b",
        "openai/gpt-oss-20b",
        "thinkingmachines/inkling",
        "qwen/qwen3.8-2.4t-a95b",
    ]

    /// DeepInfra IDs whose thinking cannot be turned off. Exact-ID only.
    /// Qwen3.8-2.4T-A95B: HF card — thinking is always enabled.
    private static let deepInfraAlwaysOnReasoningModelIDs: Set<String> = [
        "qwen/qwen3.8-2.4t-a95b",
    ]

    /// xAI models where reasoning is always-on ("Reasoning cannot be disabled" per
    /// docs.x.ai for grok-4.6 / grok-4.5); only the effort is adjustable.
    private static let xaiAlwaysOnReasoningModelIDs: Set<String> = [
        "grok-4.6",
        "grok-4.5",
    ]

    /// OpenCode Go models whose upstream reasoning cannot be disabled. Grok 4.6 / 4.5 are
    /// served under their bare upstream slugs there, so they inherit xAI's "Reasoning cannot
    /// be disabled" constraint (docs.x.ai). DeepSeek V4 is the same class of lock for a
    /// different reason: official DeepSeek thinking is on by default and only turns off with
    /// `thinking: {"type": "disabled"}`, but the Go gateway is a strict chat/completions
    /// proxy that rejects that extra field. Omitting `reasoning_effort` therefore leaves
    /// thinking on, so the UI must not offer Off. GLM-5.3 rejects `thinking.type:
    /// disabled` (z.ai/blog/glm-5.3); disable is converted to `low`. Ox Alpha Free
    /// (`ox-alpha-free`) is the same always-on low/high/max band (models.dev
    /// `opencode-go`, 2026-08-22). Muse Spark rejects `reasoning.effort: "none"` with
    /// HTTP 400 (Meta docs); omit the field instead and lock the Off toggle. Other
    /// GLM / Kimi / MiMo stay on the provider-wide omit-to-disable convention.
    private static let opencodeGoAlwaysOnReasoningModelIDs: Set<String> = [
        "grok-4.6",
        "grok-4.5",
        "deepseek-v4-pro",
        "deepseek-v4-flash",
        "glm-5.3",
        "ox-alpha-free",
        "muse-spark-1.2",
        "muse-spark-1.2-contributor",
    ]

    /// Zhipu / Z.AI Coding Plan IDs whose thinking cannot be turned off. GLM-5.3
    /// rejects `thinking.type: "disabled"` (z.ai/blog/glm-5.3); the coding-plan
    /// endpoint converts that to `low`. Exact IDs only.
    private static let zhipuAlwaysOnReasoningModelIDs: Set<String> = [
        "glm-5.3",
        "glm-5.3[1m]",
    ]

    /// OpenRouter models whose live /models metadata reports reasoning.mandatory=true
    /// (verified 2026-07-11). Kimi K3 is deliberately NOT listed: it is mandatory too,
    /// but its catalog record keeps reasoningConfig nil (no reasoning UI, no reasoning
    /// shape sent), making this default moot — same precedent as `k3` on Kimi for Coding.
    private static let openRouterAlwaysOnReasoningModelIDs: Set<String> = [
        "x-ai/grok-4.6",
        "x-ai/grok-4.5",
        "anthropic/claude-fable-5",
        "sakana/fugu-ultra",
        "meta/muse-spark-1.1",
        "meta/muse-spark-1.2",
        "qwen/qwen3.8-2.4t-a95b",
        "qwen/qwen3.8-max",
        "stealth/ox-alpha",
    ]

    /// Vercel AI Gateway twins of upstream always-on reasoning models (grok-4.6 /
    /// grok-4.5 and Muse Spark both reject disabled reasoning upstream). Kimi K3 is
    /// deliberately NOT listed: thinking is always-on upstream too, but its catalog
    /// record keeps reasoningConfig nil (no reasoning UI, no reasoning shape sent),
    /// making this default moot — same precedent as `k3` on Kimi for Coding.
    private static let vercelAIGatewayAlwaysOnReasoningModelIDs: Set<String> = [
        "xai/grok-4.6",
        "xai/grok-4.5",
        "meta/muse-spark-1.1",
        "meta/muse-spark-1.2",
        "meta/muse-spark-1.2-contributor",
    ]

    /// Kimi for Coding IDs whose thinking is always-on (Kimi Code docs list
    /// "Thinking: ON" for both K2.7 Code variants).
    private static let kimiForCodingAlwaysOnReasoningModelIDs: Set<String> = [
        "kimi-for-coding",
        "kimi-for-coding-highspeed",
    ]

    /// Modal Shared API IDs whose thinking cannot be disabled. Exact-ID only:
    /// `qwen3.8-max` and other Qwen slugs are different products (cloud Max is
    /// multimodal and toggleable).
    private static let modalAlwaysOnReasoningModelIDs: Set<String> = [
        "qwen/qwen3.8-2.4t-a95b",
    ]

    private static func isSambaNovaAlwaysOnReasoningModel(_ modelID: String) -> Bool {
        sambaNovaAlwaysOnReasoningModelIDs.contains(modelID.lowercased())
    }

    private static func isTogetherAlwaysOnReasoningModel(_ modelID: String) -> Bool {
        togetherAlwaysOnReasoningModelIDs.contains(modelID.lowercased())
    }

    /// Fireworks MiniMax M2 family plus Qwen3.8-2.4T (thinking cannot be disabled
    /// on the HF weights). Preview DeepSeek V4 Pro stays disableable.
    private static func isFireworksAlwaysOnReasoningModel(_ modelID: String) -> Bool {
        if isFireworksMiniMaxM2FamilyModel(modelID) {
            return true
        }
        let lower = modelID.lowercased()
        if lower == "accounts/fireworks/models/qwen3p8-2p4t-a95b"
            || lower == "fireworks/qwen3p8-2p4t-a95b"
            || lower == "fireworks/qwen3p8-max"
            || fireworksCanonicalModelID(lower) == "qwen3p8-2p4t-a95b"
            || fireworksCanonicalModelID(lower) == "qwen3p8-max" {
            return true
        }
        return false
    }
}
