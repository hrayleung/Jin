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
    private static let inferredContextWindowByProvider: [ProviderType: [String: Int]] = [
        .openai: [
            "gpt-5": 400_000,
            "gpt-5.2": 400_000,
            "gpt-5.2-2025-12-11": 400_000,
        ],
        .anthropic: [
            "claude-opus-4": 200_000,
            "claude-sonnet-4": 200_000,
            "claude-haiku-4": 200_000,
            "claude-opus-4-6": 200_000,
            "claude-sonnet-4-6": 200_000,
            "claude-opus-4-5-20251101": 200_000,
            "claude-sonnet-4-5-20250929": 200_000,
            "claude-haiku-4-5-20251001": 200_000,
        ],
        .perplexity: [
            "sonar-pro": 200_000,
        ],
        .fireworks: [
            "fireworks/minimax-m2p5": 196_600,
            "accounts/fireworks/models/minimax-m2p5": 196_600,
            "fireworks/minimax-m2p1": 204_800,
            "accounts/fireworks/models/minimax-m2p1": 204_800,
            "fireworks/minimax-m2": 196_600,
            "accounts/fireworks/models/minimax-m2": 196_600,
            "fireworks/kimi-k2p5": 262_100,
            "accounts/fireworks/models/kimi-k2p5": 262_100,
            "fireworks/glm-5": 202_800,
            "accounts/fireworks/models/glm-5": 202_800,
            "fireworks/glm-4p7": 202_800,
            "accounts/fireworks/models/glm-4p7": 202_800,
        ],
        .cerebras: [
            "zai-glm-4.7": 131_072,
        ],
        .xai: [
            "grok-4-1": 2_000_000,
            "grok-4-1-fast": 2_000_000,
            "grok-4-1-fast-non-reasoning": 2_000_000,
            "grok-4-1-fast-reasoning": 2_000_000,
            "grok-2-image-1212": 131_072,
            "grok-imagine-image": 32_768,
            "grok-imagine-video": 32_768,
        ],
        .gemini: [
            "gemini-3": 1_048_576,
            "gemini-3-pro": 1_048_576,
            "gemini-3-pro-preview": 1_048_576,
            "gemini-3.1-pro-preview": 1_048_576,
            "gemini-3-flash-preview": 1_048_576,
            "gemini-3-pro-image-preview": 65_536,
            "gemini-2.5-flash-image": 32_768,
        ],
        .vertexai: [
            "gemini-3": 1_048_576,
            "gemini-3-pro": 1_048_576,
            "gemini-3-pro-preview": 1_048_576,
            "gemini-3.1-pro-preview": 1_048_576,
            "gemini-3-flash-preview": 1_048_576,
            "gemini-3-pro-image-preview": 65_536,
            "gemini-2.5": 1_048_576,
            "gemini-2.5-pro": 1_048_576,
            "gemini-2.5-flash": 1_048_576,
            "gemini-2.5-flash-lite": 1_048_576,
            "gemini-2.5-flash-image": 32_768,
        ],
    ]

    static func resolve(model: ModelInfo, providerType: ProviderType?) -> ResolvedModelSettings {
        let overrides = model.overrides

        let capabilities = overrides?.capabilities ?? model.capabilities
        let inferredContextWindow = inferredContextWindow(
            for: providerType,
            modelID: model.id,
            fallback: model.contextWindow
        )
        let contextWindow = max(1, overrides?.contextWindow ?? inferredContextWindow)
        var reasoningConfig = overrides?.reasoningConfig ?? model.reasoningConfig
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
        let lowerModelID = modelID.lowercased()
        guard let mapped = inferredContextWindowByProvider[providerType]?[lowerModelID] else {
            return fallback
        }
        return mapped
    }

    private static func isFireworksMiniMaxM2FamilyModel(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        let canonicalID: String?
        if lower.hasPrefix("fireworks/") {
            canonicalID = String(lower.dropFirst("fireworks/".count))
        } else if lower.hasPrefix("accounts/fireworks/models/") {
            canonicalID = String(lower.dropFirst("accounts/fireworks/models/".count))
        } else if !lower.contains("/") {
            canonicalID = lower
        } else {
            canonicalID = nil
        }

        guard let canonicalID else { return false }
        return canonicalID == "minimax-m2"
            || canonicalID == "minimax-m2p1"
            || canonicalID == "minimax-m2p5"
    }
}
