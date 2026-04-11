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
    private static let openAINoneDefaultReasoningModelIDs: Set<String> = [
        "gpt-5.2",
        "gpt-5.2-2025-12-11",
        "gpt-5.4",
        "gpt-5.4-2026-03-05",
        "gpt-5.4-mini",
        "gpt-5.4-mini-2026-03-17",
        "gpt-5.4-nano",
        "gpt-5.4-nano-2026-03-17",
    ]

    private static let openAIHighDefaultReasoningModelIDs: Set<String> = [
        "gpt-5.4-pro",
        "gpt-5.4-pro-2026-03-05",
    ]

    private static let openAIStyleExtremeEffortModelIDs: Set<String> = [
        "gpt-5.4",
        "gpt-5.4-2026-03-05",
        "gpt-5.4-pro",
        "gpt-5.4-pro-2026-03-05",
        "gpt-5.4-mini",
        "gpt-5.4-mini-2026-03-17",
        "gpt-5.4-nano",
        "gpt-5.4-nano-2026-03-17",
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

    /// Gemini 3.1 Flash Image supports MINIMAL/HIGH.
    private static let gemini31FlashImageEffortModelIDs: Set<String> = [
        "gemini-3.1-flash-image-preview",
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

    /// Models documented by Google as supporting grounding with Google Search in Gemini API,
    /// plus narrow runtime trials we intentionally enable in Jin.
    private static let geminiGoogleSearchSupportedModelIDs: Set<String> = [
        "gemini-3.1-pro-preview",
        "gemini-3-pro-preview",
        "gemini-3-flash-preview",
        "gemini-3-pro-image-preview",
        "gemini-3.1-flash-image-preview",
        "gemini-3.1-flash-lite-preview",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.0-flash",
        "gemini-2.0-flash-001",
        "gemma-4-26b-a4b-it",
        "gemma-4-31b-it",
    ]

    /// Models supporting grounding with Google Search in Vertex AI.
    /// Includes Gemini 3.1 Flash Image based on runtime validation.
    private static let vertexGoogleSearchSupportedModelIDs: Set<String> = [
        "gemini-3.1-pro-preview",
        "gemini-3-pro-preview",
        "gemini-3-flash-preview",
        "gemini-3-pro-image-preview",
        "gemini-3.1-flash-image-preview",
        "gemini-3.1-flash-lite-preview",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.5-flash-preview",
        "gemini-2.5-flash-lite-preview",
        "gemini-2.0-flash",
    ]

    /// OpenRouter `plugins: [{id: "web"}]` support stays conservative and does not
    /// inherit Gemini-only runtime trials automatically.
    private static let openRouterGoogleSearchSupportedModelIDs: Set<String> = [
        "gemini-3.1-pro-preview",
        "gemini-3-pro-preview",
        "gemini-3-flash-preview",
        "gemini-3-pro-image-preview",
        "gemini-3.1-flash-image-preview",
        "gemini-3.1-flash-lite-preview",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.5-flash-preview",
        "gemini-2.5-flash-lite-preview",
        "gemini-2.0-flash",
        "gemini-2.0-flash-001",
    ]

    /// Fallback used by proxy providers other than explicit provider-specific allowlists.
    private static let proxiedGoogleSearchSupportedModelIDs: Set<String> =
        geminiGoogleSearchSupportedModelIDs.union(vertexGoogleSearchSupportedModelIDs)

    /// Models documented by Google as supporting grounding with Google Maps in Gemini API.
    /// Supported: Gemini 2.5 Pro, 2.5 Flash, 2.5 Flash-Lite, 2.0 Flash.
    /// Not supported: Gemini 3 family, Gemini 2.0 Flash Lite.
    private static let geminiGoogleMapsSupportedModelIDs: Set<String> = [
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.0-flash",
        "gemini-2.0-flash-001",
    ]

    /// Models supporting grounding with Google Maps in Vertex AI.
    /// Vertex documentation's Google Maps grounding pages list these exact model IDs
    /// or exact model families as supported as of March 13, 2026.
    ///
    /// Notes:
    /// - We include the current exact preview version IDs where the model pages expose them
    ///   (for example `gemini-2.5-flash-preview-09-2025`).
    /// - We also retain the legacy alias-style IDs already used in persisted Jin data
    ///   (for example `gemini-2.5-flash-preview`) so previously-saved conversations
    ///   do not silently lose the Maps UI toggle.
    private static let vertexGoogleMapsSupportedModelIDs: Set<String> = [
        "gemini-3-flash-preview",
        "gemini-3-pro-preview",
        "gemini-3-pro-image-preview",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.5-flash-preview",
        "gemini-2.5-flash-preview-09-2025",
        "gemini-2.5-flash-lite-preview",
        "gemini-2.5-flash-lite-preview-09-2025",
        "gemini-live-2.5-flash-native-audio",
        "gemini-live-2.5-flash-preview-native-audio-09-2025",
        "gemini-2.0-flash",
        "gemini-2.0-flash-001",
        "gemini-2.0-flash-live-preview-04-09",
    ]

    /// Models documented by Google as supporting code execution in Gemini API.
    private static let geminiCodeExecutionSupportedModelIDs: Set<String> = [
        "gemini-3-pro",
        "gemini-3-pro-preview",
        "gemini-3.1-pro",
        "gemini-3.1-pro-preview",
        "gemini-3-flash",
        "gemini-3-flash-preview",
        "gemini-3.1-flash-lite",
        "gemini-3.1-flash-lite-preview",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.0-flash",
        "gemini-2.0-flash-001",
    ]

    /// Models documented by Google as supporting code execution in Vertex AI.
    private static let vertexCodeExecutionSupportedModelIDs: Set<String> = [
        "gemini-3-pro",
        "gemini-3-pro-preview",
        "gemini-3.1-pro",
        "gemini-3.1-pro-preview",
        "gemini-3-flash",
        "gemini-3-flash-preview",
        "gemini-3.1-flash-lite",
        "gemini-3.1-flash-lite-preview",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.5-flash-preview",
        "gemini-2.5-flash-lite-preview",
        "gemini-2.0-flash",
        "gemini-2.0-flash-001",
    ]

    /// Exact model IDs that OpenAI currently documents as supporting the built-in Code interpreter tool.
    /// Keep this conservative: do not broaden to unlisted realtime/audio families.
    private static let openAICodeInterpreterSupportedModelIDs: Set<String> = [
        "gpt-4.1",
        "gpt-4.1-2025-04-14",
        "gpt-5",
        "gpt-5-2025-08-07",
        "gpt-5.2",
        "gpt-5.2-2025-12-11",
        "gpt-5.4",
        "gpt-5.4-2026-03-05",
        "gpt-5.4-mini",
        "gpt-5.4-mini-2026-03-17",
        "gpt-5.4-nano",
        "gpt-5.4-nano-2026-03-17",
        "gpt-5-mini",
        "gpt-5-mini-2025-08-07",
        "gpt-5-nano",
        "gpt-5-nano-2025-08-07",
        "o3",
        "o4-mini",
    ]

    /// Exact model IDs that Anthropic currently documents as supporting the code execution tool.
    private static let anthropicCodeExecutionSupportedModelIDs: Set<String> = [
        "claude-opus-4-6",
        "claude-sonnet-4-6",
        "claude-sonnet-4-5-20250929",
        "claude-opus-4-5-20251101",
        "claude-haiku-4-5-20251001",
        "claude-opus-4-1-20250805",
        "claude-opus-4-20250514",
        "claude-sonnet-4-20250514",
        "claude-3-7-sonnet-20250219",
        "claude-3-5-haiku-latest",
    ]

    private static let reasoningEffortRank: [ReasoningEffort: Int] = [
        .none: 0,
        .minimal: 1,
        .low: 2,
        .medium: 3,
        .high: 4,
        .xhigh: 5,
    ]

    private static let defaultReasoningEfforts: [ReasoningEffort] = [.low, .medium, .high]
    private static let defaultGeminiReasoningEfforts: [ReasoningEffort] = [.minimal, .low, .medium, .high]
    private static let googleModelPrefixes = [
        "google/",
        "google-ai-studio/",
        "google-vertex-ai/google/",
        "models/",
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
        case .anthropic, .claudeManagedAgents, .minimaxCodingPlan:
            return .anthropic
        case .gemini, .vertexai:
            return .gemini
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter,
             .groq, .cohere, .mistral, .deepinfra, .together, .xai, .deepseek,
             .zhipuCodingPlan, .minimax, .fireworks, .cerebras, .sambanova, .perplexity, .morphllm, .opencodeGo, .none:
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

        let canonicalLowerModelID = canonicalOpenAIModelID(lowerModelID: modelID.lowercased())
        return openAIStyleExtremeEffortModelIDs.contains(canonicalLowerModelID)
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
        return efforts
    }

    private static func supportedAnthropicEfforts(lowerModelID: String) -> [ReasoningEffort] {
        if AnthropicModelLimits.supportsMaxEffort(for: lowerModelID) {
            return [.low, .medium, .high, .xhigh]
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
        let lowerModelID = modelID.lowercased()

        switch providerType {
        case .openai, .openaiWebSocket:
            return supportsOpenAIWebSearch(lowerModelID: lowerModelID)
        case .openrouter:
            return supportsOpenRouterWebSearch(lowerModelID: lowerModelID)
        case .anthropic:
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
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .groq,
             .cohere, .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan,
             .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .none:
            return false
        }
    }

    static func defaultReasoningConfig(for providerType: ProviderType?, modelID: String) -> ModelReasoningConfig? {
        let lowerModelID = modelID.lowercased()
        let shape = requestShape(for: providerType, modelID: modelID)

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

    private static func supportsOpenRouterWebSearch(lowerModelID: String) -> Bool {
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
        return googleSearchSupportedModelIDs(for: providerType).contains(canonical)
    }

    private static func googleSearchSupportedModelIDs(for providerType: ProviderType?) -> Set<String> {
        switch providerType {
        case .gemini:
            return geminiGoogleSearchSupportedModelIDs
        case .vertexai:
            return vertexGoogleSearchSupportedModelIDs
        case .openrouter:
            return openRouterGoogleSearchSupportedModelIDs
        default:
            return proxiedGoogleSearchSupportedModelIDs
        }
    }

    private static func supportsGoogleCodeExecution(lowerModelID: String, providerType: ProviderType?) -> Bool {
        let canonical = canonicalGoogleModelID(lowerModelID: lowerModelID)
        return googleCodeExecutionSupportedModelIDs(for: providerType).contains(canonical)
    }

    private static func googleCodeExecutionSupportedModelIDs(for providerType: ProviderType?) -> Set<String> {
        switch providerType {
        case .gemini:
            return geminiCodeExecutionSupportedModelIDs
        case .vertexai:
            return vertexCodeExecutionSupportedModelIDs
        default:
            return []
        }
    }

    private static func canonicalGoogleModelID(lowerModelID: String) -> String {
        for prefix in googleModelPrefixes where lowerModelID.hasPrefix(prefix) {
            return String(lowerModelID.dropFirst(prefix.count))
        }
        return lowerModelID
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
        let lowerModelID = modelID.lowercased()

        switch providerType {
        case .openai, .openaiWebSocket:
            // OpenAI Responses API code_interpreter tool uses an exact documented model allowlist.
            // WebSocket mode uses the same Responses API and supports code_interpreter for non-realtime models.
            return supportsOpenAICodeInterpreter(lowerModelID: lowerModelID)
        case .anthropic:
            // Anthropic code_execution tool uses an exact documented model allowlist.
            return supportsAnthropicCodeExecution(lowerModelID: lowerModelID)
        case .claudeManagedAgents:
            return false
        case .xai:
            // xAI Responses API code_interpreter tool: Grok models
            return !isLikelyMediaGenerationModelID(lowerModelID)
        case .gemini:
            // Gemini API `tools.code_execution`
            return supportsGoogleCodeExecution(lowerModelID: lowerModelID, providerType: .gemini)
        case .vertexai:
            // Vertex AI `tools.codeExecution`
            return supportsGoogleCodeExecution(lowerModelID: lowerModelID, providerType: .vertexai)
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together,
             .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks, .cerebras, .sambanova, .morphllm,
             .opencodeGo, .none:
            return false
        }
    }

    private static func supportsOpenAICodeInterpreter(lowerModelID: String) -> Bool {
        let canonical = canonicalOpenAIModelID(lowerModelID: lowerModelID)
        return openAICodeInterpreterSupportedModelIDs.contains(canonical)
    }

    private static func supportsAnthropicCodeExecution(lowerModelID: String) -> Bool {
        let canonical: String
        if lowerModelID.hasPrefix("anthropic/") {
            canonical = String(lowerModelID.dropFirst("anthropic/".count))
        } else {
            canonical = lowerModelID
        }
        return anthropicCodeExecutionSupportedModelIDs.contains(canonical)
    }

    /// Whether the provider/model supports grounding with Google Maps.
    static func supportsGoogleMaps(for providerType: ProviderType?, modelID: String) -> Bool {
        let lowerModelID = modelID.lowercased()

        switch providerType {
        case .gemini:
            return supportsGoogleMapsGrounding(lowerModelID: lowerModelID, providerType: .gemini)
        case .vertexai:
            return supportsGoogleMapsGrounding(lowerModelID: lowerModelID, providerType: .vertexai)
        case .openai, .openaiWebSocket, .anthropic, .claudeManagedAgents, .xai, .codexAppServer, .githubCopilot,
             .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .perplexity,
             .groq, .cohere, .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan,
             .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .none:
            return false
        }
    }

    private static func supportsGoogleMapsGrounding(lowerModelID: String, providerType: ProviderType?) -> Bool {
        let canonical = canonicalGoogleModelID(lowerModelID: lowerModelID)
        return googleMapsSupportedModelIDs(for: providerType).contains(canonical)
    }

    private static func googleMapsSupportedModelIDs(for providerType: ProviderType?) -> Set<String> {
        switch providerType {
        case .gemini:
            return geminiGoogleMapsSupportedModelIDs
        case .vertexai:
            return vertexGoogleMapsSupportedModelIDs
        default:
            return []
        }
    }

    /// Models that support the `web_search_20260209` tool with dynamic filtering.
    static func supportsWebSearchDynamicFiltering(for providerType: ProviderType?, modelID: String) -> Bool {
        guard providerType == .anthropic || providerType == .claudeManagedAgents else { return false }
        let lower = modelID.lowercased()
        return lower.contains("claude-opus-4-6") || lower.contains("claude-sonnet-4-6")
    }
}
