import Foundation

enum XAIResponsesRequestSupport {
    private static let reasoningEffortModelIDs: Set<String> = [
        "grok-3-mini",
    ]
    private static let multiAgentReasoningModelIDs: Set<String> = [
        "grok-4.20-multi-agent",
        "grok-4.20-multi-agent-0309",
    ]
    /// Models that accept `reasoning: {"effort": ...}` with low/medium/high only
    /// (docs.x.ai: grok-4.5 reasoning is always-on and rejects none).
    private static let standardReasoningEffortModelIDs: Set<String> = [
        "grok-4.5",
    ]
    /// Models that accept `reasoning.effort` including `"none"` (docs.x.ai migration guide
    /// for grok-4.3: none/low/medium/high). grok-build-0.1 is treated the same for safety.
    private static let standardReasoningEffortWithNoneModelIDs: Set<String> = [
        "grok-4.3",
        "grok-build-0.1",
    ]
    private static let clientFunctionToolsModelIDs: Set<String> = [
        "grok-4",
        "grok-4.3",
        "grok-4.5",
        "grok-4.20",
        "grok-4.20-0309-reasoning",
        "grok-4.20-0309-non-reasoning",
        "grok-build-0.1",
        "grok-4-1",
        "grok-4-1-fast",
        "grok-4-1-fast-non-reasoning",
        "grok-4-1-fast-reasoning",
    ]
    private static let maxOutputTokensModelIDs: Set<String> = [
        "grok-4",
        "grok-4.3",
        "grok-4.5",
        "grok-4.20",
        "grok-4.20-0309-reasoning",
        "grok-4.20-0309-non-reasoning",
        "grok-build-0.1",
        "grok-4-1",
        "grok-4-1-fast",
        "grok-4-1-fast-non-reasoning",
        "grok-4-1-fast-reasoning",
    ]

    static func responsesBody(
        modelID: String,
        input: [[String: Any]],
        streaming: Bool,
        controls: GenerationControls,
        functionTools: [[String: Any]],
        supportsWebSearch: Bool,
        supportsClientFunctionTools: Bool
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": modelID,
            "input": input,
            "stream": streaming
        ]

        applyContextCacheControls(to: &body, controls: controls)
        applySamplingControls(to: &body, controls: controls, modelID: modelID)
        applyReasoningConfig(to: &body, controls: controls, modelID: modelID)

        let codeExecutionEnabled = controls.codeExecution?.enabled == true
        let toolObjects = toolObjects(
            controls: controls,
            functionTools: functionTools,
            supportsWebSearch: supportsWebSearch,
            codeExecutionEnabled: codeExecutionEnabled,
            supportsClientFunctionTools: supportsClientFunctionTools
        )
        if !toolObjects.isEmpty {
            body["tools"] = toolObjects
        }

        applyXSearchOnlyToolChoice(to: &body, controls: controls, toolObjects: toolObjects)
        applyRequiredIncludeFields(to: &body, codeExecutionEnabled: codeExecutionEnabled)
        applyProviderSpecificOverrides(to: &body, controls: controls, modelID: modelID)

        return body
    }

    static func additionalHeaders(controls: GenerationControls) -> [String: String] {
        guard controls.contextCache?.mode != .off,
              let conversationID = normalizedTrimmedString(controls.contextCache?.conversationID) else {
            return [:]
        }

        return ["x-grok-conv-id": conversationID]
    }

    static func applyContextCacheControls(
        to body: inout [String: Any],
        controls: GenerationControls
    ) {
        guard controls.contextCache?.mode != .off else { return }

        if let cacheKey = normalizedTrimmedString(controls.contextCache?.cacheKey) {
            body["prompt_cache_key"] = cacheKey
        }
        if let retention = controls.contextCache?.ttl?.providerTTLString {
            body["prompt_cache_retention"] = retention
        }
        if let minTokens = controls.contextCache?.minTokensThreshold, minTokens > 0 {
            body["prompt_cache_min_tokens"] = minTokens
        }
    }

    static func applySamplingControls(
        to body: inout [String: Any],
        controls: GenerationControls,
        modelID: String
    ) {
        if let temperature = controls.temperature {
            body["temperature"] = temperature
        }
        if let maxTokens = controls.maxTokens, supportsMaxOutputTokens(modelID: modelID) {
            body["max_output_tokens"] = maxTokens
        }
        if let topP = controls.topP {
            body["top_p"] = topP
        }
    }

    static func applyReasoningConfig(
        to body: inout [String: Any],
        controls: GenerationControls,
        modelID: String
    ) {
        if supportsMultiAgentReasoning(modelID: modelID) {
            guard let reasoning = controls.reasoning, reasoning.enabled else { return }
            let effort = reasoning.effort ?? .low
            body["reasoning"] = ["effort": mapMultiAgentReasoningEffort(effort)]
            return
        }

        if supportsStandardReasoningEffortWithNone(modelID: modelID) {
            // enabled=false → omit; effort none → explicit `"none"`.
            guard let reasoning = controls.reasoning, reasoning.enabled else { return }
            let effort = reasoning.effort ?? .none
            body["reasoning"] = ["effort": mapReasoningEffortNoneDisabled(effort)]
            return
        }

        if supportsStandardReasoningEffort(modelID: modelID) {
            // Always-on models (e.g. grok-4.5): emit effort even when controls are sparse.
            // Defaults to high per docs when effort is missing.
            let effort: ReasoningEffort
            if let reasoning = controls.reasoning, reasoning.enabled, let explicit = reasoning.effort {
                effort = explicit
            } else if controls.reasoning?.enabled == false {
                // Callers should not disable always-on models; clamp to low rather than omit.
                effort = .low
            } else {
                effort = .high
            }
            body["reasoning"] = ["effort": mapStandardReasoningEffort(effort)]
            return
        }

        if supportsReasoningEffort(modelID: modelID) {
            guard let reasoning = controls.reasoning,
                  reasoning.enabled,
                  let effort = reasoning.effort else {
                return
            }
            body["reasoning_effort"] = mapReasoningEffort(effort)
        }
    }

    static func toolObjects(
        controls: GenerationControls,
        functionTools: [[String: Any]],
        supportsWebSearch: Bool,
        codeExecutionEnabled: Bool,
        supportsClientFunctionTools: Bool
    ) -> [[String: Any]] {
        var toolObjects: [[String: Any]] = []

        if controls.webSearch?.enabled == true, supportsWebSearch {
            let sources = Set(controls.webSearch?.sources ?? [.web])

            if sources.contains(.web) {
                toolObjects.append(webSearchToolObject(from: controls.webSearch))
            }

            if sources.contains(.x) {
                toolObjects.append(xSearchToolObject(from: controls.webSearch))
            }
        }

        if codeExecutionEnabled {
            toolObjects.append(["type": "code_interpreter"])
        }

        if supportsClientFunctionTools, !functionTools.isEmpty {
            toolObjects.append(contentsOf: functionTools)
        }

        return toolObjects
    }

    /// Builds `web_search` with optional domain filters and image flags
    /// (docs.x.ai/developers/tools/web-search).
    static func webSearchToolObject(from controls: WebSearchControls?) -> [String: Any] {
        var tool: [String: Any] = ["type": "web_search"]

        let allowed = normalizedDomainList(controls?.allowedDomains, maxCount: 5)
        let excluded = normalizedDomainList(controls?.blockedDomains, maxCount: 5)
        // allowed and excluded cannot be set together.
        if !allowed.isEmpty {
            tool["filters"] = ["allowed_domains": allowed]
        } else if !excluded.isEmpty {
            tool["filters"] = ["excluded_domains": excluded]
        }

        if controls?.enableImageUnderstanding == true {
            tool["enable_image_understanding"] = true
        }
        if controls?.enableImageSearch == true {
            tool["enable_image_search"] = true
        }

        return tool
    }

    /// Builds `x_search` with optional handle filters, date range, and media understanding
    /// (docs.x.ai/developers/tools/x-search).
    static func xSearchToolObject(from controls: WebSearchControls?) -> [String: Any] {
        var tool: [String: Any] = ["type": "x_search"]

        let allowedHandles = normalizedHandleList(controls?.allowedXHandles, maxCount: 20)
        let excludedHandles = normalizedHandleList(controls?.excludedXHandles, maxCount: 20)
        if !allowedHandles.isEmpty {
            tool["allowed_x_handles"] = allowedHandles
        } else if !excludedHandles.isEmpty {
            tool["excluded_x_handles"] = excludedHandles
        }

        if let fromDate = normalizedISODate(controls?.xSearchFromDate) {
            tool["from_date"] = fromDate
        }
        if let toDate = normalizedISODate(controls?.xSearchToDate) {
            tool["to_date"] = toDate
        }

        if controls?.enableImageUnderstanding == true {
            tool["enable_image_understanding"] = true
        }
        if controls?.enableVideoUnderstanding == true {
            tool["enable_video_understanding"] = true
        }

        return tool
    }

    // Grok's auto-orchestrator often skips x_search even when it's the only enabled
    // built-in source. Force tool use in that narrow case so the model actually queries X.
    static func applyXSearchOnlyToolChoice(
        to body: inout [String: Any],
        controls: GenerationControls,
        toolObjects: [[String: Any]]
    ) {
        guard controls.webSearch?.enabled == true,
              Set(controls.webSearch?.sources ?? []) == [.x],
              toolObjects.count == 1,
              (toolObjects.first?["type"] as? String) == "x_search" else {
            return
        }
        body["tool_choice"] = "required"
    }

    static func applyRequiredIncludeFields(
        to body: inout [String: Any],
        codeExecutionEnabled: Bool
    ) {
        guard codeExecutionEnabled else { return }

        var includeFields = (body["include"] as? [String]) ?? []
        includeFields.append("code_interpreter_call.outputs")
        body["include"] = includeFields
    }

    static func applyProviderSpecificOverrides(
        to body: inout [String: Any],
        controls: GenerationControls,
        modelID: String? = nil
    ) {
        for (key, value) in controls.providerSpecific {
            if let modelID,
               key == "max_output_tokens" || key == "max_tokens" {
                if !supportsMaxOutputTokens(modelID: modelID) {
                    continue
                }
            }
            body[key] = value.value
        }
    }

    static func supportsReasoningEffort(modelID: String) -> Bool {
        reasoningEffortModelIDs.contains(modelID.lowercased())
    }

    static func supportsMultiAgentReasoning(modelID: String) -> Bool {
        multiAgentReasoningModelIDs.contains(modelID.lowercased())
    }

    static func supportsStandardReasoningEffort(modelID: String) -> Bool {
        standardReasoningEffortModelIDs.contains(modelID.lowercased())
    }

    static func supportsStandardReasoningEffortWithNone(modelID: String) -> Bool {
        standardReasoningEffortWithNoneModelIDs.contains(modelID.lowercased())
    }

    static func supportsClientFunctionTools(modelID: String) -> Bool {
        clientFunctionToolsModelIDs.contains(modelID.lowercased())
    }

    static func supportsMaxOutputTokens(modelID: String) -> Bool {
        maxOutputTokensModelIDs.contains(modelID.lowercased())
    }

    static func mapReasoningEffort(_ effort: ReasoningEffort) -> String {
        mapReasoningEffortNoneAsLow(effort)
    }

    /// Multi-agent effort maps 1:1 to API values: low/medium → 4 agents, high/xhigh → 16
    /// (docs.x.ai multi-agent).
    static func mapMultiAgentReasoningEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none, .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .xhigh, .max:
            return "xhigh"
        }
    }

    /// grok-4.5 accepts exactly low/medium/high (no none/xhigh); clamp everything else
    /// so an out-of-range persisted effort never produces a 400.
    static func mapStandardReasoningEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none, .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high, .xhigh, .max:
            return "high"
        }
    }

    // MARK: - Normalization helpers

    private static func normalizedDomainList(_ domains: [String]?, maxCount: Int) -> [String] {
        guard let domains else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for domain in domains {
            guard let trimmed = domain.trimmedNonEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
            if result.count >= maxCount { break }
        }
        return result
    }

    private static func normalizedHandleList(_ handles: [String]?, maxCount: Int) -> [String] {
        guard let handles else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for handle in handles {
            guard var trimmed = handle.trimmedNonEmpty else { continue }
            if trimmed.hasPrefix("@") {
                trimmed = String(trimmed.dropFirst())
            }
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
            if result.count >= maxCount { break }
        }
        return result
    }

    private static func normalizedISODate(_ raw: String?) -> String? {
        guard let raw = raw?.trimmedNonEmpty else { return nil }
        // Accept YYYY-MM-DD; reject other shapes so we never send invalid wire values.
        let parts = raw.split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        return raw
    }
}
