import Foundation

extension VertexAIRequestBuilder {
    func makeGenerationConfig(_ controls: GenerationControls, modelID: String) -> [String: Any] {
        var config: [String: Any] = [:]
        addSamplingControls(to: &config, controls: controls)
        addThinkingConfig(to: &config, controls: controls, modelID: modelID)
        addImageConfig(to: &config, controls: controls, modelID: modelID)
        return config
    }

    func addSamplingControls(to config: inout [String: Any], controls: GenerationControls) {
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

    func addThinkingConfig(
        to config: inout [String: Any],
        controls: GenerationControls,
        modelID: String
    ) {
        let supportsThinkingConfig = modelSupport.supportsThinkingConfig(modelID)
        let supportsThinkingLevel = modelSupport.supportsThinkingLevel(modelID)
        guard supportsThinkingConfig,
              let reasoning = controls.reasoning,
              reasoning.enabled else {
            return
        }

        var thinkingConfig: [String: Any] = ["includeThoughts": true]
        if let effort = reasoning.effort,
           supportsThinkingLevel {
            let normalizedEffort = ModelCapabilityRegistry.normalizedReasoningEffort(
                effort,
                for: .vertexai,
                modelID: modelID
            )
            thinkingConfig["thinkingLevel"] = modelSupport.mapEffortToVertexLevel(normalizedEffort, modelID: modelID)
        } else if let budget = reasoning.budgetTokens {
            thinkingConfig["thinkingBudget"] = budget
        }

        config["thinkingConfig"] = thinkingConfig
    }

    func addImageConfig(
        to config: inout [String: Any],
        controls: GenerationControls,
        modelID: String
    ) {
        let supportsImageGeneration = modelSupport.supportsImageGeneration(modelID)
        guard supportsImageGeneration else { return }

        let imageControls = controls.imageGeneration
        config["responseModalities"] = (imageControls?.responseMode ?? .textAndImage).responseModalities
        if let seed = imageControls?.seed {
            config["seed"] = seed
        }

        var imageConfig: [String: Any] = [:]
        if let aspectRatio = imageControls?.aspectRatio {
            imageConfig["aspectRatio"] = aspectRatio.rawValue
        }
        if let imageSize = imageControls?.imageSize,
           modelSupport.supportsImageSize(modelID, imageSize: imageSize) {
            imageConfig["imageSize"] = imageSize.rawValue
        }
        if let personGeneration = imageControls?.vertexPersonGeneration {
            imageConfig["personGeneration"] = personGeneration.rawValue
        }
        if let imageOutputOptions = makeImageOutputOptions(imageControls) {
            imageConfig["imageOutputOptions"] = imageOutputOptions
        }
        if !imageConfig.isEmpty {
            config["imageConfig"] = imageConfig
        }
    }

    func makeImageOutputOptions(_ imageControls: ImageGenerationControls?) -> [String: Any]? {
        var imageOutputOptions: [String: Any] = [:]
        if let mime = imageControls?.vertexOutputMIMEType {
            imageOutputOptions["mimeType"] = mime.rawValue
        }
        if let quality = imageControls?.vertexCompressionQuality {
            imageOutputOptions["compressionQuality"] = min(100, max(0, quality))
        }
        return imageOutputOptions.isEmpty ? nil : imageOutputOptions
    }
}
