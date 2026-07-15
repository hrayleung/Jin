import Foundation

enum OpenAIResponsesRequestSupport {
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
    }

    static func applySamplingControls(
        to body: inout [String: Any],
        controls: GenerationControls,
        supportsSamplingParameters: Bool
    ) {
        guard supportsSamplingParameters else { return }

        if let temperature = controls.temperature {
            body["temperature"] = temperature
        }
        if let topP = controls.topP {
            body["top_p"] = topP
        }
    }

    static func applyReasoningConfig(
        to body: inout [String: Any],
        controls: GenerationControls,
        providerType: ProviderType?,
        modelID: String,
        reasoningEnabled: Bool,
        reasoningEffort: ReasoningEffort?
    ) {
        // When reasoning is Off, omit the entire `reasoning` object so persisted
        // summary/mode/context cannot re-enable or alter reasoning behavior.
        if reasoningEnabled {
            var reasoningDict: [String: Any] = [:]

            if let reasoningEffort {
                reasoningDict["effort"] = mappedReasoningEffort(
                    reasoningEffort,
                    providerType: providerType,
                    modelID: modelID
                )
            }
            if let summary = controls.reasoning?.summary {
                reasoningDict["summary"] = summary.rawValue
            }

            // GPT-5.6 Pro mode: `reasoning.mode = "pro"` (independent of effort level).
            if ModelCapabilityRegistry.supportsOpenAIStyleProMode(for: providerType, modelID: modelID),
               controls.reasoning?.mode == .pro {
                reasoningDict["mode"] = "pro"
            }

            // Multi-turn reasoning reuse: only when the model accepts `reasoning.context`.
            if ModelCapabilityRegistry.supportsOpenAIStyleReasoningContext(for: providerType, modelID: modelID),
               let context = controls.reasoning?.context {
                reasoningDict["context"] = context.rawValue
            }

            if !reasoningDict.isEmpty {
                body["reasoning"] = reasoningDict
            }
        }

        // Verbosity is independent of reasoning on/off.
        applyTextVerbosity(to: &body, controls: controls, providerType: providerType, modelID: modelID)
    }

    static func applyTextVerbosity(
        to body: inout [String: Any],
        controls: GenerationControls,
        providerType: ProviderType?,
        modelID: String
    ) {
        guard ModelCapabilityRegistry.supportsOpenAIStyleVerbosity(for: providerType, modelID: modelID),
              let verbosity = controls.textVerbosity else {
            return
        }

        var textDict = body["text"] as? [String: Any] ?? [:]
        textDict["verbosity"] = verbosity.rawValue
        body["text"] = textDict
    }

    static func toolObjects(
        controls: GenerationControls,
        functionTools: [[String: Any]],
        supportsWebSearch: Bool,
        codeExecutionEnabled: Bool
    ) -> [[String: Any]] {
        var toolObjects: [[String: Any]] = []

        if controls.webSearch?.enabled == true, supportsWebSearch {
            var webSearchTool: [String: Any] = ["type": "web_search"]
            if let contextSize = controls.webSearch?.contextSize {
                webSearchTool["search_context_size"] = contextSize.rawValue
            }
            toolObjects.append(webSearchTool)
        }

        if codeExecutionEnabled {
            toolObjects.append(codeInterpreterTool(from: controls.codeExecution))
        }

        toolObjects.append(contentsOf: functionTools)
        return toolObjects
    }

    static func applyProviderSpecificOverrides(
        to body: inout [String: Any],
        controls: GenerationControls,
        supportsSamplingParameters: Bool
    ) {
        for (key, value) in controls.providerSpecific {
            guard key != "prompt_cache_min_tokens", key != "service_tier" else {
                continue
            }
            if !supportsSamplingParameters, key == "temperature" || key == "top_p" {
                continue
            }
            body[key] = value.value
        }
    }

    static func applyRequiredIncludeFields(
        to body: inout [String: Any],
        webSearchEnabled: Bool,
        codeExecutionEnabled: Bool
    ) {
        if webSearchEnabled {
            body["include"] = mergedIncludeFields(
                body["include"],
                adding: "web_search_call.action.sources"
            )
        }

        if codeExecutionEnabled {
            body["include"] = mergedIncludeFields(
                body["include"],
                adding: "code_interpreter_call.outputs"
            )
        }
    }

    static func mergedIncludeFields(_ existing: Any?, adding field: String) -> [String] {
        let existingStrings: [String]
        if let strings = existing as? [String] {
            existingStrings = strings
        } else if let anyArray = existing as? [Any] {
            existingStrings = anyArray.compactMap { $0 as? String }
        } else {
            existingStrings = []
        }

        var out: [String] = []
        var seen: Set<String> = []
        for raw in existingStrings + [field] {
            guard let trimmed = raw.trimmedNonEmpty, seen.insert(trimmed).inserted else { continue }
            out.append(trimmed)
        }
        return out
    }

    static func mappedReasoningEffort(
        _ effort: ReasoningEffort,
        providerType: ProviderType?,
        modelID: String
    ) -> String {
        let normalized = ModelCapabilityRegistry.normalizedReasoningEffort(
            effort,
            for: providerType,
            modelID: modelID
        )

        switch normalized {
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
        case .max:
            // `max` is a real API value starting with GPT-5.6; older models reject it.
            return ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(for: providerType, modelID: modelID)
                ? "max"
                : "xhigh"
        }
    }

    static func codeInterpreterTool(from controls: CodeExecutionControls?) -> [String: Any] {
        var codeInterpreterTool: [String: Any] = ["type": "code_interpreter"]
        let openAISettings = controls?.openAI?.normalized()

        if let existingContainerID = openAISettings?.normalizedExistingContainerID {
            codeInterpreterTool["container"] = existingContainerID
            return codeInterpreterTool
        }

        let containerConfig = openAISettings?.container?.normalized()
        var container: [String: Any] = ["type": containerConfig?.normalizedType ?? "auto"]

        if let memoryLimit = containerConfig?.normalizedMemoryLimit {
            container["memory_limit"] = memoryLimit
        }
        if let fileIDs = containerConfig?.normalizedFileIDs, !fileIDs.isEmpty {
            container["file_ids"] = fileIDs
        }

        codeInterpreterTool["container"] = container
        return codeInterpreterTool
    }
}
