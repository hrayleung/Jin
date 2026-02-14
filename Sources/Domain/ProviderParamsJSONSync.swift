import Foundation

enum ProviderParamsJSONSync {
    static func makeDraft(
        providerType: ProviderType?,
        modelID: String,
        controls: GenerationControls
    ) -> [String: AnyCodable] {
        let base: [String: Any]

        switch providerType {
        case .openai:
            base = makeOpenAIDraft(controls: controls)
        case .anthropic:
            base = makeAnthropicDraft(controls: controls, modelID: modelID)
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
        case .openaiCompatible, .openrouter, .groq, .cohere, .mistral, .deepinfra, .xai, .deepseek, .none:
            base = [:]
        }

        var merged = base
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

        switch providerType {
        case .openai:
            applyOpenAI(draft: normalizedDraft, controls: &controls, providerSpecific: &providerSpecific)
        case .anthropic:
            applyAnthropic(draft: normalizedDraft, modelID: modelID, controls: &controls, providerSpecific: &providerSpecific)
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
        case .openaiCompatible, .openrouter, .groq, .cohere, .mistral, .deepinfra, .xai, .deepseek, .none:
            break
        }

        return providerSpecific
    }

    private static func pruneNulls(in dict: [String: AnyCodable]) -> [String: AnyCodable] {
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

    // MARK: - Draft builders

    private static func makeOpenAIDraft(controls: GenerationControls) -> [String: Any] {
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
                effortString = mapOpenAIEffort(reasoning.effort ?? .none)
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

        return out
    }

    private static func makeAnthropicDraft(controls: GenerationControls, modelID: String) -> [String: Any] {
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

        if let reasoning = controls.reasoning, reasoning.enabled {
            let supportsAdaptive = AnthropicModelLimits.supportsAdaptiveThinking(for: modelID)
            let supportsEffort = AnthropicModelLimits.supportsEffort(for: modelID)

            if supportsAdaptive, reasoning.budgetTokens == nil {
                out["thinking"] = ["type": "adaptive"]
            } else {
                out["thinking"] = [
                    "type": "enabled",
                    "budget_tokens": reasoning.budgetTokens ?? 2048
                ]
            }

            if supportsEffort, reasoning.budgetTokens == nil, let effort = reasoning.effort {
                out["output_config"] = [
                    "effort": mapAnthropicEffort(effort, modelID: modelID)
                ]
            }
        }

        if controls.webSearch?.enabled == true {
            out["tools"] = [
                [
                    "type": "web_search_20250305",
                    "name": "web_search"
                ]
            ]
        }

        return out
    }

    private static func makeGeminiDraft(controls: GenerationControls, modelID: String) -> [String: Any] {
        var out: [String: Any] = [:]

        let generationConfig = makeGeminiGenerationConfig(controls: controls, modelID: modelID)
        if !generationConfig.isEmpty {
            out["generationConfig"] = generationConfig
        }

        if controls.webSearch?.enabled == true, geminiSupportsGoogleSearch(modelID) {
            out["tools"] = [
                ["google_search": [:]]
            ]
        }

        return out
    }

    private static func makeVertexAIDraft(controls: GenerationControls, modelID: String) -> [String: Any] {
        var out: [String: Any] = [:]

        let generationConfig = makeVertexAIGenerationConfig(controls: controls, modelID: modelID)
        if !generationConfig.isEmpty {
            out["generationConfig"] = generationConfig
        }

        if controls.webSearch?.enabled == true, vertexSupportsGoogleSearch(modelID) {
            out["tools"] = [
                ["googleSearch": [:]]
            ]
        }

        return out
    }

    private static func makeCerebrasDraft(controls: GenerationControls) -> [String: Any] {
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

    private static func makeFireworksDraft(controls: GenerationControls, modelID: String) -> [String: Any] {
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

    private static func makePerplexityDraft(controls: GenerationControls) -> [String: Any] {
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

    // MARK: - Apply (draft -> controls)

    private static func applyOpenAI(
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
                let canPromote = applyOpenAIReasoning(dict, controls: &controls)
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
    }

    private static func applyAnthropic(
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

        if let raw = draft["max_tokens"]?.value {
            if let value = intValue(from: raw) {
                controls.maxTokens = value
                providerSpecific.removeValue(forKey: "max_tokens")
            }
        } else {
            controls.maxTokens = nil
        }

        if let raw = draft["thinking"]?.value {
            if let dict = raw as? [String: Any] {
                let canPromote = applyAnthropicThinking(dict, modelID: modelID, controls: &controls)
                if canPromote {
                    providerSpecific.removeValue(forKey: "thinking")
                }
            }
        } else {
            controls.reasoning = nil
        }

        if let raw = draft["output_config"]?.value {
            if let dict = raw as? [String: Any] {
                applyAnthropicOutputConfig(dict, modelID: modelID, controls: &controls, providerSpecific: &providerSpecific)
            }
        }

        if let raw = draft["tools"]?.value {
            let canPromote = applyAnthropicWebSearchTools(raw, controls: &controls)
            if canPromote {
                providerSpecific.removeValue(forKey: "tools")
            }
        } else {
            controls.webSearch = nil
        }
    }

    private static func applyGemini(
        draft: [String: AnyCodable],
        modelID: String,
        controls: inout GenerationControls,
        providerSpecific: inout [String: AnyCodable]
    ) {
        if let raw = draft["generationConfig"]?.value {
            if let dict = raw as? [String: Any] {
                applyGeminiGenerationConfig(dict, modelID: modelID, controls: &controls, providerSpecific: &providerSpecific)
            }
        } else {
            controls.temperature = nil
            controls.maxTokens = nil
            controls.topP = nil
            controls.reasoning = nil
            controls.imageGeneration = nil
        }

        if let raw = draft["tools"]?.value {
            let canPromote = applyGoogleSearchTools(raw, key: "google_search", controls: &controls)
            if canPromote {
                providerSpecific.removeValue(forKey: "tools")
            }
        } else {
            controls.webSearch = nil
        }
    }

    private static func applyVertexAI(
        draft: [String: AnyCodable],
        modelID: String,
        controls: inout GenerationControls,
        providerSpecific: inout [String: AnyCodable]
    ) {
        if let raw = draft["generationConfig"]?.value {
            if let dict = raw as? [String: Any] {
                applyVertexAIGenerationConfig(dict, modelID: modelID, controls: &controls, providerSpecific: &providerSpecific)
            }
        } else {
            controls.temperature = nil
            controls.maxTokens = nil
            controls.topP = nil
            controls.reasoning = nil
            controls.imageGeneration = nil
        }

        if let raw = draft["tools"]?.value {
            let canPromote = applyGoogleSearchTools(raw, key: "googleSearch", controls: &controls)
            if canPromote {
                providerSpecific.removeValue(forKey: "tools")
            }
        } else {
            controls.webSearch = nil
        }
    }

    private static func applyCerebras(
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
                // Matches the app's default; promote to UI.
                var reasoning = controls.reasoning ?? ReasoningControls(enabled: true)
                reasoning.enabled = true
                controls.reasoning = reasoning
                providerSpecific.removeValue(forKey: "reasoning_format")
            case "":
                // Treat empty string as clearing the override (use provider default).
                providerSpecific.removeValue(forKey: "reasoning_format")
            default:
                // Keep as provider override (e.g., raw/hidden).
                break
            }
        }
    }

    private static func applyFireworks(
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

    private static func applyPerplexity(
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

            // Backwards compatibility: accept web_search_options.disable_search if present.
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
            // Explicitly enabled: fall back to provider default (search on).
            controls.webSearch = nil
        } else if promotedDisableSearch != nil || promotedContextSize != nil {
            let isDisabled = promotedDisableSearch == true
            controls.webSearch = WebSearchControls(enabled: !isDisabled, contextSize: promotedContextSize, sources: nil)
        } else if !hasDisableSearchKey && hasWebSearchOptionsKey {
            // web_search_options is present (e.g. other search fields), but nothing is promoted into UI state.
            controls.webSearch = nil
        } else if !hasDisableSearchKey && !hasWebSearchOptionsKey {
            controls.webSearch = nil
        }
    }

    // MARK: - OpenAI helpers

    private static func applyOpenAIReasoning(_ dict: [String: Any], controls: inout GenerationControls) -> Bool {
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

        controls.reasoning = ReasoningControls(
            enabled: true,
            effort: effort,
            budgetTokens: nil,
            summary: summary ?? .auto
        )

        return isSimple && (summaryString == nil || summary != nil)
    }

    private static func applyOpenAIWebSearchTools(
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

        // Promote to UI only if this is purely the UI-managed web_search tool (no extras).
        return found && nonWebSearchToolCount == 0 && canPromoteToUI
    }

    private static func mapOpenAIEffort(_ effort: ReasoningEffort) -> String {
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

    private static func parseOpenAIEffort(_ raw: String) -> ReasoningEffort? {
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

    private static func parseReasoningSummary(_ raw: String) -> ReasoningSummary? {
        ReasoningSummary(rawValue: raw.lowercased())
    }

    // MARK: - Anthropic helpers

    private static func applyAnthropicThinking(_ dict: [String: Any], modelID: String, controls: inout GenerationControls) -> Bool {
        let knownKeys: Set<String> = ["type", "budget_tokens"]
        let isSimple = Set(dict.keys).isSubset(of: knownKeys)

        let typeRaw = dict["type"] as? String
        let type = typeRaw?.lowercased()
        let budgetTokens = dict["budget_tokens"].flatMap(intValue(from:))

        var reasoning = controls.reasoning ?? ReasoningControls(enabled: true)
        reasoning.enabled = true

        switch type {
        case "adaptive":
            reasoning.budgetTokens = nil
        case "enabled", nil:
            reasoning.budgetTokens = budgetTokens
        default:
            reasoning.budgetTokens = budgetTokens
        }

        // If model supports effort control and budget isn't being used, keep any existing effort.
        if AnthropicModelLimits.supportsEffort(for: modelID), reasoning.budgetTokens != nil {
            reasoning.effort = nil
        }

        reasoning.summary = nil
        controls.reasoning = reasoning

        guard isSimple, typeRaw != nil else { return false }
        guard type == "adaptive" || type == "enabled" else { return false }
        if dict["budget_tokens"] != nil, budgetTokens == nil {
            return false
        }

        return true
    }

    private static func applyAnthropicOutputConfig(
        _ dict: [String: Any],
        modelID: String,
        controls: inout GenerationControls,
        providerSpecific: inout [String: AnyCodable]
    ) {
        guard AnthropicModelLimits.supportsEffort(for: modelID) else { return }

        var remaining = dict
        if let effortString = dict["effort"] as? String,
           let effort = parseAnthropicEffort(effortString) {
            var reasoning = controls.reasoning ?? ReasoningControls(enabled: true)
            reasoning.enabled = true
            reasoning.effort = effort
            reasoning.budgetTokens = nil
            reasoning.summary = nil
            controls.reasoning = reasoning

            remaining.removeValue(forKey: "effort")
        }

        if remaining.isEmpty {
            providerSpecific.removeValue(forKey: "output_config")
        } else {
            providerSpecific["output_config"] = AnyCodable(remaining)
        }
    }

    private static func applyAnthropicWebSearchTools(
        _ raw: Any,
        controls: inout GenerationControls
    ) -> Bool {
        guard let array = raw as? [Any] else { return false }

        let webSearchTypes: Set<String> = ["web_search_20250305"]
        var found = false
        var nonSearchToolCount = 0
        var canPromoteToUI = (array.count == 1)

        for item in array {
            guard let dict = item as? [String: Any] else {
                nonSearchToolCount += 1
                canPromoteToUI = false
                continue
            }

            if let type = dict["type"] as? String, webSearchTypes.contains(type) {
                found = true

                let knownKeys: Set<String> = ["type", "name"]
                if !Set(dict.keys).isSubset(of: knownKeys) {
                    canPromoteToUI = false
                }

                if let name = dict["name"] as? String, name != "web_search" {
                    canPromoteToUI = false
                }
            } else {
                nonSearchToolCount += 1
                canPromoteToUI = false
            }
        }

        controls.webSearch = found ? WebSearchControls(enabled: true) : nil

        return found && nonSearchToolCount == 0 && canPromoteToUI
    }

    private static func mapAnthropicEffort(_ effort: ReasoningEffort, modelID: String) -> String {
        switch effort {
        case .none:
            return "high"
        case .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .xhigh:
            return AnthropicModelLimits.supportsMaxEffort(for: modelID) ? "max" : "high"
        }
    }

    private static func parseAnthropicEffort(_ raw: String) -> ReasoningEffort? {
        switch raw.lowercased() {
        case "low":
            return .low
        case "medium":
            return .medium
        case "high":
            return .high
        case "max":
            return .xhigh
        default:
            return nil
        }
    }

    // MARK: - Gemini helpers

    private static func makeGeminiGenerationConfig(controls: GenerationControls, modelID: String) -> [String: Any] {
        var config: [String: Any] = [:]
        let isImageModel = isGeminiImageModel(modelID)

        if let temperature = controls.temperature {
            config["temperature"] = temperature
        }
        if let maxTokens = controls.maxTokens {
            config["maxOutputTokens"] = maxTokens
        }
        if let topP = controls.topP {
            config["topP"] = topP
        }

        if geminiSupportsThinking(modelID), let reasoning = controls.reasoning {
            if reasoning.enabled {
                var thinkingConfig: [String: Any] = [
                    "includeThoughts": true
                ]

                if let effort = reasoning.effort {
                    thinkingConfig["thinkingLevel"] = mapEffortToGeminiThinkingLevel(effort, modelID: modelID)
                } else if let budget = reasoning.budgetTokens {
                    thinkingConfig["thinkingBudget"] = budget
                }

                config["thinkingConfig"] = thinkingConfig
            } else if isGemini3Model(modelID) {
                config["thinkingConfig"] = [
                    "thinkingLevel": defaultGeminiThinkingLevelWhenOff(modelID: modelID)
                ]
            }
        }

        if isImageModel, let imageControls = controls.imageGeneration {
            let responseMode = imageControls.responseMode ?? .textAndImage
            config["responseModalities"] = responseMode.responseModalities

            if let seed = imageControls.seed {
                config["seed"] = seed
            }

            var imageConfig: [String: Any] = [:]
            if let aspectRatio = imageControls.aspectRatio {
                imageConfig["aspectRatio"] = aspectRatio.rawValue
            }
            if isGemini3ProImageModel(modelID), let imageSize = imageControls.imageSize {
                imageConfig["imageSize"] = imageSize.rawValue
            }
            if !imageConfig.isEmpty {
                config["imageConfig"] = imageConfig
            }
        }

        return config
    }

    private static func applyGeminiGenerationConfig(
        _ dict: [String: Any],
        modelID: String,
        controls: inout GenerationControls,
        providerSpecific: inout [String: AnyCodable]
    ) {
        let remaining = applyGoogleStyleGenerationConfig(
            dict,
            defaultLevelWhenOff: defaultGeminiThinkingLevelWhenOff(modelID: modelID),
            isImageModel: isGeminiImageModel(modelID),
            controls: &controls,
            applyImageConfig: { imageDict, ctrl in
                applyGeminiImageConfig(imageDict, modelID: modelID, controls: &ctrl)
            }
        )

        if remaining.isEmpty {
            providerSpecific.removeValue(forKey: "generationConfig")
        } else {
            providerSpecific["generationConfig"] = AnyCodable(remaining)
        }
    }

    private static func applyGeminiImageConfig(_ dict: [String: Any], modelID: String, controls: inout GenerationControls) {
        var image = controls.imageGeneration ?? ImageGenerationControls()

        if let aspect = dict["aspectRatio"] as? String, let ratio = ImageAspectRatio(rawValue: aspect) {
            image.aspectRatio = ratio
        }

        if isGemini3ProImageModel(modelID),
           let sizeString = dict["imageSize"] as? String,
           let size = ImageOutputSize(rawValue: sizeString) {
            image.imageSize = size
        }

        controls.imageGeneration = image.isEmpty ? nil : image
    }

    private static func geminiSupportsGoogleSearch(_ modelID: String) -> Bool {
        !modelID.lowercased().contains("gemini-2.5-flash-image")
    }

    private static func geminiSupportsThinking(_ modelID: String) -> Bool {
        !modelID.lowercased().contains("gemini-2.5-flash-image")
    }

    private static func isGemini3Model(_ modelID: String) -> Bool {
        modelID.lowercased().contains("gemini-3")
    }

    private static func isGeminiImageModel(_ modelID: String) -> Bool {
        modelID.lowercased().contains("-image")
    }

    private static func isGemini3ProImageModel(_ modelID: String) -> Bool {
        modelID.lowercased().contains("gemini-3-pro-image")
    }

    private static func defaultGeminiThinkingLevelWhenOff(modelID: String) -> String {
        let lower = modelID.lowercased()
        if lower.contains("gemini-3-pro") {
            return "LOW"
        }
        return "MINIMAL"
    }

    private static func mapEffortToGeminiThinkingLevel(_ effort: ReasoningEffort, modelID: String) -> String {
        let lower = modelID.lowercased()
        let isPro = lower.contains("gemini-3-pro")

        switch effort {
        case .none, .minimal:
            return isPro ? "LOW" : "MINIMAL"
        case .low:
            return "LOW"
        case .medium:
            return isPro ? "HIGH" : "MEDIUM"
        case .high, .xhigh:
            return "HIGH"
        }
    }

    // MARK: - Vertex helpers

    private static func makeVertexAIGenerationConfig(controls: GenerationControls, modelID: String) -> [String: Any] {
        var config: [String: Any] = [:]
        let isImageModel = isVertexImageModel(modelID)

        if let temperature = controls.temperature {
            config["temperature"] = temperature
        }
        if let maxTokens = controls.maxTokens {
            config["maxOutputTokens"] = maxTokens
        }
        if let topP = controls.topP {
            config["topP"] = topP
        }

        if vertexSupportsThinking(modelID), let reasoning = controls.reasoning, reasoning.enabled {
            var thinkingConfig: [String: Any] = [
                "includeThoughts": true
            ]

            if let effort = reasoning.effort {
                thinkingConfig["thinkingLevel"] = mapEffortToVertexThinkingLevel(effort)
            } else if let budget = reasoning.budgetTokens {
                thinkingConfig["thinkingBudget"] = budget
            }

            config["thinkingConfig"] = thinkingConfig
        }

        if isImageModel, let imageControls = controls.imageGeneration {
            let responseMode = imageControls.responseMode ?? .textAndImage
            config["responseModalities"] = responseMode.responseModalities

            if let seed = imageControls.seed {
                config["seed"] = seed
            }

            var imageConfig: [String: Any] = [:]
            if let aspectRatio = imageControls.aspectRatio {
                imageConfig["aspectRatio"] = aspectRatio.rawValue
            }
            if isVertexGemini3ProImageModel(modelID), let imageSize = imageControls.imageSize {
                imageConfig["imageSize"] = imageSize.rawValue
            }
            if let person = imageControls.vertexPersonGeneration {
                imageConfig["personGeneration"] = person.rawValue
            }

            var imageOutputOptions: [String: Any] = [:]
            if let mime = imageControls.vertexOutputMIMEType {
                imageOutputOptions["mimeType"] = mime.rawValue
            }
            if let quality = imageControls.vertexCompressionQuality {
                imageOutputOptions["compressionQuality"] = min(100, max(0, quality))
            }
            if !imageOutputOptions.isEmpty {
                imageConfig["imageOutputOptions"] = imageOutputOptions
            }

            if !imageConfig.isEmpty {
                config["imageConfig"] = imageConfig
            }
        }

        return config
    }

    private static func applyVertexAIGenerationConfig(
        _ dict: [String: Any],
        modelID: String,
        controls: inout GenerationControls,
        providerSpecific: inout [String: AnyCodable]
    ) {
        let remaining = applyGoogleStyleGenerationConfig(
            dict,
            defaultLevelWhenOff: "MINIMAL",
            isImageModel: isVertexImageModel(modelID),
            controls: &controls,
            applyImageConfig: { imageDict, ctrl in
                applyVertexImageConfig(imageDict, modelID: modelID, controls: &ctrl)
            }
        )

        if remaining.isEmpty {
            providerSpecific.removeValue(forKey: "generationConfig")
        } else {
            providerSpecific["generationConfig"] = AnyCodable(remaining)
        }
    }

    private static func applyVertexImageConfig(_ dict: [String: Any], modelID: String, controls: inout GenerationControls) {
        var image = controls.imageGeneration ?? ImageGenerationControls()

        if let aspect = dict["aspectRatio"] as? String, let ratio = ImageAspectRatio(rawValue: aspect) {
            image.aspectRatio = ratio
        }

        if isVertexGemini3ProImageModel(modelID),
           let sizeString = dict["imageSize"] as? String,
           let size = ImageOutputSize(rawValue: sizeString) {
            image.imageSize = size
        }

        if let personString = dict["personGeneration"] as? String,
           let person = VertexImagePersonGeneration(rawValue: personString) {
            image.vertexPersonGeneration = person
        }

        if let outputOptions = dict["imageOutputOptions"] as? [String: Any] {
            if let mimeString = outputOptions["mimeType"] as? String,
               let mime = VertexImageOutputMIMEType(rawValue: mimeString) {
                image.vertexOutputMIMEType = mime
            }
            if let qualityRaw = outputOptions["compressionQuality"], let quality = intValue(from: qualityRaw) {
                image.vertexCompressionQuality = quality
            }
        }

        controls.imageGeneration = image.isEmpty ? nil : image
    }

    private static func vertexSupportsGoogleSearch(_ modelID: String) -> Bool {
        !modelID.lowercased().contains("gemini-2.5-flash-image")
    }

    private static func vertexSupportsThinking(_ modelID: String) -> Bool {
        !modelID.lowercased().contains("gemini-2.5-flash-image")
    }

    private static func isVertexImageModel(_ modelID: String) -> Bool {
        isGeminiImageModel(modelID)
    }

    private static func isVertexGemini3ProImageModel(_ modelID: String) -> Bool {
        isGemini3ProImageModel(modelID)
    }

    private static func mapEffortToVertexThinkingLevel(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none, .minimal:
            return "MINIMAL"
        case .low:
            return "LOW"
        case .medium:
            return "MEDIUM"
        case .high, .xhigh:
            return "HIGH"
        }
    }

    // MARK: - Shared Google-style Generation Config

    /// Shared logic for Gemini and VertexAI generation config application.
    /// Returns the remaining (unrecognized) keys for providerSpecific passthrough.
    private static func applyGoogleStyleGenerationConfig(
        _ dict: [String: Any],
        defaultLevelWhenOff: String,
        isImageModel: Bool,
        controls: inout GenerationControls,
        applyImageConfig: (([String: Any], inout GenerationControls) -> Void)?
    ) -> [String: Any] {
        var remaining = dict

        if let raw = dict["temperature"], let value = doubleValue(from: raw) {
            controls.temperature = value
            remaining.removeValue(forKey: "temperature")
        } else {
            controls.temperature = nil
        }

        if let raw = dict["maxOutputTokens"], let value = intValue(from: raw) {
            controls.maxTokens = value
            remaining.removeValue(forKey: "maxOutputTokens")
        } else {
            controls.maxTokens = nil
        }

        if let raw = dict["topP"], let value = doubleValue(from: raw) {
            controls.topP = value
            remaining.removeValue(forKey: "topP")
        } else {
            controls.topP = nil
        }

        if let raw = dict["thinkingConfig"] as? [String: Any] {
            applyThinkingConfig(
                raw,
                defaultLevelWhenOff: defaultLevelWhenOff,
                controls: &controls
            )
            remaining.removeValue(forKey: "thinkingConfig")
        } else {
            controls.reasoning = nil
        }

        if let raw = dict["responseModalities"] as? [Any] {
            applyResponseModalities(raw, controls: &controls)
            remaining.removeValue(forKey: "responseModalities")
        } else if isImageModel {
            controls.imageGeneration = nil
        }

        if let raw = dict["seed"], let value = intValue(from: raw) {
            var image = controls.imageGeneration ?? ImageGenerationControls()
            image.seed = value
            controls.imageGeneration = image
            remaining.removeValue(forKey: "seed")
        }

        if let raw = dict["imageConfig"] as? [String: Any] {
            applyImageConfig?(raw, &controls)
            remaining.removeValue(forKey: "imageConfig")
        }

        return remaining
    }

    // MARK: - Shared helpers

    private static func applyThinkingConfig(
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

    private static func parseThinkingLevel(_ raw: String) -> ReasoningEffort? {
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

    private static func applyResponseModalities(_ array: [Any], controls: inout GenerationControls) {
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

    private static func applyGoogleSearchTools(
        _ raw: Any,
        key: String,
        controls: inout GenerationControls
    ) -> Bool {
        guard let array = raw as? [Any] else { return false }

        var found = false
        var nonSearchToolCount = 0
        var canPromoteToUI = (array.count == 1)

        for item in array {
            guard let dict = item as? [String: Any] else {
                nonSearchToolCount += 1
                canPromoteToUI = false
                continue
            }

            if let configValue = dict[key] {
                found = true

                if dict.keys.count != 1 {
                    canPromoteToUI = false
                }

                if let config = configValue as? [String: Any], !config.isEmpty {
                    canPromoteToUI = false
                } else if let config = configValue as? [String: AnyCodable], !config.isEmpty {
                    canPromoteToUI = false
                } else if !(configValue is [String: Any]) && !(configValue is [String: AnyCodable]) {
                    // Unknown/non-dictionary config; keep as provider override.
                    canPromoteToUI = false
                }
            } else {
                nonSearchToolCount += 1
                canPromoteToUI = false
            }
        }

        controls.webSearch = found ? WebSearchControls(enabled: true) : nil

        return found && nonSearchToolCount == 0 && canPromoteToUI
    }

    private static func mergeProviderSpecific(
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

        case .openai, .cerebras, .fireworks, .openaiCompatible, .openrouter, .groq, .cohere, .mistral, .deepinfra, .xai, .deepseek, .none:
            for (key, value) in additional {
                base[key] = value
            }
        }
    }

    private static func deepMerge(into base: inout [String: Any], additional: [String: Any]) {
        for (key, value) in additional {
            if var baseDict = base[key] as? [String: Any], let addDict = value as? [String: Any] {
                deepMerge(into: &baseDict, additional: addDict)
                base[key] = baseDict
            } else {
                base[key] = value
            }
        }
    }

    private static func mapFireworksEffort(_ effort: ReasoningEffort) -> String {
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

    private static func parseFireworksEffort(_ raw: String) -> ReasoningEffort? {
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

    private static func isFireworksMiniMaxM2FamilyModel(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return lower.hasPrefix("fireworks/minimax-m2")
            || lower.hasPrefix("accounts/fireworks/models/minimax-m2")
    }

    private static func supportedFireworksReasoningHistoryValues(for modelID: String) -> Set<String> {
        if isFireworksMiniMaxM2FamilyModel(modelID) {
            return ["interleaved", "disabled"]
        }

        let lower = modelID.lowercased()
        if lower == "fireworks/kimi-k2p5"
            || lower == "accounts/fireworks/models/kimi-k2p5"
            || lower == "fireworks/glm-4p7"
            || lower == "accounts/fireworks/models/glm-4p7"
            || lower == "fireworks/glm-5"
            || lower == "accounts/fireworks/models/glm-5" {
            return ["preserved", "interleaved", "disabled"]
        }

        return []
    }

    private static func mapPerplexityEffort(_ effort: ReasoningEffort) -> String? {
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

    private static func parsePerplexityEffort(_ raw: String) -> ReasoningEffort? {
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

    private static func doubleValue(from raw: Any) -> Double? {
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

    private static func intValue(from raw: Any) -> Int? {
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
