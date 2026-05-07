import Foundation

enum GeminiRequestSupport {
    static func generationConfig(
        controls: GenerationControls,
        modelID: String
    ) -> [String: Any] {
        var config: [String: Any] = [:]
        addSamplingControls(to: &config, controls: controls)
        addThinkingConfig(to: &config, controls: controls, modelID: modelID)
        addImageConfig(to: &config, controls: controls, modelID: modelID)
        return config
    }

    static func systemInstructionText(from messages: [Message]) -> String? {
        let text = messages
            .filter { $0.role == .system }
            .flatMap(\.content)
            .compactMap { part -> String? in
                if case .text(let text) = part { return text }
                return nil
            }
            .joined()
            .trimmedNonEmpty

        return text
    }

    static func explicitCachedContentName(from controls: GenerationControls) -> String? {
        guard controls.contextCache?.mode == .explicit else { return nil }
        return normalizedTrimmedString(controls.contextCache?.cachedContentName)
    }

    static func normalizedCachedContentName(_ raw: String) -> String {
        let trimmed = raw.trimmed
        if trimmed.lowercased().hasPrefix("cachedcontents/") {
            return trimmed
        }
        return "cachedContents/\(trimmed)"
    }

    static func toolArray(
        controls: GenerationControls,
        functionDeclarations: [[String: Any]],
        supportsWebSearch: Bool,
        supportsCodeExecution: Bool,
        supportsGoogleMaps: Bool,
        supportsFunctionCalling: Bool
    ) -> [[String: Any]] {
        var toolArray: [[String: Any]] = []

        if controls.webSearch?.enabled == true, supportsWebSearch {
            toolArray.append(["google_search": [:]])
        }

        if controls.codeExecution?.enabled == true, supportsCodeExecution {
            toolArray.append(["code_execution": [:]])
        }

        if controls.googleMaps?.enabled == true, supportsGoogleMaps {
            var mapsConfig: [String: Any] = [:]
            if controls.googleMaps?.enableWidget == true {
                mapsConfig["enableWidget"] = true
            }
            toolArray.append(["googleMaps": mapsConfig])
        }

        if supportsFunctionCalling, !functionDeclarations.isEmpty {
            toolArray.append(["functionDeclarations": functionDeclarations])
        }

        return toolArray
    }

    static func toolConfig(
        controls: GenerationControls,
        supportsGoogleMaps: Bool
    ) -> [String: Any]? {
        guard controls.googleMaps?.enabled == true, supportsGoogleMaps else {
            return nil
        }

        var retrievalConfig: [String: Any] = [:]

        if let lat = controls.googleMaps?.latitude,
           let lng = controls.googleMaps?.longitude {
            retrievalConfig["latLng"] = [
                "latitude": lat,
                "longitude": lng
            ]
        }

        guard !retrievalConfig.isEmpty else { return nil }
        return ["retrievalConfig": retrievalConfig]
    }

    static func functionDeclarations(from tools: [ToolDefinition]) -> [[String: Any]] {
        tools.map(functionDeclaration)
    }

    static func modelIDForPath(_ modelID: String) -> String {
        let trimmed = modelID.trimmed
        if trimmed.lowercased().hasPrefix("models/") {
            return String(trimmed.dropFirst("models/".count))
        }
        return trimmed
    }

    static func supportsFunctionCalling(_ modelID: String) -> Bool {
        // Gemini image-generation models do not support function calling.
        !GeminiModelConstants.isImageGenerationModel(modelID)
    }

    static func supportsImageSize(_ modelID: String) -> Bool {
        // imageSize is documented for Gemini 3 Pro Image and Gemini 3.1 Flash Image.
        let lower = modelID.lowercased()
        return lower == "gemini-3-pro-image-preview" || lower == "gemini-3.1-flash-image-preview"
    }

    static func supportsImageSize(_ modelID: String, imageSize: ImageOutputSize) -> Bool {
        guard supportsImageSize(modelID) else { return false }
        let lower = modelID.lowercased()
        if lower == "gemini-3-pro-image-preview" {
            return imageSize != .size512px
        }
        return true
    }

    static func supportsThinking(_ modelID: String) -> Bool {
        modelID.lowercased() != "gemini-2.5-flash-image"
    }

    static func supportsThinkingConfig(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return supportsThinking(modelID) && lower != "gemini-3-pro-image-preview"
    }

    static func supportsThinkingLevel(_ modelID: String) -> Bool {
        supportsThinkingConfig(modelID)
    }

    private static func addSamplingControls(to config: inout [String: Any], controls: GenerationControls) {
        if let temperature = controls.temperature {
            config["temperature"] = temperature
        }
        if let maxTokens = controls.maxTokens {
            config["maxOutputTokens"] = maxTokens
        }
        if let topP = controls.topP {
            config["topP"] = topP
        }
    }

    private static func addThinkingConfig(
        to config: inout [String: Any],
        controls: GenerationControls,
        modelID: String
    ) {
        if supportsThinkingConfig(modelID), let reasoning = controls.reasoning {
            if reasoning.enabled {
                var thinkingConfig: [String: Any] = [
                    "includeThoughts": true
                ]

                if let effort = reasoning.effort, supportsThinkingLevel(modelID) {
                    let normalizedEffort = ModelCapabilityRegistry.normalizedReasoningEffort(
                        effort,
                        for: .gemini,
                        modelID: modelID
                    )
                    thinkingConfig["thinkingLevel"] = mapEffortToThinkingLevel(normalizedEffort, modelID: modelID)
                } else if let budget = reasoning.budgetTokens {
                    thinkingConfig["thinkingBudget"] = budget
                }

                config["thinkingConfig"] = thinkingConfig
            } else if GeminiModelConstants.isGemini3Model(modelID), supportsThinkingLevel(modelID) {
                // Best-effort "off": minimize thinking level (cannot be fully disabled for Gemini 3 Pro).
                config["thinkingConfig"] = [
                    "thinkingLevel": defaultThinkingLevelWhenOff(modelID: modelID)
                ]
            }
        }
    }

    private static func addImageConfig(
        to config: inout [String: Any],
        controls: GenerationControls,
        modelID: String
    ) {
        guard GeminiModelConstants.isImageGenerationModel(modelID) else { return }

        let imageControls = controls.imageGeneration
        let responseMode = imageControls?.responseMode ?? .textAndImage
        config["responseModalities"] = responseMode.responseModalities

        if let seed = imageControls?.seed {
            config["seed"] = seed
        }

        var imageConfig: [String: Any] = [:]
        if let aspectRatio = imageControls?.aspectRatio {
            imageConfig["aspectRatio"] = aspectRatio.rawValue
        }
        if let imageSize = imageControls?.imageSize, supportsImageSize(modelID, imageSize: imageSize) {
            imageConfig["imageSize"] = imageSize.rawValue
        }
        if !imageConfig.isEmpty {
            config["imageConfig"] = imageConfig
        }
    }

    private static func defaultThinkingLevelWhenOff(modelID: String) -> String {
        GeminiModelConstants.defaultThinkingLevelWhenOff(for: .gemini, modelID: modelID)
    }

    private static func mapEffortToThinkingLevel(_ effort: ReasoningEffort, modelID: String) -> String {
        GeminiModelConstants.mapEffortToThinkingLevel(effort, for: .gemini, modelID: modelID)
    }

    private static func functionDeclaration(_ tool: ToolDefinition) -> [String: Any] {
        [
            "name": tool.name,
            "description": tool.description,
            "parameters": [
                "type": tool.parameters.type,
                "properties": tool.parameters.properties.mapValues { $0.toDictionary() },
                "required": tool.parameters.required
            ]
        ]
    }
}
