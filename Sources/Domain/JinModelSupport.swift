import Foundation

enum JinModelSupport {
    static let fullSupportSymbol = "✦"

    // Exact-match allowlists avoid over-marking similarly named custom models.
    private static let fullySupportedModelsByProvider: [ProviderType: Set<String>] = [
        .openai: [
            "gpt-5",
            "gpt-5.2",
            "gpt-5.2-2025-12-11",
            "o3",
            "o4",
            "gpt-4o",
        ],
        .openaiWebSocket: [
            "gpt-5",
            "gpt-5.2",
            "gpt-5.2-2025-12-11",
            "o3",
            "o4",
            "gpt-4o",
        ],
        .openrouter: [
            "google/gemini-3-pro-preview",
            "google/gemini-3.1-pro-preview",
        ],
        .anthropic: [
            "claude-opus-4",
            "claude-opus-4-6",
            "claude-opus-4-5-20251101",
            "claude-sonnet-4",
            "claude-sonnet-4-6",
            "claude-sonnet-4-5-20250929",
            "claude-haiku-4",
            "claude-haiku-4-5-20251001",
        ],
        .perplexity: [
            "sonar-pro",
            "sonar-reasoning",
            "sonar-reasoning-pro",
            "sonar-deep-research",
        ],
        .xai: [
            "grok-4-1",
            "grok-4-1-fast",
            "grok-4-1-fast-non-reasoning",
            "grok-4-1-fast-reasoning",
            "grok-imagine-image",
            "grok-imagine-image-pro",
            "grok-2-image-1212",
            "grok-imagine-video",
        ],
        .deepseek: [
            "deepseek-chat",
            "deepseek-reasoner",
            "deepseek-v3.2-exp",
        ],
        .fireworks: [
            "fireworks/kimi-k2p5",
            "accounts/fireworks/models/kimi-k2p5",
            "fireworks/glm-4p7",
            "accounts/fireworks/models/glm-4p7",
            "fireworks/glm-5",
            "accounts/fireworks/models/glm-5",
            "fireworks/minimax-m2p5",
            "accounts/fireworks/models/minimax-m2p5",
        ],
        .cerebras: [
            "zai-glm-4.7",
        ],
        .gemini: [
            "gemini-3",
            "gemini-3-pro-preview",
            "gemini-3.1-pro-preview",
            "gemini-3-pro-image-preview",
            "gemini-3-flash-preview",
            "gemini-2.5-flash-image",
            "veo-2",
            "veo-3",
        ],
        .vertexai: [
            "gemini-3",
            "gemini-3-pro-preview",
            "gemini-3.1-pro-preview",
            "gemini-3-pro-image-preview",
            "gemini-3-flash-preview",
            "gemini-2.5",
            "gemini-2.5-pro",
            "gemini-2.5-flash-image",
            "veo-2",
            "veo-3",
        ],
    ]

    // Keep native PDF support checks aligned across UI and adapters.
    private static let nativePDFSupportedModelsByProvider: [ProviderType: Set<String>] = [
        .openai: [
            "gpt-5.2",
            "gpt-5.2-2025-12-11",
            "gpt-4o",
            "o3",
            "o4",
        ],
        .openaiWebSocket: [
            "gpt-5.2",
            "gpt-5.2-2025-12-11",
            "gpt-4o",
            "o3",
            "o4",
        ],
        .anthropic: [
            "claude-opus-4",
            "claude-opus-4-6",
            "claude-opus-4-5-20251101",
            "claude-sonnet-4",
            "claude-sonnet-4-6",
            "claude-sonnet-4-5-20250929",
            "claude-haiku-4",
            "claude-haiku-4-5-20251001",
        ],
        .perplexity: [
            "sonar",
            "sonar-pro",
            "sonar-reasoning",
            "sonar-reasoning-pro",
            "sonar-deep-research",
        ],
        .xai: [
            "grok-4-1",
            "grok-4-1-fast",
            "grok-4-1-fast-non-reasoning",
            "grok-4-1-fast-reasoning",
            "grok-4-1212",
        ],
        .gemini: [
            "gemini-3",
            "gemini-3-pro-preview",
            "gemini-3.1-pro-preview",
            "gemini-3-flash-preview",
        ],
        .vertexai: [
            "gemini-3",
            "gemini-3-pro-preview",
            "gemini-3.1-pro-preview",
            "gemini-3-flash-preview",
        ],
    ]

    static func isFullySupported(providerType: ProviderType, modelID: String) -> Bool {
        let lower = modelID.lowercased()
        guard let fullySupported = fullySupportedModelsByProvider[providerType] else {
            return false
        }
        return fullySupported.contains(lower)
    }

    static func supportsNativePDF(providerType: ProviderType, modelID: String) -> Bool {
        let lower = modelID.lowercased()
        guard let supported = nativePDFSupportedModelsByProvider[providerType] else {
            return false
        }
        return supported.contains(lower)
    }
}
