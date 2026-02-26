import Foundation

enum ModelRequestShape {
    case openAICompatible
    case openAIResponses
    case anthropic
    case gemini
}

enum ModelCapabilityRegistry {
    private static let openAIStyleExtremeEffortModelIDs: Set<String> = [
        "gpt-5.2",
        "gpt-5.2-2025-12-11",
        "gpt-5.2-codex",
        "gpt-5.2-pro",
        "gpt-5.3-codex",
        "gpt-5.3-codex-spark",
    ]

    /// Gemini 3 Flash supports MINIMAL/LOW/MEDIUM/HIGH.
    private static let gemini3FlashEffortModelIDs: Set<String> = [
        "gemini-3-flash-preview",
    ]

    /// Gemini 3.1 Pro supports LOW/MEDIUM/HIGH.
    private static let gemini31ProEffortModelIDs: Set<String> = [
        "gemini-3.1-pro-preview",
    ]

    /// Gemini 3 Pro family supports LOW/HIGH.
    private static let gemini3ProLowHighEffortModelIDs: Set<String> = [
        "gemini-3",
        "gemini-3-pro",
        "gemini-3-pro-preview",
        "gemini-3-pro-image-preview",
    ]

    /// Models documented by Google as supporting grounding with Google Search in Gemini API.
    private static let geminiGoogleSearchSupportedModelIDs: Set<String> = [
        "gemini-3.1-pro-preview",
        "gemini-3-pro-preview",
        "gemini-3-flash-preview",
        "gemini-3-pro-image-preview",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.0-flash",
        "gemini-2.0-flash-001",
    ]

    /// Models documented by Google as supporting grounding with Google Search in Vertex AI.
    private static let vertexGoogleSearchSupportedModelIDs: Set<String> = [
        "gemini-3.1-pro-preview",
        "gemini-3-pro-preview",
        "gemini-3-flash-preview",
        "gemini-3-pro-image-preview",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.5-flash-preview",
        "gemini-2.5-flash-lite-preview",
        "gemini-2.0-flash",
    ]

    /// Fallback used by proxy providers (for example OpenRouter `google/*` model IDs).
    private static let proxiedGoogleSearchSupportedModelIDs: Set<String> =
        geminiGoogleSearchSupportedModelIDs.union(vertexGoogleSearchSupportedModelIDs)

    private static let reasoningEffortRank: [ReasoningEffort: Int] = [
        .none: 0,
        .minimal: 1,
        .low: 2,
        .medium: 3,
        .high: 4,
        .xhigh: 5,
    ]

    static func requestShape(for providerType: ProviderType?, modelID: String) -> ModelRequestShape {
        switch providerType {
        case .openai, .openaiWebSocket:
            return .openAIResponses
        case .anthropic:
            return .anthropic
        case .gemini, .vertexai:
            return .gemini
        case .codexAppServer, .openaiCompatible, .cloudflareAIGateway, .openrouter,
             .groq, .cohere, .mistral, .deepinfra, .xai, .deepseek,
             .fireworks, .cerebras, .perplexity, .none:
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
        let canonicalLowerModelID = canonicalOpenAIModelID(lowerModelID: modelID.lowercased())
        return openAIStyleExtremeEffortModelIDs.contains(canonicalLowerModelID)
    }

    static func supportedReasoningEfforts(for providerType: ProviderType?, modelID: String) -> [ReasoningEffort] {
        let lowerModelID = modelID.lowercased()

        switch providerType {
        case .vertexai:
            return supportedGeminiThinkingEfforts(lowerModelID: lowerModelID)
        case .perplexity:
            return [.minimal, .low, .medium, .high]
        case .gemini:
            return supportedGeminiThinkingEfforts(lowerModelID: lowerModelID)
        default:
            break
        }

        if supportsOpenAIStyleReasoningEffort(for: providerType, modelID: modelID) {
            var efforts: [ReasoningEffort] = [.low, .medium, .high]
            if supportsOpenAIStyleExtremeEffort(for: providerType, modelID: modelID) {
                efforts.append(.xhigh)
            }
            return efforts
        }

        return [.low, .medium, .high]
    }

    private static func supportedGeminiThinkingEfforts(lowerModelID: String) -> [ReasoningEffort] {
        if gemini3FlashEffortModelIDs.contains(lowerModelID) {
            return [.minimal, .low, .medium, .high]
        }
        if gemini31ProEffortModelIDs.contains(lowerModelID) {
            return [.low, .medium, .high]
        }
        if gemini3ProLowHighEffortModelIDs.contains(lowerModelID) {
            return [.low, .high]
        }
        return [.minimal, .low, .medium, .high]
    }

    static func normalizedReasoningEffort(
        _ effort: ReasoningEffort,
        for providerType: ProviderType?,
        modelID: String
    ) -> ReasoningEffort {
        guard effort != .none else { return .none }

        let supportedEfforts = supportedReasoningEfforts(for: providerType, modelID: modelID)
        guard !supportedEfforts.isEmpty else { return effort }
        if supportedEfforts.contains(effort) {
            return effort
        }

        guard let targetRank = reasoningEffortRank[effort] else {
            return supportedEfforts.last ?? effort
        }

        var best: (effort: ReasoningEffort, distance: Int, rank: Int)?
        for candidate in supportedEfforts {
            guard let candidateRank = reasoningEffortRank[candidate] else { continue }
            let distance = abs(candidateRank - targetRank)

            if let currentBest = best {
                if distance < currentBest.distance
                    || (distance == currentBest.distance && candidateRank > currentBest.rank) {
                    best = (candidate, distance, candidateRank)
                }
            } else {
                best = (candidate, distance, candidateRank)
            }
        }

        return best?.effort ?? supportedEfforts.last ?? effort
    }

    static func supportsWebSearch(for providerType: ProviderType?, modelID: String) -> Bool {
        let lower = modelID.lowercased()

        switch providerType {
        case .openai, .openaiWebSocket:
            return supportsOpenAIWebSearch(lowerModelID: lower)
        case .openrouter:
            return supportsOpenRouterWebSearch(lowerModelID: lower)
        case .anthropic:
            return isAnthropicModelID(lower)
        case .perplexity:
            return true
        case .xai:
            return !isLikelyMediaGenerationModelID(lower)
        case .gemini:
            return supportsGoogleSearch(lowerModelID: lower, providerType: .gemini)
        case .vertexai:
            return supportsGoogleSearch(lowerModelID: lower, providerType: .vertexai)
        case .codexAppServer, .openaiCompatible, .cloudflareAIGateway, .groq,
             .cohere, .mistral, .deepinfra, .deepseek, .fireworks, .cerebras, .none:
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
            return supportsGoogleSearch(lowerModelID: lowerModelID, providerType: .openrouter)
        }

        if lowerModelID.hasPrefix("x-ai/") || lowerModelID.hasPrefix("xai/") || lowerModelID.hasPrefix("perplexity/") {
            return !isLikelyMediaGenerationModelID(lowerModelID)
        }

        return false
    }

    private static func supportsGoogleSearch(lowerModelID: String, providerType: ProviderType?) -> Bool {
        let canonical = canonicalGoogleModelID(lowerModelID: lowerModelID)

        switch providerType {
        case .gemini:
            return geminiGoogleSearchSupportedModelIDs.contains(canonical)
        case .vertexai:
            return vertexGoogleSearchSupportedModelIDs.contains(canonical)
        default:
            return proxiedGoogleSearchSupportedModelIDs.contains(canonical)
        }
    }

    private static func canonicalGoogleModelID(lowerModelID: String) -> String {
        if lowerModelID.hasPrefix("google/") {
            return String(lowerModelID.dropFirst("google/".count))
        }
        if lowerModelID.hasPrefix("google-ai-studio/") {
            return String(lowerModelID.dropFirst("google-ai-studio/".count))
        }
        if lowerModelID.hasPrefix("google-vertex-ai/google/") {
            return String(lowerModelID.dropFirst("google-vertex-ai/google/".count))
        }
        return lowerModelID
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

    private static func canonicalOpenAIModelID(lowerModelID: String) -> String {
        if lowerModelID.hasPrefix("openai/") {
            return String(lowerModelID.dropFirst("openai/".count))
        }
        return lowerModelID
    }

    /// Models that support the `web_search_20260209` tool with dynamic filtering.
    static func supportsWebSearchDynamicFiltering(for providerType: ProviderType?, modelID: String) -> Bool {
        guard providerType == .anthropic else { return false }
        let lower = modelID.lowercased()
        return lower.contains("claude-opus-4-6") || lower.contains("claude-sonnet-4-6")
    }
}
