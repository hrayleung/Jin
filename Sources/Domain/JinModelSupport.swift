import Foundation

enum JinModelSupport {
    static let fullSupportSymbol = "✦"

    static func isFullySupported(providerType: ProviderType, modelID: String) -> Bool {
        let lower = modelID.lowercased()

        switch providerType {
        case .openai:
            return lower.hasPrefix("gpt-5")
                || lower.hasPrefix("o3")
                || lower.hasPrefix("o4")
                || lower.hasPrefix("gpt-4o")

        case .openaiCompatible, .openrouter, .groq, .cohere, .mistral, .deepinfra:
            // Generic/aggregated routing is provider-dependent; avoid over-promising.
            return false

        case .anthropic:
            return lower.contains("claude-opus-4")
                || lower.contains("claude-sonnet-4")
                || lower.contains("claude-haiku-4")

        case .perplexity:
            return lower.contains("sonar-pro")
                || lower.contains("sonar-reasoning")
                || lower.contains("sonar-deep-research")

        case .xai:
            return lower.contains("grok-4")
                || lower.contains("grok-5")
                || lower.contains("grok-6")
                || lower.contains("imagine-image")
                || lower.contains("grok-2-image")

        case .deepseek:
            return lower == "deepseek-chat"
                || lower == "deepseek-reasoner"
                || lower.contains("deepseek-v3.2-exp")

        case .fireworks:
            return lower == "fireworks/kimi-k2p5"
                || lower == "accounts/fireworks/models/kimi-k2p5"
                || lower == "fireworks/glm-4p7"
                || lower == "accounts/fireworks/models/glm-4p7"

        case .cerebras:
            return lower == "zai-glm-4.7"

        case .gemini:
            return lower.contains("gemini-3")
                || lower.contains("gemini-2.5-flash-image")

        case .vertexai:
            return lower.contains("gemini-3")
                || lower.contains("gemini-2.5")
        }
    }
}
