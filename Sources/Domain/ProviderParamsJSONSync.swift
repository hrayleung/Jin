import Foundation

enum ProviderParamsJSONSync {
    static func makeDraft(
        providerType: ProviderType?,
        modelID: String,
        controls: GenerationControls
    ) -> [String: AnyCodable] {
        let base: [String: Any]

        switch providerType {
        case .openai, .openaiWebSocket:
            base = makeOpenAIDraft(controls: controls, modelID: modelID)
        case .anthropic:
            base = makeAnthropicDraft(controls: controls, modelID: modelID)
        case .xai:
            base = makeXAIDraft(controls: controls)
        case .gemini:
            base = makeGeminiDraft(controls: controls, modelID: modelID)
        case .vertexai:
            base = makeVertexAIDraft(controls: controls, modelID: modelID)
        case .cerebras:
            base = makeCerebrasDraft(controls: controls)
        case .fireworks:
            base = makeFireworksDraft(controls: controls, modelID: modelID)
        case .perplexity:
            base = makePerplexityDraft(controls: controls)
        case .codexAppServer, .openaiCompatible, .cloudflareAIGateway, .openrouter, .groq, .cohere, .mistral, .deepinfra, .deepseek, .none:
            base = [:]
        }

        var merged = base
        if let contextCacheDraft = makeContextCacheDraft(providerType: providerType, controls: controls) {
            merged["context_cache"] = contextCacheDraft
        }
        mergeProviderSpecific(
            into: &merged,
            providerType: providerType,
            modelID: modelID,
            providerSpecific: controls.providerSpecific
        )

        return merged.mapValues { AnyCodable($0) }
    }

    static func applyDraft(
        providerType: ProviderType?,
        modelID: String,
        draft: [String: AnyCodable],
        controls: inout GenerationControls
    ) -> [String: AnyCodable] {
        let normalizedDraft = pruneNulls(in: draft)
        var providerSpecific = normalizedDraft
        applyContextCache(
            draft: normalizedDraft,
            providerType: providerType,
            controls: &controls,
            providerSpecific: &providerSpecific
        )

        switch providerType {
        case .openai, .openaiWebSocket:
            applyOpenAI(
                draft: normalizedDraft,
                modelID: modelID,
                controls: &controls,
                providerSpecific: &providerSpecific
            )
        case .anthropic:
            applyAnthropic(draft: normalizedDraft, modelID: modelID, controls: &controls, providerSpecific: &providerSpecific)
        case .xai:
            applyXAI(draft: normalizedDraft, controls: &controls, providerSpecific: &providerSpecific)
        case .gemini:
            applyGemini(draft: normalizedDraft, modelID: modelID, controls: &controls, providerSpecific: &providerSpecific)
        case .vertexai:
            applyVertexAI(draft: normalizedDraft, modelID: modelID, controls: &controls, providerSpecific: &providerSpecific)
        case .cerebras:
            applyCerebras(draft: normalizedDraft, controls: &controls, providerSpecific: &providerSpecific)
        case .fireworks:
            applyFireworks(draft: normalizedDraft, modelID: modelID, controls: &controls, providerSpecific: &providerSpecific)
        case .perplexity:
            applyPerplexity(draft: normalizedDraft, controls: &controls, providerSpecific: &providerSpecific)
        case .codexAppServer, .openaiCompatible, .cloudflareAIGateway, .openrouter, .groq, .cohere, .mistral, .deepinfra, .deepseek, .none:
            break
        }

        return providerSpecific
    }

    // MARK: - Null Pruning

    static func pruneNulls(in dict: [String: AnyCodable]) -> [String: AnyCodable] {
        var out: [String: AnyCodable] = [:]
        out.reserveCapacity(dict.count)

        for (key, wrapped) in dict {
            guard let pruned = pruneNulls(any: wrapped.value) else { continue }
            out[key] = AnyCodable(pruned)
        }

        return out
    }

    private static func pruneNulls(any value: Any) -> Any? {
        switch value {
        case is NSNull:
            return nil
        case let array as [Any]:
            return array.compactMap { pruneNulls(any: $0) }
        case let array as [AnyCodable]:
            return array.compactMap { pruneNulls(any: $0.value) }
        case let dict as [String: Any]:
            var out: [String: Any] = [:]
            out.reserveCapacity(dict.count)
            for (key, value) in dict {
                if let pruned = pruneNulls(any: value) {
                    out[key] = pruned
                }
            }
            return out
        case let dict as [String: AnyCodable]:
            var out: [String: Any] = [:]
            out.reserveCapacity(dict.count)
            for (key, value) in dict {
                if let pruned = pruneNulls(any: value.value) {
                    out[key] = pruned
                }
            }
            return out
        default:
            return value
        }
    }

    // MARK: - Context Cache

    static func supportsContextCache(providerType: ProviderType?) -> Bool {
        switch providerType {
        case .openai, .openaiWebSocket, .anthropic, .gemini, .vertexai, .xai:
            return true
        case .codexAppServer, .openaiCompatible, .cloudflareAIGateway, .openrouter, .perplexity, .groq, .cohere, .mistral, .deepinfra, .deepseek, .fireworks, .cerebras, .none:
            return false
        }
    }

    static func makeContextCacheDraft(
        providerType: ProviderType?,
        controls: GenerationControls
    ) -> [String: Any]? {
        guard supportsContextCache(providerType: providerType),
              let contextCache = controls.contextCache else {
            return nil
        }

        var out: [String: Any] = [
            "mode": contextCache.mode.rawValue
        ]

        if let strategy = contextCache.strategy {
            out["strategy"] = strategy.rawValue
        }
        if let ttl = contextCache.ttl {
            switch ttl {
            case .providerDefault:
                out["ttl"] = "default"
            case .minutes5:
                out["ttl"] = "5m"
            case .hour1:
                out["ttl"] = "1h"
            case .customSeconds(let seconds):
                out["ttl"] = "custom:\(max(1, seconds))"
            }
        }
        if let cacheKey = normalizedTrimmedString(contextCache.cacheKey) {
            out["cache_key"] = cacheKey
        }
        if let conversationID = normalizedTrimmedString(contextCache.conversationID) {
            out["conversation_id"] = conversationID
        }
        if let cachedContent = normalizedTrimmedString(contextCache.cachedContentName) {
            out["cached_content_name"] = cachedContent
        }
        if let minTokens = contextCache.minTokensThreshold, minTokens > 0 {
            out["min_tokens_threshold"] = minTokens
        }

        return out
    }

    static func applyContextCache(
        draft: [String: AnyCodable],
        providerType: ProviderType?,
        controls: inout GenerationControls,
        providerSpecific: inout [String: AnyCodable]
    ) {
        guard supportsContextCache(providerType: providerType) else {
            controls.contextCache = nil
            providerSpecific.removeValue(forKey: "context_cache")
            return
        }

        guard let raw = draft["context_cache"]?.value else {
            controls.contextCache = nil
            return
        }

        guard let dict = raw as? [String: Any] else {
            return
        }

        var contextCache = controls.contextCache ?? ContextCacheControls(mode: .implicit)
        var remaining = dict

        if let rawMode = dict["mode"] as? String {
            contextCache.mode = ContextCacheMode(rawValue: rawMode.lowercased()) ?? .implicit
            remaining.removeValue(forKey: "mode")
        }

        if let rawStrategy = dict["strategy"] as? String {
            contextCache.strategy = ContextCacheStrategy(rawValue: rawStrategy)
            remaining.removeValue(forKey: "strategy")
        }

        if let rawTTL = dict["ttl"] {
            contextCache.ttl = parseContextCacheTTL(rawTTL)
            remaining.removeValue(forKey: "ttl")
        }

        if let rawCacheKey = dict["cache_key"] as? String {
            contextCache.cacheKey = normalizedTrimmedString(rawCacheKey)
            remaining.removeValue(forKey: "cache_key")
        }

        if let rawConversationID = dict["conversation_id"] as? String {
            contextCache.conversationID = normalizedTrimmedString(rawConversationID)
            remaining.removeValue(forKey: "conversation_id")
        }

        if let rawCachedContent = dict["cached_content_name"] as? String {
            contextCache.cachedContentName = normalizedTrimmedString(rawCachedContent)
            remaining.removeValue(forKey: "cached_content_name")
        }

        if let rawMinTokens = dict["min_tokens_threshold"],
           let minTokens = intValue(from: rawMinTokens),
           minTokens > 0 {
            contextCache.minTokensThreshold = minTokens
            remaining.removeValue(forKey: "min_tokens_threshold")
        } else if dict["min_tokens_threshold"] != nil {
            remaining.removeValue(forKey: "min_tokens_threshold")
        }

        controls.contextCache = contextCache

        if remaining.isEmpty {
            providerSpecific.removeValue(forKey: "context_cache")
        } else {
            providerSpecific["context_cache"] = AnyCodable(remaining)
        }
    }

    static func parseContextCacheTTL(_ raw: Any) -> ContextCacheTTL {
        if let value = intValue(from: raw), value > 0 {
            return .customSeconds(value)
        }

        guard let rawString = raw as? String else {
            return .providerDefault
        }

        let normalized = rawString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "", "default", "provider_default", "providerdefault":
            return .providerDefault
        case "5m", "5min", "5mins", "minutes5":
            return .minutes5
        case "1h", "60m", "hour1":
            return .hour1
        default:
            if normalized.hasPrefix("custom:"),
               let value = Int(normalized.dropFirst("custom:".count)),
               value > 0 {
                return .customSeconds(value)
            }
            if normalized.hasSuffix("s"),
               let value = Int(normalized.dropLast()),
               value > 0 {
                return .customSeconds(value)
            }
            return .providerDefault
        }
    }

    // MARK: - Provider-Specific Merge

    static func mergeProviderSpecific(
        into base: inout [String: Any],
        providerType: ProviderType?,
        modelID: String,
        providerSpecific: [String: AnyCodable]
    ) {
        guard !providerSpecific.isEmpty else { return }

        let additional = providerSpecific.mapValues { $0.value }

        switch providerType {
        case .gemini, .vertexai, .perplexity:
            deepMerge(into: &base, additional: additional)

        case .anthropic:
            for (key, value) in additional {
                if key == "output_format" {
                    var output = (base["output_config"] as? [String: Any]) ?? [:]
                    output["format"] = value
                    base["output_config"] = output
                    continue
                }

                if key == "output_config", let dict = value as? [String: Any] {
                    var output = (base["output_config"] as? [String: Any]) ?? [:]
                    deepMerge(into: &output, additional: dict)
                    base["output_config"] = output
                    continue
                }

                base[key] = value
            }

        case .openai, .openaiWebSocket, .codexAppServer, .cerebras, .fireworks, .openaiCompatible, .cloudflareAIGateway, .openrouter, .groq, .cohere, .mistral, .deepinfra, .xai, .deepseek, .none:
            base.merge(additional) { _, new in new }
        }
    }

    // MARK: - Shared Utilities

    static func deepMerge(into base: inout [String: Any], additional: [String: Any]) {
        for (key, value) in additional {
            if var baseDict = base[key] as? [String: Any], let addDict = value as? [String: Any] {
                deepMerge(into: &baseDict, additional: addDict)
                base[key] = baseDict
            } else {
                base[key] = value
            }
        }
    }

    static func applyThinkingConfig(
        _ dict: [String: Any],
        defaultLevelWhenOff: String,
        controls: inout GenerationControls
    ) {
        let includeThoughts = (dict["includeThoughts"] as? Bool) ?? false
        let budget = dict["thinkingBudget"].flatMap(intValue(from:))
        let levelString = dict["thinkingLevel"] as? String

        if includeThoughts {
            var reasoning = controls.reasoning ?? ReasoningControls(enabled: true)
            reasoning.enabled = true
            reasoning.summary = nil

            if let budget {
                reasoning.budgetTokens = budget
                reasoning.effort = nil
            } else if let levelString, let effort = parseThinkingLevel(levelString) {
                reasoning.effort = effort
                reasoning.budgetTokens = nil
            }

            controls.reasoning = reasoning
        } else if let levelString, levelString.uppercased() == defaultLevelWhenOff.uppercased() {
            controls.reasoning = ReasoningControls(enabled: false)
        } else {
            controls.reasoning = nil
        }
    }

    static func parseThinkingLevel(_ raw: String) -> ReasoningEffort? {
        switch raw.uppercased() {
        case "MINIMAL":
            return .minimal
        case "LOW":
            return .low
        case "MEDIUM":
            return .medium
        case "HIGH":
            return .high
        default:
            return nil
        }
    }

    static func applyResponseModalities(_ array: [Any], controls: inout GenerationControls) {
        let strings = array.compactMap { $0 as? String }
        let set = Set(strings.map { $0.uppercased() })

        var image = controls.imageGeneration ?? ImageGenerationControls()
        if set == ["IMAGE"] {
            image.responseMode = .imageOnly
        } else if set.contains("IMAGE") {
            image.responseMode = .textAndImage
        } else {
            image.responseMode = nil
        }

        controls.imageGeneration = image.isEmpty ? nil : image
    }

    static func doubleValue(from raw: Any) -> Double? {
        if let value = raw as? Double {
            return value
        }
        if let value = raw as? Int {
            return Double(value)
        }
        if let value = raw as? String {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func intValue(from raw: Any) -> Int? {
        if let value = raw as? Int {
            return value
        }
        if let value = raw as? Double {
            let rounded = Int(value)
            if abs(value - Double(rounded)) < 0.000_000_1 {
                return rounded
            }
            return nil
        }
        if let value = raw as? String {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}
