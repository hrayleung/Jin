import Foundation

// MARK: - Gemini & Vertex AI Draft & Apply

extension ProviderParamsJSONSync {

    // MARK: - Gemini

    static func makeGeminiDraft(controls: GenerationControls, modelID: String) -> [String: Any] {
        var out: [String: Any] = [:]

        if isGoogleVideoModel(modelID) {
            if let videoControls = controls.googleVideoGeneration {
                out["videoGeneration"] = makeGoogleVideoGenerationDraft(videoControls)
            }
            return out
        }

        let generationConfig = makeGeminiGenerationConfig(controls: controls, modelID: modelID)
        if !generationConfig.isEmpty {
            out["generationConfig"] = generationConfig
        }

        if controls.webSearch?.enabled == true, geminiSupportsGoogleSearch(modelID) {
            out["tools"] = [
                ["google_search": [:]]
            ]
        }

        if controls.contextCache?.mode == .explicit,
           let cachedContent = normalizedTrimmedString(controls.contextCache?.cachedContentName) {
            out["cachedContent"] = cachedContent
        }

        return out
    }

    static func applyGemini(
        draft: [String: AnyCodable],
        modelID: String,
        controls: inout GenerationControls,
        providerSpecific: inout [String: AnyCodable]
    ) {
        if isGoogleVideoModel(modelID) {
            if let raw = draft["videoGeneration"]?.value as? [String: Any] {
                applyGoogleVideoGeneration(raw, controls: &controls)
                providerSpecific.removeValue(forKey: "videoGeneration")
            } else {
                controls.googleVideoGeneration = nil
            }
            return
        }

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

        if let raw = draft["cachedContent"]?.value as? String {
            let normalized = normalizedTrimmedString(raw)
            var contextCache = controls.contextCache ?? ContextCacheControls(mode: .explicit)
            contextCache.mode = .explicit
            contextCache.cachedContentName = normalized
            controls.contextCache = contextCache
            providerSpecific.removeValue(forKey: "cachedContent")
        } else if draft["cachedContent"] == nil,
                  controls.contextCache?.mode == .explicit {
            controls.contextCache?.cachedContentName = nil
        }
    }

    // MARK: - Vertex AI

    static func makeVertexAIDraft(controls: GenerationControls, modelID: String) -> [String: Any] {
        var out: [String: Any] = [:]

        if isGoogleVideoModel(modelID) {
            if let videoControls = controls.googleVideoGeneration {
                out["videoGeneration"] = makeGoogleVideoGenerationDraft(videoControls)
            }
            return out
        }

        let generationConfig = makeVertexAIGenerationConfig(controls: controls, modelID: modelID)
        if !generationConfig.isEmpty {
            out["generationConfig"] = generationConfig
        }

        if controls.webSearch?.enabled == true, vertexSupportsGoogleSearch(modelID) {
            out["tools"] = [
                ["googleSearch": [:]]
            ]
        }

        if controls.contextCache?.mode == .explicit,
           let cachedContent = normalizedTrimmedString(controls.contextCache?.cachedContentName) {
            out["cachedContent"] = cachedContent
        }

        return out
    }

    static func applyVertexAI(
        draft: [String: AnyCodable],
        modelID: String,
        controls: inout GenerationControls,
        providerSpecific: inout [String: AnyCodable]
    ) {
        if isGoogleVideoModel(modelID) {
            if let raw = draft["videoGeneration"]?.value as? [String: Any] {
                applyGoogleVideoGeneration(raw, controls: &controls)
                providerSpecific.removeValue(forKey: "videoGeneration")
            } else {
                controls.googleVideoGeneration = nil
            }
            return
        }

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

        if let raw = draft["cachedContent"]?.value as? String {
            let normalized = normalizedTrimmedString(raw)
            var contextCache = controls.contextCache ?? ContextCacheControls(mode: .explicit)
            contextCache.mode = .explicit
            contextCache.cachedContentName = normalized
            controls.contextCache = contextCache
            providerSpecific.removeValue(forKey: "cachedContent")
        } else if draft["cachedContent"] == nil,
                  controls.contextCache?.mode == .explicit {
            controls.contextCache?.cachedContentName = nil
        }
    }

    // MARK: - Gemini Generation Config

    static func makeGeminiGenerationConfig(controls: GenerationControls, modelID: String) -> [String: Any] {
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
                    let normalizedEffort = ModelCapabilityRegistry.normalizedReasoningEffort(
                        effort,
                        for: .gemini,
                        modelID: modelID
                    )
                    thinkingConfig["thinkingLevel"] = mapEffortToGeminiThinkingLevel(normalizedEffort, modelID: modelID)
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
            if let imageSize = imageControls.imageSize,
               supportsGoogleImageSize(modelID, imageSize: imageSize) {
                imageConfig["imageSize"] = imageSize.rawValue
            }
            if !imageConfig.isEmpty {
                config["imageConfig"] = imageConfig
            }
        }

        return config
    }

    static func applyGeminiGenerationConfig(
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

    static func applyGeminiImageConfig(_ dict: [String: Any], modelID: String, controls: inout GenerationControls) {
        var image = controls.imageGeneration ?? ImageGenerationControls()

        if let aspect = dict["aspectRatio"] as? String, let ratio = ImageAspectRatio(rawValue: aspect) {
            image.aspectRatio = ratio
        }

        if isGemini3ProImageModel(modelID),
           let sizeString = dict["imageSize"] as? String,
           let size = ImageOutputSize(rawValue: sizeString) {
            image.imageSize = supportsGoogleImageSize(modelID, imageSize: size) ? size : nil
        }

        controls.imageGeneration = image.isEmpty ? nil : image
    }

    // MARK: - Vertex AI Generation Config

    static func makeVertexAIGenerationConfig(controls: GenerationControls, modelID: String) -> [String: Any] {
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

        if vertexSupportsThinkingConfig(modelID), let reasoning = controls.reasoning, reasoning.enabled {
            var thinkingConfig: [String: Any] = [
                "includeThoughts": true
            ]

            if let effort = reasoning.effort {
                let normalizedEffort = ModelCapabilityRegistry.normalizedReasoningEffort(
                    effort,
                    for: .vertexai,
                    modelID: modelID
                )
                thinkingConfig["thinkingLevel"] = mapEffortToVertexThinkingLevel(
                    normalizedEffort,
                    modelID: modelID
                )
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
            if let imageSize = imageControls.imageSize,
               supportsGoogleImageSize(modelID, imageSize: imageSize) {
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

    static func applyVertexAIGenerationConfig(
        _ dict: [String: Any],
        modelID: String,
        controls: inout GenerationControls,
        providerSpecific: inout [String: AnyCodable]
    ) {
        let remaining = applyGoogleStyleGenerationConfig(
            dict,
            defaultLevelWhenOff: defaultVertexThinkingLevelWhenOff(modelID: modelID),
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

    static func applyVertexImageConfig(_ dict: [String: Any], modelID: String, controls: inout GenerationControls) {
        var image = controls.imageGeneration ?? ImageGenerationControls()

        if let aspect = dict["aspectRatio"] as? String, let ratio = ImageAspectRatio(rawValue: aspect) {
            image.aspectRatio = ratio
        }

        if isVertexGemini3ProImageModel(modelID),
           let sizeString = dict["imageSize"] as? String,
           let size = ImageOutputSize(rawValue: sizeString) {
            image.imageSize = supportsGoogleImageSize(modelID, imageSize: size) ? size : nil
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

    // MARK: - Shared Google Helpers

    static let gemini3ModelIDs: Set<String> = [
        "gemini-3",
        "gemini-3-pro",
        "gemini-3-pro-preview",
        "gemini-3.1-pro-preview",
        "gemini-3.1-flash-image-preview",
        "gemini-3-flash-preview",
        "gemini-3-pro-image-preview",
    ]

    static let geminiImageModelIDs: Set<String> = [
        "gemini-3-pro-image-preview",
        "gemini-3.1-flash-image-preview",
        "gemini-2.5-flash-image",
    ]

    static let googleVideoModelIDs: Set<String> = [
        "veo-2",
        "veo-3",
    ]

    static func geminiSupportsGoogleSearch(_ modelID: String) -> Bool {
        ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: modelID)
    }

    static func geminiSupportsThinking(_ modelID: String) -> Bool {
        modelID.lowercased() != "gemini-2.5-flash-image"
    }

    static func isGemini3Model(_ modelID: String) -> Bool {
        gemini3ModelIDs.contains(modelID.lowercased())
    }

    static func isGeminiImageModel(_ modelID: String) -> Bool {
        geminiImageModelIDs.contains(modelID.lowercased())
    }

    static func isGemini3ProImageModel(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return lower == "gemini-3-pro-image-preview" || lower == "gemini-3.1-flash-image-preview"
    }

    static func supportsGoogleImageSize(_ modelID: String, imageSize: ImageOutputSize) -> Bool {
        let lower = modelID.lowercased()
        switch lower {
        case "gemini-3.1-flash-image-preview":
            return true
        case "gemini-3-pro-image-preview":
            return imageSize != .size512px
        default:
            return false
        }
    }

    static func isGoogleVideoModel(_ modelID: String) -> Bool {
        googleVideoModelIDs.contains(modelID.lowercased())
    }

    static func makeGoogleVideoGenerationDraft(_ controls: GoogleVideoGenerationControls) -> [String: Any] {
        var out: [String: Any] = [:]
        if let duration = controls.durationSeconds { out["durationSeconds"] = duration }
        if let aspectRatio = controls.aspectRatio { out["aspectRatio"] = aspectRatio.rawValue }
        if let resolution = controls.resolution { out["resolution"] = resolution.rawValue }
        if let negativePrompt = controls.negativePrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !negativePrompt.isEmpty {
            out["negativePrompt"] = negativePrompt
        }
        if let generateAudio = controls.generateAudio { out["generateAudio"] = generateAudio }
        if let personGeneration = controls.personGeneration { out["personGeneration"] = personGeneration.rawValue }
        if let seed = controls.seed { out["seed"] = seed }
        return out
    }

    static func applyGoogleVideoGeneration(_ dict: [String: Any], controls: inout GenerationControls) {
        var video = controls.googleVideoGeneration ?? GoogleVideoGenerationControls()

        if let duration = dict["durationSeconds"] as? Int {
            video.durationSeconds = duration
        }
        if let aspectRatioString = dict["aspectRatio"] as? String,
           let ratio = GoogleVideoAspectRatio(rawValue: aspectRatioString) {
            video.aspectRatio = ratio
        }
        if let resolutionString = dict["resolution"] as? String,
           let resolution = GoogleVideoResolution(rawValue: resolutionString) {
            video.resolution = resolution
        }
        if let negativePrompt = dict["negativePrompt"] as? String {
            video.negativePrompt = negativePrompt
        }
        if let generateAudio = dict["generateAudio"] as? Bool {
            video.generateAudio = generateAudio
        }
        if let personString = dict["personGeneration"] as? String,
           let person = GoogleVideoPersonGeneration(rawValue: personString) {
            video.personGeneration = person
        }
        if let seed = dict["seed"] as? Int {
            video.seed = seed
        }

        controls.googleVideoGeneration = video.isEmpty ? nil : video
    }

    static func defaultGeminiThinkingLevelWhenOff(modelID: String) -> String {
        let supportsMinimal = ModelCapabilityRegistry.supportedReasoningEfforts(
            for: .gemini,
            modelID: modelID
        ).contains(.minimal)
        return supportsMinimal ? "MINIMAL" : "LOW"
    }

    static func mapEffortToGeminiThinkingLevel(_ effort: ReasoningEffort, modelID: String) -> String {
        let supportedEfforts = ModelCapabilityRegistry.supportedReasoningEfforts(
            for: .gemini,
            modelID: modelID
        )
        let supportsMinimal = supportedEfforts.contains(.minimal)
        let supportsMedium = supportedEfforts.contains(.medium)

        switch effort {
        case .none, .minimal:
            return supportsMinimal ? "MINIMAL" : "LOW"
        case .low:
            return "LOW"
        case .medium:
            return supportsMedium ? "MEDIUM" : "HIGH"
        case .high, .xhigh:
            return "HIGH"
        }
    }

    static func vertexSupportsGoogleSearch(_ modelID: String) -> Bool {
        ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: modelID)
    }

    static func vertexSupportsThinking(_ modelID: String) -> Bool {
        modelID.lowercased() != "gemini-2.5-flash-image"
    }

    static func vertexSupportsThinkingConfig(_ modelID: String) -> Bool {
        vertexSupportsThinking(modelID) && !isVertexGemini3ProImageModel(modelID)
    }

    static func isVertexImageModel(_ modelID: String) -> Bool {
        isGeminiImageModel(modelID)
    }

    static func isVertexGemini3ProImageModel(_ modelID: String) -> Bool {
        isGemini3ProImageModel(modelID)
    }

    static func defaultVertexThinkingLevelWhenOff(modelID: String) -> String {
        let supportsMinimal = ModelCapabilityRegistry.supportedReasoningEfforts(
            for: .vertexai,
            modelID: modelID
        ).contains(.minimal)
        return supportsMinimal ? "MINIMAL" : "LOW"
    }

    static func mapEffortToVertexThinkingLevel(_ effort: ReasoningEffort, modelID: String) -> String {
        let supportedEfforts = ModelCapabilityRegistry.supportedReasoningEfforts(
            for: .vertexai,
            modelID: modelID
        )
        let supportsMinimal = supportedEfforts.contains(.minimal)
        let supportsMedium = supportedEfforts.contains(.medium)

        switch effort {
        case .none, .minimal:
            return supportsMinimal ? "MINIMAL" : "LOW"
        case .low:
            return "LOW"
        case .medium:
            return supportsMedium ? "MEDIUM" : "HIGH"
        case .high, .xhigh:
            return "HIGH"
        }
    }

    /// Shared logic for Gemini and VertexAI generation config application.
    /// Returns the remaining (unrecognized) keys for providerSpecific passthrough.
    static func applyGoogleStyleGenerationConfig(
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

    static func applyGoogleSearchTools(
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
}
