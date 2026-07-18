import Foundation

enum ModelRequestShape {
    case openAICompatible
    case openAIResponses
    case anthropic
    case gemini
}

private extension ModelRequestShape {
    var supportsOpenAIStyleReasoningEffort: Bool {
        switch self {
        case .openAICompatible, .openAIResponses:
            return true
        case .anthropic, .gemini:
            return false
        }
    }
}

enum ModelCapabilityRegistry {
    /// Default-effort exceptions still live here until defaultEffort is fully on catalog records.
    private static let openAINoneDefaultReasoningModelIDs: Set<String> = [
        "gpt-5.2",
        "gpt-5.2-2025-12-11",
        "gpt-5.4",
        "gpt-5.4-2026-03-05",
        "gpt-5.4-image-2",
        "gpt-5.4-mini",
        "gpt-5.4-mini-2026-03-17",
        "gpt-5.4-nano",
        "gpt-5.4-nano-2026-03-17",
    ]

    private static let openAIHighDefaultReasoningModelIDs: Set<String> = [
        "gpt-5.5-pro",
        "gpt-5.5-pro-2026-04-23",
        "gpt-5.4-pro",
        "gpt-5.4-pro-2026-03-05",
    ]

    // OpenAI wire-policy sets (extreme/max effort, pro mode, verbosity, code interpreter)
    // moved to `ModelCatalog.openAIDeclaredFeaturesByID` (PR1b).

    /// Gemini 3 Flash / 3.5 Flash supports MINIMAL/LOW/MEDIUM/HIGH.
    private static let gemini3FlashEffortModelIDs: Set<String> = [
        "gemini-3-flash-preview",
        "gemini-3.5-flash",
    ]

    /// Gemini 3.1 Flash Image supports MINIMAL/HIGH.
    private static let gemini31FlashImageEffortModelIDs: Set<String> = [
        "gemini-3.1-flash-image",
        "gemini-3.1-flash-image-preview",
        "gemini-3.1-flash-lite-image",
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
        "gemini-3-pro-image",
        "gemini-3-pro-image-preview",
    ]

    // Gemini/Vertex Search, Maps, and code-execution allowlists moved to
    // `ModelCatalog.geminiDeclaredFeaturesByID` / `vertexDeclaredFeaturesByID` (PR1c).
    // OpenAI / Anthropic feature tables: PR1b.

    /// OpenRouter `plugins: [{id: "web"}]` support stays conservative and does not
    /// inherit Gemini-only runtime trials automatically. Keys are bare Google IDs
    /// (after stripping `google/`).
    private static let openRouterGoogleSearchSupportedModelIDs: Set<String> = [
        "gemini-3.1-pro-preview",
        "gemini-3-pro-preview",
        "gemini-3-flash-preview",
        "gemini-3-pro-image",
        "gemini-3-pro-image-preview",
        "gemini-3.1-flash-image",
        "gemini-3.1-flash-image-preview",
        "gemini-3.1-flash-lite-preview",
        "gemini-3.1-flash-lite",
        "gemini-3.5-flash",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.5-flash-preview",
        "gemini-2.5-flash-lite-preview",
        "gemini-2.0-flash",
        "gemini-2.0-flash-001",
    ]

    /// Fallback used by proxy providers other than OpenRouter's explicit list.
    /// Union of AI Studio + Vertex catalog feature IDs that enable webSearch.
    private static let proxiedGoogleSearchSupportedModelIDs: Set<String> = {
        let gemini = ModelCatalog.geminiDeclaredFeaturesByID
            .filter { $0.value.webSearch == true }
            .map(\.key)
        let vertex = ModelCatalog.vertexDeclaredFeaturesByID
            .filter { $0.value.webSearch == true }
            .map(\.key)
        return Set(gemini).union(vertex)
    }()

    private static let reasoningEffortRank: [ReasoningEffort: Int] = [
        .none: 0,
        .minimal: 1,
        .low: 2,
        .medium: 3,
        .high: 4,
        .xhigh: 5,
        .max: 6,
    ]

    private static let defaultReasoningEfforts: [ReasoningEffort] = [.low, .medium, .high]
    private static let defaultGeminiReasoningEfforts: [ReasoningEffort] = [.minimal, .low, .medium, .high]
    private static let deepSeekV4ReasoningEffortModelIDs: Set<String> = [
        "deepseek-v4-flash",
        "deepseek-v4-pro",
    ]
    /// OpenCode Go GLM models whose `reasoning_effort` is restricted to `high`/`max`
    /// (Z.AI documents only these two for GLM-5.2; `max` is the native default).
    private static let opencodeGoGLMHighMaxReasoningEffortModelIDs: Set<String> = [
        "glm-5.2",
    ]
    private static let openRouterDeepSeekV4ReasoningEffortModelIDs: Set<String> = [
        "deepseek/deepseek-v4-flash",
        "deepseek/deepseek-v4-pro",
    ]
    /// Sakana Fugu Ultra only accepts the high/xhigh/max band (OpenRouter
    /// supported_efforts, verified 2026-07-11).
    private static let openRouterHighBandEffortModelIDs: Set<String> = [
        "sakana/fugu-ultra",
    ]
    /// Tencent Hy3 accepts only high/low ("none" is expressed by disabling
    /// reasoning) — OpenRouter supported_efforts, verified 2026-07-11.
    private static let openRouterLowHighEffortModelIDs: Set<String> = [
        "tencent/hy3",
        "tencent/hy3:free",
    ]
    /// Gemini 3.1 Flash Lite Image on OpenRouter accepts only minimal/high
    /// (matches the native gemini31FlashImageEffortModelIDs band).
    private static let openRouterMinimalHighEffortModelIDs: Set<String> = [
        "google/gemini-3.1-flash-lite-image",
    ]
    /// Thinking Machines Inkling accepts the full none/minimal/low/medium/high/max
    /// band with no xhigh (OpenRouter supported_efforts, verified 2026-07-18).
    private static let openRouterMinimalMaxEffortModelIDs: Set<String> = [
        "thinkingmachines/inkling",
    ]
    private static let togetherDeepSeekV4ReasoningEffortModelIDs: Set<String> = [
        "deepseek-ai/deepseek-v4-pro",
    ]
    private static let deepInfraDeepSeekV4ReasoningEffortModelIDs: Set<String> = [
        "deepseek-ai/deepseek-v4-flash",
        "deepseek-ai/deepseek-v4-pro",
    ]
    private static let xAIMultiAgentReasoningEffortModelIDs: Set<String> = [
        "grok-4.20-multi-agent",
        "grok-4.20-multi-agent-0309",
        "x-ai/grok-4.20-multi-agent",
        "xai/grok-4.20-multi-agent",
    ]
    private static let xAIAlwaysOnStandardEffortModelIDs: Set<String> = [
        "grok-4.5",
        "x-ai/grok-4.5",
        "xai/grok-4.5",
    ]
    private static let xAIStandardEffortWithNoneModelIDs: Set<String> = [
        "grok-4.3",
        "x-ai/grok-4.3",
        "xai/grok-4.3",
    ]

    /// Whether effort labels should describe multi-agent agent count rather than thinking depth.
    static func usesXAIMultiAgentEffortLabels(for providerType: ProviderType?, modelID: String) -> Bool {
        switch providerType {
        case .xai, .openrouter, .vercelAIGateway:
            return xAIMultiAgentReasoningEffortModelIDs.contains(modelID.lowercased())
        default:
            return false
        }
    }
    private static let mistralHighOnlyReasoningEffortModelIDs: Set<String> = [
        "mistral-medium-3.5",
        "mistral-small-4-0-26-03",
        "magistral-medium-1-2-25-09",
    ]
    private static let searchKeywords = ["search", "sonar", ":online"]
    private static let reasoningKeywords = ["deepseek-r1", "reasoning", "thinking"]
    private static let mediaGenerationKeywords = [
        "-image",
        "imagen",
        "veo",
        "-video",
        "video-generation",
        "imagine-image",
        "imagine-video",
    ]

    static func requestShape(for providerType: ProviderType?, modelID _: String) -> ModelRequestShape {
        switch providerType {
        case .openai, .openaiWebSocket:
            return .openAIResponses
        case .anthropic, .claudeManagedAgents, .mimoTokenPlanAnthropic, .kimiForCoding:
            return .anthropic
        case .gemini, .vertexai:
            return .gemini
        case .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter,
             .groq, .cohere, .mistral, .deepinfra, .together, .xai, .deepseek,
             .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .mimoTokenPlanOpenAI, .fireworks, .cerebras, .sambanova, .databricks, .perplexity, .morphllm, .opencodeGo,
             .zyphra, .meta, .none:
            return .openAICompatible
        }
    }

    static func supportsOpenAIStyleReasoningEffort(for providerType: ProviderType?, modelID: String) -> Bool {
        requestShape(for: providerType, modelID: modelID).supportsOpenAIStyleReasoningEffort
    }

    static func supportsOpenAIStyleExtremeEffort(for providerType: ProviderType?, modelID: String) -> Bool {
        guard supportsOpenAIStyleReasoningEffort(for: providerType, modelID: modelID) else {
            return false
        }
        return openAIStyleFeatureFlag(for: providerType, modelID: modelID, \.openAIStyleExtremeEffort) ?? false
    }

    static func supportsOpenAIStyleMaxEffort(for providerType: ProviderType?, modelID: String) -> Bool {
        guard supportsOpenAIStyleReasoningEffort(for: providerType, modelID: modelID) else {
            return false
        }

        let lowerModelID = modelID.lowercased()
        if providerType == .openrouter,
           openRouterHighBandEffortModelIDs.contains(lowerModelID)
            || openRouterMinimalMaxEffortModelIDs.contains(lowerModelID) {
            return true
        }

        return openAIStyleFeatureFlag(for: providerType, modelID: modelID, \.openAIStyleMaxEffort) ?? false
    }

    /// GPT-5.6 Responses API `reasoning.mode = "pro"` (not a separate model slug on OpenAI).
    static func supportsOpenAIStyleProMode(for providerType: ProviderType?, modelID: String) -> Bool {
        guard supportsOpenAIStyleReasoningEffort(for: providerType, modelID: modelID) else {
            return false
        }
        return openAIStyleFeatureFlag(for: providerType, modelID: modelID, \.openAIStyleProMode) ?? false
    }

    /// Responses API `reasoning.context` support (exact IDs).
    static func supportsOpenAIStyleReasoningContext(for providerType: ProviderType?, modelID: String) -> Bool {
        guard supportsOpenAIStyleReasoningEffort(for: providerType, modelID: modelID) else {
            return false
        }
        return openAIStyleFeatureFlag(for: providerType, modelID: modelID, \.openAIStyleReasoningContext) ?? false
    }

    /// Responses API `text.verbosity` support (exact IDs).
    /// Limited to native OpenAI / OpenAI WebSocket providers — gateways may not forward the field.
    static func supportsOpenAIStyleVerbosity(for providerType: ProviderType?, modelID: String) -> Bool {
        switch providerType {
        case .openai, .openaiWebSocket, .none:
            break
        default:
            return false
        }
        return openAIStyleFeatureFlag(for: providerType, modelID: modelID, \.openAIStyleVerbosity) ?? false
    }

    static func supportedReasoningEfforts(for providerType: ProviderType?, modelID: String) -> [ReasoningEffort] {
        let lowerModelID = modelID.lowercased()

        switch providerType {
        case .vertexai, .gemini:
            return supportedGeminiThinkingEfforts(lowerModelID: lowerModelID)
        case .perplexity:
            return defaultGeminiReasoningEfforts
        case .anthropic, .claudeManagedAgents:
            return supportedAnthropicEfforts(lowerModelID: lowerModelID)
        case .deepseek where deepSeekV4ReasoningEffortModelIDs.contains(lowerModelID):
            return [.high, .max]
        case .openrouter where openRouterDeepSeekV4ReasoningEffortModelIDs.contains(lowerModelID):
            return [.high, .xhigh]
        case .openrouter where xAIMultiAgentReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .medium, .high, .xhigh]
        case .openrouter where xAIAlwaysOnStandardEffortModelIDs.contains(lowerModelID):
            return [.low, .medium, .high]
        case .openrouter where xAIStandardEffortWithNoneModelIDs.contains(lowerModelID):
            return [.none, .low, .medium, .high]
        case .openrouter where openRouterHighBandEffortModelIDs.contains(lowerModelID):
            return [.high, .xhigh, .max]
        case .openrouter where openRouterMinimalHighEffortModelIDs.contains(lowerModelID):
            return [.minimal, .high]
        case .openrouter where openRouterMinimalMaxEffortModelIDs.contains(lowerModelID):
            return [.none, .minimal, .low, .medium, .high, .max]
        case .openrouter where openRouterLowHighEffortModelIDs.contains(lowerModelID):
            return [.low, .high]
        case .together where togetherDeepSeekV4ReasoningEffortModelIDs.contains(lowerModelID):
            return [.high]
        case .deepinfra where deepInfraDeepSeekV4ReasoningEffortModelIDs.contains(lowerModelID):
            return [.high]
        case .xai where xAIMultiAgentReasoningEffortModelIDs.contains(lowerModelID):
            // Multi-agent: low/medium → 4 agents, high/xhigh → 16 agents.
            return [.low, .medium, .high, .xhigh]
        case .xai where xAIAlwaysOnStandardEffortModelIDs.contains(lowerModelID):
            return [.low, .medium, .high]
        case .xai where xAIStandardEffortWithNoneModelIDs.contains(lowerModelID):
            return [.none, .low, .medium, .high]
        case .vercelAIGateway where xAIMultiAgentReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .medium, .high, .xhigh]
        case .vercelAIGateway where xAIAlwaysOnStandardEffortModelIDs.contains(lowerModelID):
            return [.low, .medium, .high]
        case .vercelAIGateway where xAIStandardEffortWithNoneModelIDs.contains(lowerModelID):
            return [.none, .low, .medium, .high]
        case .mistral where mistralHighOnlyReasoningEffortModelIDs.contains(lowerModelID):
            return [.high]
        case .fireworks where fireworksDeepSeekV4ProModelIDs.contains(lowerModelID):
            return [.high, .max]
        case .opencodeGo where deepSeekV4ReasoningEffortModelIDs.contains(lowerModelID):
            return [.high, .max]
        case .opencodeGo where opencodeGoGLMHighMaxReasoningEffortModelIDs.contains(lowerModelID):
            return [.high, .max]
        case .meta:
            // Muse Spark accepts minimal..xhigh ("none" returns HTTP 400 and is handled
            // by omitting the field; "max" is not accepted).
            return [.minimal, .low, .medium, .high, .xhigh]
        default:
            break
        }

        guard supportsOpenAIStyleReasoningEffort(for: providerType, modelID: modelID) else {
            return defaultReasoningEfforts
        }

        var efforts = defaultReasoningEfforts
        if supportsOpenAIStyleExtremeEffort(for: providerType, modelID: modelID) {
            efforts.append(.xhigh)
        }
        if supportsOpenAIStyleMaxEffort(for: providerType, modelID: modelID) {
            efforts.append(.max)
        }
        return efforts
    }

    private static func supportedAnthropicEfforts(lowerModelID: String) -> [ReasoningEffort] {
        if AnthropicModelLimits.supportsXHighEffort(for: lowerModelID) {
            return [.low, .medium, .high, .xhigh, .max]
        }
        if AnthropicModelLimits.supportsMaxEffort(for: lowerModelID) {
            return [.low, .medium, .high, .max]
        }
        return defaultReasoningEfforts
    }

    private static func supportedGeminiThinkingEfforts(lowerModelID: String) -> [ReasoningEffort] {
        if gemini31FlashImageEffortModelIDs.contains(lowerModelID) {
            return [.minimal, .high]
        }
        if gemini3FlashEffortModelIDs.contains(lowerModelID) {
            return defaultGeminiReasoningEfforts
        }
        if gemini31ProEffortModelIDs.contains(lowerModelID) {
            return defaultReasoningEfforts
        }
        if gemini3ProLowHighEffortModelIDs.contains(lowerModelID) {
            return [.low, .high]
        }
        return defaultGeminiReasoningEfforts
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

        return closestSupportedEffort(to: effort, in: supportedEfforts)
    }

    private static func closestSupportedEffort(
        to effort: ReasoningEffort,
        in supportedEfforts: [ReasoningEffort]
    ) -> ReasoningEffort {
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
                continue
            }

            best = (candidate, distance, candidateRank)
        }

        return best?.effort ?? supportedEfforts.last ?? effort
    }

    static func supportsWebSearch(for providerType: ProviderType?, modelID: String) -> Bool {
        // Catalog features win when explicitly declared (Phase 1 dual-read).
        if let declared = resolvedCatalogFeatures(for: providerType, modelID: modelID)?.webSearch {
            return declared
        }

        let lowerModelID = modelID.lowercased()

        switch providerType {
        case .openai, .openaiWebSocket:
            // Uncatalogued OpenAI IDs keep the conservative gpt-/o3/o4 heuristic.
            return supportsOpenAIWebSearch(lowerModelID: lowerModelID)
        case .openrouter:
            return supportsOpenRouterWebSearch(lowerModelID: lowerModelID)
        case .anthropic:
            // Uncatalogued Claude IDs keep the conservative family heuristic.
            return isAnthropicModelID(lowerModelID)
        case .claudeManagedAgents:
            return false
        case .perplexity:
            return true
        case .xai:
            return !isLikelyMediaGenerationModelID(lowerModelID)
        case .gemini:
            return supportsGoogleSearch(lowerModelID: lowerModelID, providerType: .gemini)
        case .vertexai:
            return supportsGoogleSearch(lowerModelID: lowerModelID, providerType: .vertexai)
        case .opencodeGo:
            return MiMoModelIDs.tokenPlanExactModelIDs.contains(lowerModelID)
        case .mimoTokenPlanOpenAI:
            return MiMoModelIDs.tokenPlanExactModelIDs.contains(lowerModelID)
        case .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .groq,
             .cohere, .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan,
             .mimoTokenPlanAnthropic, .fireworks, .cerebras, .sambanova, .databricks, .morphllm, .zyphra, .meta, .kimiForCoding, .none:
            return false
        }
    }

    static func defaultReasoningConfig(for providerType: ProviderType?, modelID: String) -> ModelReasoningConfig? {
        let lowerModelID = modelID.lowercased()
        let shape = requestShape(for: providerType, modelID: modelID)

        if providerType == .mistral,
           mistralHighOnlyReasoningEffortModelIDs.contains(lowerModelID) {
            return ModelReasoningConfig(type: .effort, defaultEffort: .high)
        }

        guard isReasoningModelID(lowerModelID, shape: shape) else {
            return nil
        }

        switch shape {
        case .anthropic:
            return defaultAnthropicReasoningConfig(lowerModelID: lowerModelID, shape: shape)
        case .gemini:
            return defaultGeminiReasoningConfig(lowerModelID: lowerModelID)
        case .openAICompatible, .openAIResponses:
            return defaultOpenAIFamilyReasoningConfig(lowerModelID: lowerModelID)
        }
    }

    private static func defaultAnthropicReasoningConfig(
        lowerModelID: String,
        shape: ModelRequestShape
    ) -> ModelReasoningConfig {
        if shape == .anthropic {
            if AnthropicModelLimits.supportsAdaptiveThinking(for: lowerModelID) {
                return ModelReasoningConfig(type: .effort, defaultEffort: .high)
            }
            return ModelReasoningConfig(type: .budget, defaultBudget: 2048)
        }

        if AnthropicModelLimits.supportsAdaptiveThinking(for: lowerModelID) {
            return ModelReasoningConfig(type: .effort, defaultEffort: .high)
        }
        return ModelReasoningConfig(type: .effort, defaultEffort: .medium)
    }

    private static func defaultGeminiReasoningConfig(lowerModelID: String) -> ModelReasoningConfig {
        if lowerModelID.contains("gemini-3-pro") {
            return ModelReasoningConfig(type: .effort, defaultEffort: .high)
        }
        return ModelReasoningConfig(type: .effort, defaultEffort: .medium)
    }

    private static func defaultOpenAIFamilyReasoningConfig(lowerModelID: String) -> ModelReasoningConfig {
        if deepSeekV4ReasoningEffortModelIDs.contains(lowerModelID) {
            return ModelReasoningConfig(type: .effort, defaultEffort: .high)
        }
        if isGeminiReasoningModelID(lowerModelID) {
            return defaultGeminiReasoningConfig(lowerModelID: lowerModelID)
        }
        if isAnthropicModelID(lowerModelID) {
            return defaultAnthropicReasoningConfig(lowerModelID: lowerModelID, shape: .openAICompatible)
        }

        let canonicalLowerModelID = canonicalOpenAIModelID(lowerModelID: lowerModelID)
        if openAINoneDefaultReasoningModelIDs.contains(canonicalLowerModelID) {
            return ModelReasoningConfig(type: .effort, defaultEffort: ReasoningEffort.none)
        }
        if openAIHighDefaultReasoningModelIDs.contains(canonicalLowerModelID) {
            return ModelReasoningConfig(type: .effort, defaultEffort: .high)
        }

        return ModelReasoningConfig(type: .effort, defaultEffort: .medium)
    }

    private static func isReasoningModelID(_ lowerModelID: String, shape: ModelRequestShape) -> Bool {
        switch shape {
        case .anthropic:
            return isAnthropicModelID(lowerModelID)
        case .gemini:
            return isGeminiReasoningModelID(lowerModelID)
        case .openAICompatible, .openAIResponses:
            return isAnthropicModelID(lowerModelID)
                || isGeminiReasoningModelID(lowerModelID)
                || isOpenAIReasoningModelID(lowerModelID)
                || containsAnyFragment(in: lowerModelID, fragments: reasoningKeywords)
        }
    }

    private static func isAnthropicModelID(_ lowerModelID: String) -> Bool {
        lowerModelID.contains("claude") || lowerModelID.contains("anthropic/")
    }

    private static func isGeminiModelID(_ lowerModelID: String) -> Bool {
        lowerModelID.contains("gemini")
    }

    private static func isGeminiReasoningModelID(_ lowerModelID: String) -> Bool {
        isGeminiModelID(lowerModelID)
            && !lowerModelID.contains("-image")
            && !lowerModelID.contains("imagen")
    }

    private static func isOpenAIReasoningModelID(_ lowerModelID: String) -> Bool {
        lowerModelID.contains("gpt-5") || hasPrefixOrScopedPrefix(lowerModelID, prefixes: ["o1", "o3", "o4"])
    }

    private static func supportsOpenAIWebSearch(lowerModelID: String) -> Bool {
        guard lowerModelID.hasPrefix("gpt-")
            || lowerModelID.contains("/gpt-")
            || hasPrefixOrScopedPrefix(lowerModelID, prefixes: ["o3", "o4"]) else {
            return false
        }

        return !isLikelyMediaGenerationModelID(lowerModelID)
    }

    private static func supportsOpenRouterWebSearch(lowerModelID rawModelID: String) -> Bool {
        // OpenRouter "latest"-family aliases are prefixed with `~` (e.g. `~openai/gpt-latest`).
        // Strip it so they share the same web-search policy as their canonical twins.
        let lowerModelID = rawModelID.hasPrefix("~") ? String(rawModelID.dropFirst()) : rawModelID

        if containsAnyFragment(in: lowerModelID, fragments: searchKeywords) {
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
            return ModelCatalog.features(for: canonical, provider: .gemini)?.webSearch ?? false
        case .vertexai:
            return ModelCatalog.features(for: canonical, provider: .vertexai)?.webSearch ?? false
        case .openrouter:
            return openRouterGoogleSearchSupportedModelIDs.contains(canonical)
        default:
            return proxiedGoogleSearchSupportedModelIDs.contains(canonical)
        }
    }

    private static func supportsGoogleCodeExecution(lowerModelID: String, providerType: ProviderType?) -> Bool {
        let canonical = canonicalGoogleModelID(lowerModelID: lowerModelID)
        switch providerType {
        case .gemini:
            return ModelCatalog.features(for: canonical, provider: .gemini)?.codeExecution ?? false
        case .vertexai:
            return ModelCatalog.features(for: canonical, provider: .vertexai)?.codeExecution ?? false
        default:
            return false
        }
    }

    private static func canonicalGoogleModelID(lowerModelID: String) -> String {
        ModelCatalog.canonicalGoogleModelID(lowerModelID)
    }

    private static func isLikelyMediaGenerationModelID(_ lowerModelID: String) -> Bool {
        containsAnyFragment(in: lowerModelID, fragments: mediaGenerationKeywords)
    }

    private static func canonicalOpenAIModelID(lowerModelID: String) -> String {
        if lowerModelID.hasPrefix("openai/") {
            return String(lowerModelID.dropFirst("openai/".count))
        }
        return lowerModelID
    }

    private static func containsAnyFragment(in value: String, fragments: [String]) -> Bool {
        fragments.contains(where: value.contains)
    }

    private static func hasPrefixOrScopedPrefix(_ value: String, prefixes: [String]) -> Bool {
        prefixes.contains { prefix in
            value.hasPrefix(prefix) || value.contains("/\(prefix)")
        }
    }

    /// Whether the provider/model supports native code execution (OpenAI Code Interpreter, Anthropic Code Execution).
    static func supportsCodeExecution(for providerType: ProviderType?, modelID: String) -> Bool {
        // OpenAI / Anthropic: catalog feature tables are the SSoT (explicit true/false).
        // Explicit `codeExecution` on features wins over the capability bit so alias
        // records (e.g. claude-opus-4) can deny execution while still advertising tools.
        if let features = resolvedCatalogFeatures(for: providerType, modelID: modelID),
           let declared = features.codeExecution {
            return declared
        }

        let lowerModelID = modelID.lowercased()

        switch providerType {
        case .openai, .openaiWebSocket:
            // No catalog/feature row → not supported (exact-ID policy).
            return false
        case .anthropic:
            return false
        case .claudeManagedAgents:
            return false
        case .xai:
            return ModelCatalog.entry(for: modelID, provider: .xai)?.capabilities.contains(.codeExecution) ?? false
        case .gemini:
            // Gemini API `tools.code_execution`
            return supportsGoogleCodeExecution(lowerModelID: lowerModelID, providerType: .gemini)
        case .vertexai:
            // Vertex AI `tools.codeExecution`
            return supportsGoogleCodeExecution(lowerModelID: lowerModelID, providerType: .vertexai)
        case .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together,
             .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks, .cerebras, .sambanova, .databricks, .morphllm,
             .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI, .opencodeGo, .zyphra, .meta, .kimiForCoding, .none:
            return false
        }
    }

    /// Whether the provider/model supports grounding with Google Maps.
    static func supportsGoogleMaps(for providerType: ProviderType?, modelID: String) -> Bool {
        if let declared = resolvedCatalogFeatures(for: providerType, modelID: modelID)?.googleMaps {
            return declared
        }

        switch providerType {
        case .gemini, .vertexai:
            // No catalog/feature row → not supported (exact-ID policy).
            return false
        case .openai, .openaiWebSocket, .anthropic, .claudeManagedAgents, .xai, .githubCopilot,
             .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .perplexity,
             .groq, .cohere, .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan,
             .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI, .fireworks, .cerebras, .sambanova, .databricks, .morphllm, .opencodeGo,
             .zyphra, .meta, .kimiForCoding, .none:
            return false
        }
    }

    // MARK: - Catalog dual-read helpers

    private static func catalogEntry(
        for providerType: ProviderType?,
        modelID: String
    ) -> ModelCatalogEntry? {
        guard let providerType else { return nil }
        return ModelCatalog.entry(for: modelID, provider: providerType)
    }

    /// Features from `ModelCatalog.features` (record + declared tables), including
    /// OpenAI/Anthropic table-only rows that have no full catalog `Record`.
    private static func resolvedCatalogFeatures(
        for providerType: ProviderType?,
        modelID: String
    ) -> ModelFeatures? {
        guard let providerType else { return nil }
        return ModelCatalog.features(for: modelID, provider: providerType)
    }

    /// OpenAI-style wire flags: native providers use full feature resolution;
    /// compound IDs (`openai/gpt-5.4` on gateways) resolve against the OpenAI table.
    private static func openAIStyleFeatureFlag(
        for providerType: ProviderType?,
        modelID: String,
        _ keyPath: KeyPath<ModelFeatures, Bool?>
    ) -> Bool? {
        if let providerType, providerType == .openai || providerType == .openaiWebSocket {
            if let value = ModelCatalog.features(for: modelID, provider: providerType)?[keyPath: keyPath] {
                return value
            }
        }

        let canonical = canonicalOpenAIModelID(lowerModelID: modelID.lowercased())
        return ModelCatalog.openAIDeclaredFeaturesByID[canonical]?[keyPath: keyPath]
    }

    /// Models that support the `web_search_20260209` tool with dynamic filtering.
    /// Documented list includes Fable 5, Mythos 5, Opus 4.8/4.7/4.6, Sonnet 5/4.6.
    static func supportsWebSearchDynamicFiltering(for providerType: ProviderType?, modelID: String) -> Bool {
        guard providerType == .anthropic || providerType == .claudeManagedAgents else { return false }
        if let declared = resolvedCatalogFeatures(for: providerType, modelID: modelID)?.webSearchDynamicFiltering {
            return declared
        }
        // Uncatalogued Anthropic IDs: no dynamic filtering (exact-ID policy).
        return false
    }
}
