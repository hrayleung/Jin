import Foundation

enum XAIResponsesRequestSupport {
    private static let reasoningEffortModelIDs: Set<String> = [
        "grok-3-mini",
    ]
    private static let multiAgentReasoningModelIDs: Set<String> = [
        "grok-4.20-multi-agent",
        "grok-4.20-multi-agent-0309",
    ]
    private static let clientFunctionToolsModelIDs: Set<String> = [
        "grok-4",
        "grok-4.3",
        "grok-4.20",
        "grok-4-1",
        "grok-4-1-fast",
        "grok-4-1-fast-non-reasoning",
        "grok-4-1-fast-reasoning",
    ]
    private static let maxOutputTokensModelIDs: Set<String> = [
        "grok-4",
        "grok-4.3",
        "grok-4.20",
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
        guard let reasoning = controls.reasoning,
              reasoning.enabled,
              let effort = reasoning.effort else {
            return
        }

        if supportsMultiAgentReasoning(modelID: modelID) {
            body["reasoning"] = ["effort": mapMultiAgentReasoningEffort(effort)]
        } else if supportsReasoningEffort(modelID: modelID) {
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
                toolObjects.append(["type": "web_search"])
            }

            if sources.contains(.x) {
                toolObjects.append(["type": "x_search"])
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

    static func supportsClientFunctionTools(modelID: String) -> Bool {
        clientFunctionToolsModelIDs.contains(modelID.lowercased())
    }

    static func supportsMaxOutputTokens(modelID: String) -> Bool {
        maxOutputTokensModelIDs.contains(modelID.lowercased())
    }

    static func mapReasoningEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none, .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high, .xhigh, .max:
            return "high"
        }
    }

    static func mapMultiAgentReasoningEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .high, .xhigh, .max:
            return "high"
        case .none, .minimal, .low, .medium:
            return "low"
        }
    }
}
