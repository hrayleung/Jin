import Foundation

// MARK: - OpenAI Draft & Apply

extension ProviderParamsJSONSync {

    static func makeOpenAIDraft(
        controls: GenerationControls,
        modelID: String
    ) -> [String: Any] {
        var out: [String: Any] = [:]

        if let temperature = controls.temperature {
            out["temperature"] = temperature
        }

        if let topP = controls.topP {
            out["top_p"] = topP
        }

        if let maxTokens = controls.maxTokens {
            out["max_output_tokens"] = maxTokens
        }

        if let reasoning = controls.reasoning {
            let effortString: String
            if reasoning.enabled {
                let normalizedEffort = ModelCapabilityRegistry.normalizedReasoningEffort(
                    reasoning.effort ?? .none,
                    for: .openai,
                    modelID: modelID
                )
                effortString = mapOpenAIEffort(normalizedEffort)
            } else {
                effortString = "none"
            }

            var reasoningDict: [String: Any] = [
                "effort": effortString
            ]
            if let summary = reasoning.summary {
                reasoningDict["summary"] = summary.rawValue
            }
            out["reasoning"] = reasoningDict
        }

        if controls.webSearch?.enabled == true {
            var webSearchTool: [String: Any] = ["type": "web_search"]
            if let size = controls.webSearch?.contextSize {
                webSearchTool["search_context_size"] = size.rawValue
            }
            out["tools"] = [webSearchTool]
        }

        if let contextCache = controls.contextCache, contextCache.mode != .off {
            if let cacheKey = normalizedTrimmedString(contextCache.cacheKey) {
                out["prompt_cache_key"] = cacheKey
            }
            if let retention = contextCache.ttl?.providerTTLString {
                out["prompt_cache_retention"] = retention
            }
        }

        return out
    }

    static func applyOpenAI(
        draft: [String: AnyCodable],
        modelID: String,
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

        if let raw = draft["max_output_tokens"]?.value {
            if let value = intValue(from: raw) {
                controls.maxTokens = value
                providerSpecific.removeValue(forKey: "max_output_tokens")
            }
        } else {
            controls.maxTokens = nil
        }

        if let raw = draft["reasoning"]?.value {
            if let dict = raw as? [String: Any] {
                let canPromote = applyOpenAIReasoning(dict, modelID: modelID, controls: &controls)
                if canPromote {
                    providerSpecific.removeValue(forKey: "reasoning")
                }
            }
        } else {
            controls.reasoning = nil
        }

        if let raw = draft["tools"]?.value {
            let canPromote = applyOpenAIWebSearchTools(raw, controls: &controls)
            if canPromote {
                providerSpecific.removeValue(forKey: "tools")
            }
        } else {
            if controls.webSearch != nil {
                controls.webSearch?.enabled = false
            } else {
                controls.webSearch = nil
            }
        }

        var contextCache = controls.contextCache ?? ContextCacheControls(mode: .implicit)
        var touchedContextCache = false

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

    // MARK: - OpenAI Helpers

    static func applyOpenAIReasoning(
        _ dict: [String: Any],
        modelID: String,
        controls: inout GenerationControls
    ) -> Bool {
        let knownKeys: Set<String> = ["effort", "summary"]
        let isSimple = Set(dict.keys).isSubset(of: knownKeys)

        guard let effortString = dict["effort"] as? String,
              let effort = parseOpenAIEffort(effortString) else {
            return false
        }

        let summaryString = dict["summary"] as? String
        let summary = summaryString.flatMap(parseReasoningSummary)

        if effort == .none {
            var reasoning = controls.reasoning ?? ReasoningControls(enabled: false)
            reasoning.enabled = false
            if let summary {
                reasoning.summary = summary
            }
            reasoning.effort = nil
            reasoning.budgetTokens = nil
            controls.reasoning = reasoning
            return isSimple && (summaryString == nil || summary != nil)
        }

        let normalizedEffort = ModelCapabilityRegistry.normalizedReasoningEffort(
            effort,
            for: .openai,
            modelID: modelID
        )

        controls.reasoning = ReasoningControls(
            enabled: true,
            effort: normalizedEffort,
            budgetTokens: nil,
            summary: summary ?? .auto
        )

        return isSimple && (summaryString == nil || summary != nil)
    }

    static func applyOpenAIWebSearchTools(
        _ raw: Any,
        controls: inout GenerationControls
    ) -> Bool {
        guard let array = raw as? [Any] else { return false }

        var found = false
        var contextSize: WebSearchContextSize?
        var nonWebSearchToolCount = 0
        var canPromoteToUI = (array.count == 1)

        for item in array {
            guard let dict = item as? [String: Any] else {
                nonWebSearchToolCount += 1
                canPromoteToUI = false
                continue
            }

            if let type = dict["type"] as? String, type == "web_search" {
                found = true
                let knownKeys: Set<String> = ["type", "search_context_size"]
                if !Set(dict.keys).isSubset(of: knownKeys) {
                    canPromoteToUI = false
                }

                if let sizeString = dict["search_context_size"] as? String {
                    if let parsed = WebSearchContextSize(rawValue: sizeString.lowercased()) {
                        contextSize = parsed
                    } else {
                        canPromoteToUI = false
                    }
                }
            } else {
                nonWebSearchToolCount += 1
                canPromoteToUI = false
            }
        }

        if found {
            controls.webSearch = WebSearchControls(enabled: true, contextSize: contextSize, sources: nil)
        } else {
            controls.webSearch = nil
        }

        return found && nonWebSearchToolCount == 0 && canPromoteToUI
    }

    static func mapOpenAIEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none:
            return "none"
        case .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .xhigh:
            return "xhigh"
        }
    }

    static func parseOpenAIEffort(_ raw: String) -> ReasoningEffort? {
        switch raw.lowercased() {
        case "none":
            return ReasoningEffort.none
        case "minimal":
            return .minimal
        case "low":
            return .low
        case "medium":
            return .medium
        case "high":
            return .high
        case "xhigh", "extra_high", "extra-high":
            return .xhigh
        default:
            return nil
        }
    }

    static func parseReasoningSummary(_ raw: String) -> ReasoningSummary? {
        ReasoningSummary(rawValue: raw.lowercased())
    }
}
