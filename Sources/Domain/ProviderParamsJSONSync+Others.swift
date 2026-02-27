import Foundation

// MARK: - xAI, Cerebras, Fireworks, Perplexity Draft & Apply

extension ProviderParamsJSONSync {

    // MARK: - xAI

    static func makeXAIDraft(controls: GenerationControls) -> [String: Any] {
        var out: [String: Any] = [:]

        guard let contextCache = controls.contextCache, contextCache.mode != .off else {
            return out
        }

        if let conversationID = normalizedTrimmedString(contextCache.conversationID) {
            out["x-grok-conv-id"] = conversationID
        }
        if let cacheKey = normalizedTrimmedString(contextCache.cacheKey) {
            out["prompt_cache_key"] = cacheKey
        }
        if let retention = contextCache.ttl?.providerTTLString {
            out["prompt_cache_retention"] = retention
        }

        return out
    }

    static func applyXAI(
        draft: [String: AnyCodable],
        controls: inout GenerationControls,
        providerSpecific: inout [String: AnyCodable]
    ) {
        var contextCache = controls.contextCache ?? ContextCacheControls(mode: .implicit)
        var touchedContextCache = false

        if let raw = draft["x-grok-conv-id"]?.value as? String {
            contextCache.conversationID = normalizedTrimmedString(raw)
            touchedContextCache = true
            providerSpecific.removeValue(forKey: "x-grok-conv-id")
        }

        if let raw = draft["prompt_cache_key"]?.value as? String {
            contextCache.cacheKey = normalizedTrimmedString(raw)
            touchedContextCache = true
            providerSpecific.removeValue(forKey: "prompt_cache_key")
        }

        if let raw = draft["prompt_cache_retention"]?.value as? String {
            contextCache.ttl = parseContextCacheTTL(raw)
            touchedContextCache = true
            providerSpecific.removeValue(forKey: "prompt_cache_retention")
        }

        if let raw = draft["prompt_cache_min_tokens"]?.value, let value = intValue(from: raw), value > 0 {
            contextCache.minTokensThreshold = value
            touchedContextCache = true
            providerSpecific.removeValue(forKey: "prompt_cache_min_tokens")
        } else if draft["prompt_cache_min_tokens"] != nil {
            providerSpecific.removeValue(forKey: "prompt_cache_min_tokens")
        }

        if touchedContextCache {
            contextCache.mode = .implicit
            controls.contextCache = contextCache
        }
    }

    // MARK: - Cerebras

    static func makeCerebrasDraft(controls: GenerationControls) -> [String: Any] {
        var out: [String: Any] = [:]

        if let temperature = controls.temperature {
            out["temperature"] = temperature
        }

        if let topP = controls.topP {
            out["top_p"] = topP
        }

        if let maxTokens = controls.maxTokens {
            out["max_completion_tokens"] = maxTokens
        }

        if let reasoning = controls.reasoning {
            out["disable_reasoning"] = (reasoning.enabled == false)
            out["reasoning_format"] = (reasoning.enabled == false) ? "none" : "parsed"
        }

        return out
    }

    static func applyCerebras(
        draft: [String: AnyCodable],
        controls: inout GenerationControls,
        providerSpecific: inout [String: AnyCodable]
    ) {
        if let raw = draft["temperature"]?.value {
            if let value = doubleValue(from: raw) {
                controls.temperature = value
                providerSpecific.removeValue(forKey: "temperature")
            }
        } else {
            controls.temperature = nil
        }

        if let raw = draft["top_p"]?.value {
            if let value = doubleValue(from: raw) {
                controls.topP = value
                providerSpecific.removeValue(forKey: "top_p")
            }
        } else {
            controls.topP = nil
        }

        if let raw = draft["max_completion_tokens"]?.value {
            if let value = intValue(from: raw) {
                controls.maxTokens = value
                providerSpecific.removeValue(forKey: "max_completion_tokens")
            }
        } else {
            controls.maxTokens = nil
        }

        if let raw = draft["disable_reasoning"]?.value, let disabled = raw as? Bool {
            var reasoning = controls.reasoning ?? ReasoningControls(enabled: true)
            reasoning.enabled = !disabled
            controls.reasoning = reasoning
            providerSpecific.removeValue(forKey: "disable_reasoning")
        } else {
            controls.reasoning = nil
        }

        if let raw = draft["reasoning_format"]?.value, let formatRaw = raw as? String {
            let format = formatRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch format {
            case "none":
                var reasoning = controls.reasoning ?? ReasoningControls(enabled: true)
                reasoning.enabled = false
                controls.reasoning = reasoning
                providerSpecific.removeValue(forKey: "reasoning_format")
            case "parsed":
                var reasoning = controls.reasoning ?? ReasoningControls(enabled: true)
                reasoning.enabled = true
                controls.reasoning = reasoning
                providerSpecific.removeValue(forKey: "reasoning_format")
            case "":
                providerSpecific.removeValue(forKey: "reasoning_format")
            default:
                break
            }
        }
    }

    // MARK: - Fireworks

    static func makeFireworksDraft(controls: GenerationControls, modelID: String) -> [String: Any] {
        var out: [String: Any] = [:]
        let isMiniMaxM2FamilyModel = isFireworksMiniMaxM2FamilyModel(modelID)

        if let temperature = controls.temperature {
            out["temperature"] = temperature
        }

        if let topP = controls.topP {
            out["top_p"] = topP
        }

        if let maxTokens = controls.maxTokens {
            out["max_tokens"] = maxTokens
        }

        if let reasoning = controls.reasoning {
            if reasoning.enabled == false || (reasoning.effort ?? ReasoningEffort.none) == ReasoningEffort.none {
                if !isMiniMaxM2FamilyModel {
                    out["reasoning_effort"] = "none"
                }
            } else if let effort = reasoning.effort {
                out["reasoning_effort"] = mapFireworksEffort(effort)
            }
        }

        return out
    }

    static func applyFireworks(
        draft: [String: AnyCodable],
        modelID: String,
        controls: inout GenerationControls,
        providerSpecific: inout [String: AnyCodable]
    ) {
        let isMiniMaxM2FamilyModel = isFireworksMiniMaxM2FamilyModel(modelID)

        if let raw = draft["temperature"]?.value {
            if let value = doubleValue(from: raw) {
                controls.temperature = value
                providerSpecific.removeValue(forKey: "temperature")
            }
        } else {
            controls.temperature = nil
        }

        if let raw = draft["top_p"]?.value {
            if let value = doubleValue(from: raw) {
                controls.topP = value
                providerSpecific.removeValue(forKey: "top_p")
            }
        } else {
            controls.topP = nil
        }

        if let raw = draft["max_tokens"]?.value {
            if let value = intValue(from: raw) {
                controls.maxTokens = value
                providerSpecific.removeValue(forKey: "max_tokens")
            }
        } else {
            controls.maxTokens = nil
        }

        if let raw = draft["reasoning_effort"]?.value {
            if let effortString = raw as? String,
               let effort = parseFireworksEffort(effortString) {
                if effort == .none {
                    if isMiniMaxM2FamilyModel {
                        controls.reasoning = ReasoningControls(enabled: true, effort: .medium, budgetTokens: nil, summary: nil)
                    } else {
                        controls.reasoning = ReasoningControls(enabled: false, effort: nil, budgetTokens: nil, summary: nil)
                    }
                } else {
                    controls.reasoning = ReasoningControls(enabled: true, effort: effort, budgetTokens: nil, summary: nil)
                }
                providerSpecific.removeValue(forKey: "reasoning_effort")
            } else if isMiniMaxM2FamilyModel {
                controls.reasoning = ReasoningControls(enabled: true, effort: .medium, budgetTokens: nil, summary: nil)
                providerSpecific.removeValue(forKey: "reasoning_effort")
            }
        } else {
            if isMiniMaxM2FamilyModel {
                controls.reasoning = ReasoningControls(enabled: true, effort: .medium, budgetTokens: nil, summary: nil)
            } else {
                controls.reasoning = nil
            }
        }

        if let rawHistory = draft["reasoning_history"]?.value as? String {
            let normalized = rawHistory.lowercased()
            if supportedFireworksReasoningHistoryValues(for: modelID).contains(normalized) {
                providerSpecific["reasoning_history"] = AnyCodable(normalized)
            } else {
                providerSpecific.removeValue(forKey: "reasoning_history")
            }
        } else if draft["reasoning_history"] != nil {
            providerSpecific.removeValue(forKey: "reasoning_history")
        }
    }

    // MARK: - Perplexity

    static func makePerplexityDraft(controls: GenerationControls) -> [String: Any] {
        var out: [String: Any] = [:]

        if let temperature = controls.temperature {
            out["temperature"] = temperature
        }

        if let topP = controls.topP {
            out["top_p"] = topP
        }

        if let maxTokens = controls.maxTokens {
            out["max_tokens"] = maxTokens
        }

        if let reasoning = controls.reasoning,
           reasoning.enabled,
           let effort = mapPerplexityEffort(reasoning.effort ?? .medium) {
            out["reasoning_effort"] = effort
        }

        if let webSearch = controls.webSearch {
            if webSearch.enabled == false {
                out["disable_search"] = true
            } else if let contextSize = webSearch.contextSize {
                out["web_search_options"] = [
                    "search_context_size": contextSize.rawValue
                ]
            }
        }

        return out
    }

    static func applyPerplexity(
        draft: [String: AnyCodable],
        controls: inout GenerationControls,
        providerSpecific: inout [String: AnyCodable]
    ) {
        if let raw = draft["temperature"]?.value {
            if let value = doubleValue(from: raw) {
                controls.temperature = value
                providerSpecific.removeValue(forKey: "temperature")
            }
        } else {
            controls.temperature = nil
        }

        if let raw = draft["top_p"]?.value {
            if let value = doubleValue(from: raw) {
                controls.topP = value
                providerSpecific.removeValue(forKey: "top_p")
            }
        } else {
            controls.topP = nil
        }

        if let raw = draft["max_tokens"]?.value {
            if let value = intValue(from: raw) {
                controls.maxTokens = value
                providerSpecific.removeValue(forKey: "max_tokens")
            }
        } else {
            controls.maxTokens = nil
        }

        if let raw = draft["reasoning_effort"]?.value as? String,
           let effort = parsePerplexityEffort(raw) {
            controls.reasoning = ReasoningControls(enabled: true, effort: effort, budgetTokens: nil, summary: nil)
            providerSpecific.removeValue(forKey: "reasoning_effort")
        } else if draft["reasoning_effort"] == nil {
            controls.reasoning = nil
        }

        let hasDisableSearchKey = draft["disable_search"] != nil
        let hasWebSearchOptionsKey = draft["web_search_options"] != nil

        var promotedContextSize: WebSearchContextSize?
        var promotedDisableSearch: Bool?

        if let raw = draft["web_search_options"]?.value as? [String: Any] {
            var remaining = raw

            if let sizeString = raw["search_context_size"] as? String,
               let parsed = WebSearchContextSize(rawValue: sizeString.lowercased()) {
                promotedContextSize = parsed
                remaining.removeValue(forKey: "search_context_size")
            }

            if let disable = raw["disable_search"] as? Bool {
                promotedDisableSearch = disable
                remaining.removeValue(forKey: "disable_search")
            }

            if remaining.isEmpty {
                providerSpecific.removeValue(forKey: "web_search_options")
            } else {
                providerSpecific["web_search_options"] = AnyCodable(remaining)
            }
        }

        if let rawDisable = draft["disable_search"]?.value as? Bool {
            promotedDisableSearch = rawDisable
            providerSpecific.removeValue(forKey: "disable_search")
        }

        if promotedDisableSearch == false && promotedContextSize == nil {
            controls.webSearch = nil
        } else if promotedDisableSearch != nil || promotedContextSize != nil {
            let isDisabled = promotedDisableSearch == true
            controls.webSearch = WebSearchControls(enabled: !isDisabled, contextSize: promotedContextSize, sources: nil)
        } else if !hasDisableSearchKey && hasWebSearchOptionsKey {
            controls.webSearch = nil
        } else if !hasDisableSearchKey && !hasWebSearchOptionsKey {
            controls.webSearch = nil
        }
    }

    // MARK: - Provider-Specific Helpers

    static func mapFireworksEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none:
            return "none"
        case .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high, .xhigh:
            return "high"
        }
    }

    static func parseFireworksEffort(_ raw: String) -> ReasoningEffort? {
        switch raw.lowercased() {
        case "none":
            return ReasoningEffort.none
        case "low":
            return .low
        case "medium":
            return .medium
        case "high":
            return .high
        default:
            return nil
        }
    }

    static func supportedFireworksReasoningHistoryValues(for modelID: String) -> Set<String> {
        if isFireworksMiniMaxM2FamilyModel(modelID) {
            return ["interleaved", "disabled"]
        }

        let preservedHistoryModels: Set<String> = ["kimi-k2p5", "glm-4p7", "glm-5"]
        if let canonical = fireworksCanonicalModelID(modelID),
           preservedHistoryModels.contains(canonical) {
            return ["preserved", "interleaved", "disabled"]
        }

        return []
    }

    static func mapPerplexityEffort(_ effort: ReasoningEffort) -> String? {
        switch effort {
        case .none:
            return nil
        case .minimal:
            return "minimal"
        case .low:
            return "low"
        case .medium:
            return "medium"
        case .high, .xhigh:
            return "high"
        }
    }

    static func parsePerplexityEffort(_ raw: String) -> ReasoningEffort? {
        switch raw.lowercased() {
        case "minimal":
            return .minimal
        case "low":
            return .low
        case "medium":
            return .medium
        case "high":
            return .high
        default:
            return nil
        }
    }
}
