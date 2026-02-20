import Foundation

enum ModelRequestShape {
    case openAICompatible
    case openAIResponses
    case anthropic
    case gemini
}

enum ModelCapabilityRegistry {
    static func requestShape(for providerType: ProviderType?, modelID: String) -> ModelRequestShape {
        switch providerType {
        case .openai:
            return .openAIResponses
        case .codexAppServer:
            return .openAICompatible
        case .anthropic:
            return .anthropic
        case .gemini, .vertexai:
            return .gemini
        case .openaiCompatible, .openrouter, .groq, .mistral, .deepinfra:
            return .openAICompatible
        case .perplexity, .cohere, .xai, .deepseek, .fireworks, .cerebras, .none:
            return .openAICompatible
        }
    }

    static func supportsOpenAIStyleReasoningEffort(for providerType: ProviderType?, modelID: String) -> Bool {
        let shape = requestShape(for: providerType, modelID: modelID)
        return shape == .openAICompatible || shape == .openAIResponses
    }

    static func supportsOpenAIStyleExtremeEffort(for providerType: ProviderType?, modelID: String) -> Bool {
        guard supportsOpenAIStyleReasoningEffort(for: providerType, modelID: modelID) else {
            return false
        }
        return modelID.lowercased().contains("gpt-5.2")
    }

    static func supportsWebSearch(for providerType: ProviderType?, modelID: String) -> Bool {
        let lower = modelID.lowercased()

        switch providerType {
        case .openai:
            return supportsOpenAIWebSearch(lowerModelID: lower)
        case .codexAppServer:
            return false
        case .openrouter:
            return supportsOpenRouterWebSearch(lowerModelID: lower)
        case .anthropic:
            return isAnthropicModelID(lower)
        case .perplexity:
            return true
        case .xai:
            return !isLikelyMediaGenerationModelID(lower)
        case .gemini:
            return supportsGeminiGoogleSearch(lowerModelID: lower)
        case .vertexai:
            return supportsVertexGoogleSearch(lowerModelID: lower)
        case .openaiCompatible, .groq, .cohere, .mistral, .deepinfra, .deepseek, .fireworks, .cerebras, .none:
            return false
        }
    }

    static func defaultReasoningConfig(for providerType: ProviderType?, modelID: String) -> ModelReasoningConfig? {
        let lower = modelID.lowercased()
        let shape = requestShape(for: providerType, modelID: modelID)

        switch shape {
        case .anthropic:
            guard isReasoningModelID(lower, shape: shape) else { return nil }
            if AnthropicModelLimits.supportsAdaptiveThinking(for: lower) {
                return ModelReasoningConfig(type: .effort, defaultEffort: .high)
            }
            return ModelReasoningConfig(type: .budget, defaultBudget: 2048)

        case .gemini:
            guard isReasoningModelID(lower, shape: shape) else { return nil }
            if lower.contains("gemini-3-pro") {
                return ModelReasoningConfig(type: .effort, defaultEffort: .high)
            }
            return ModelReasoningConfig(type: .effort, defaultEffort: .medium)

        case .openAICompatible, .openAIResponses:
            guard isReasoningModelID(lower, shape: shape) else { return nil }
            if isGeminiModelID(lower) && !lower.contains("-image") && !lower.contains("imagen") {
                if lower.contains("gemini-3-pro") {
                    return ModelReasoningConfig(type: .effort, defaultEffort: .high)
                }
                return ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            }
            if isAnthropicModelID(lower) {
                if AnthropicModelLimits.supportsAdaptiveThinking(for: lower) {
                    return ModelReasoningConfig(type: .effort, defaultEffort: .high)
                }
                return ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            }
            return ModelReasoningConfig(type: .effort, defaultEffort: .medium)
        }
    }

    private static func isReasoningModelID(_ lowerModelID: String, shape: ModelRequestShape) -> Bool {
        switch shape {
        case .anthropic:
            return isAnthropicModelID(lowerModelID)
        case .gemini:
            return isGeminiModelID(lowerModelID)
                && !lowerModelID.contains("-image")
                && !lowerModelID.contains("imagen")
        case .openAICompatible, .openAIResponses:
            if isAnthropicModelID(lowerModelID) {
                return true
            }

            if isGeminiModelID(lowerModelID)
                && !lowerModelID.contains("-image")
                && !lowerModelID.contains("imagen") {
                return true
            }

            if lowerModelID.contains("gpt-5")
                || lowerModelID.hasPrefix("o1")
                || lowerModelID.hasPrefix("o3")
                || lowerModelID.hasPrefix("o4")
                || lowerModelID.contains("/o1")
                || lowerModelID.contains("/o3")
                || lowerModelID.contains("/o4") {
                return true
            }

            if lowerModelID.contains("deepseek-r1")
                || lowerModelID.contains("reasoning")
                || lowerModelID.contains("thinking") {
                return true
            }

            return false
        }
    }

    private static func isAnthropicModelID(_ lowerModelID: String) -> Bool {
        lowerModelID.contains("claude") || lowerModelID.contains("anthropic/")
    }

    private static func isGeminiModelID(_ lowerModelID: String) -> Bool {
        lowerModelID.contains("gemini")
    }

    private static func supportsOpenAIWebSearch(lowerModelID: String) -> Bool {
        if lowerModelID.hasPrefix("gpt-")
            || lowerModelID.contains("/gpt-")
            || lowerModelID.hasPrefix("o3")
            || lowerModelID.hasPrefix("o4")
            || lowerModelID.contains("/o3")
            || lowerModelID.contains("/o4") {
            return !isLikelyMediaGenerationModelID(lowerModelID)
        }

        return false
    }

    private static func supportsOpenRouterWebSearch(lowerModelID: String) -> Bool {
        // Explicitly search-oriented model IDs are generally web-search capable.
        if lowerModelID.contains("search")
            || lowerModelID.contains("sonar")
            || lowerModelID.contains(":online") {
            return true
        }

        if lowerModelID.hasPrefix("openai/") {
            let canonical = String(lowerModelID.dropFirst("openai/".count))
            return supportsOpenAIWebSearch(lowerModelID: canonical)
        }

        if lowerModelID.hasPrefix("anthropic/") {
            return true
        }

        if lowerModelID.hasPrefix("google/") {
            return supportsGeminiGoogleSearch(lowerModelID: lowerModelID)
        }

        if lowerModelID.hasPrefix("x-ai/") || lowerModelID.hasPrefix("xai/") || lowerModelID.hasPrefix("perplexity/") {
            return !isLikelyMediaGenerationModelID(lowerModelID)
        }

        return false
    }

    private static func supportsGeminiGoogleSearch(lowerModelID: String) -> Bool {
        // Gemini 2.5 Flash Image is the known model that rejects Google Search grounding.
        !lowerModelID.contains("gemini-2.5-flash-image")
    }

    private static func supportsVertexGoogleSearch(lowerModelID: String) -> Bool {
        // Vertex mirrors Gemini model-family search support behavior.
        !lowerModelID.contains("gemini-2.5-flash-image")
    }

    private static func isLikelyMediaGenerationModelID(_ lowerModelID: String) -> Bool {
        if lowerModelID.contains("-image")
            || lowerModelID.contains("imagen")
            || lowerModelID.contains("veo")
            || lowerModelID.contains("-video")
            || lowerModelID.contains("video-generation")
            || lowerModelID.contains("imagine-image")
            || lowerModelID.contains("imagine-video") {
            return true
        }
        return false
    }

    /// Models that support the `web_search_20260209` tool with dynamic filtering.
    static func supportsWebSearchDynamicFiltering(for providerType: ProviderType?, modelID: String) -> Bool {
        guard providerType == .anthropic else { return false }
        let lower = modelID.lowercased()
        return lower.contains("claude-opus-4-6") || lower.contains("claude-sonnet-4-6")
    }
}
