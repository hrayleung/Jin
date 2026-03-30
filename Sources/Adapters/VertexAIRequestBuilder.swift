import Foundation

struct VertexAIRequestBuilder {
    private let providerConfig: ProviderConfig
    private let serviceAccountJSON: ServiceAccountCredentials
    private let modelSupport: VertexAIModelSupport

    init(
        providerConfig: ProviderConfig,
        serviceAccountJSON: ServiceAccountCredentials,
        modelSupport: VertexAIModelSupport
    ) {
        self.providerConfig = providerConfig
        self.serviceAccountJSON = serviceAccountJSON
        self.modelSupport = modelSupport
    }

    func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool,
        accessToken: String
    ) throws -> URLRequest {
        let normalizedModelID = normalizedModelID(from: modelID)
        let endpoint = try makeRequestURL(modelID: normalizedModelID, streaming: streaming)
        var body = try makeRequestBody(
            messages: messages,
            modelID: normalizedModelID,
            controls: controls,
            tools: tools
        )

        if !controls.providerSpecific.isEmpty {
            deepMergeDictionary(into: &body, additional: controls.providerSpecific.mapValues { $0.value })
        }

        return try NetworkRequestFactory.makeJSONRequest(
            url: endpoint,
            timeoutSeconds: modelSupport.requestTimeoutInterval(for: normalizedModelID, controls: controls),
            headers: vertexHeaders(accessToken: accessToken),
            body: body
        )
    }

    func vertexHeaders(
        accessToken: String,
        accept: String? = nil,
        contentType: String? = nil
    ) -> [String: String] {
        var headers: [String: String] = ["Authorization": "Bearer \(accessToken)"]
        if let accept {
            headers["Accept"] = accept
        }
        if let contentType {
            headers["Content-Type"] = contentType
        }
        return headers
    }

    private func makeRequestURL(modelID: String, streaming: Bool) throws -> URL {
        let method = streaming ? "streamGenerateContent" : "generateContent"
        let endpoint = "\(baseURL)/projects/\(serviceAccountJSON.projectID)/locations/\(location)/publishers/google/models/\(modelID):\(method)"
        return try validatedURL(endpoint)
    }

    private func normalizedModelID(from rawModelID: String) -> String {
        let trimmed = rawModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rawModelID }

        let segments = trimmed
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !segments.isEmpty else { return trimmed }

        if let index = segments.lastIndex(of: "models"),
           index < segments.index(before: segments.endIndex) {
            return segments[segments.index(after: index)]
        }

        return segments.last ?? trimmed
    }

    private func makeRequestBody(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition]
    ) throws -> [String: Any] {
        let supportsNativePDF = supportsNativePDF(modelID: modelID, controls: controls)
        var body: [String: Any] = [
            "contents": try translatedMessages(messages, supportsNativePDF: supportsNativePDF),
            "generationConfig": makeGenerationConfig(controls, modelID: modelID)
        ]

        let explicitCachedContent = explicitCachedContentName(from: controls)
        if let cachedContent = explicitCachedContent {
            body["cachedContent"] = cachedContent
        } else if let systemInstruction = systemInstruction(from: messages) {
            body["systemInstruction"] = systemInstruction
        }

        let toolArray = makeTools(modelID: modelID, controls: controls, tools: tools)
        if !toolArray.isEmpty {
            body["tools"] = toolArray
        }

        if let toolConfig = makeToolConfig(modelID: modelID, controls: controls) {
            body["toolConfig"] = toolConfig
        }

        return body
    }

    private func translatedMessages(
        _ messages: [Message],
        supportsNativePDF: Bool
    ) throws -> [[String: Any]] {
        try VertexAIMessageTranslation.translateMessages(
            messages,
            supportsNativePDF: supportsNativePDF
        )
    }

    private func systemInstruction(from messages: [Message]) -> [String: Any]? {
        let parts = messages
            .filter { $0.role == .system }
            .flatMap(\.content)
            .compactMap { part -> String? in
                guard case .text(let text) = part else { return nil }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : text
            }
            .map { ["text": $0] }

        guard !parts.isEmpty else { return nil }
        return ["parts": parts]
    }

    private func explicitCachedContentName(from controls: GenerationControls) -> String? {
        guard controls.contextCache?.mode == .explicit else { return nil }
        return normalizedTrimmedString(controls.contextCache?.cachedContentName)
    }

    private func makeTools(
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition]
    ) -> [[String: Any]] {
        let supportsWebSearch = modelSupport.supportsWebSearch(providerConfig: providerConfig, modelID: modelID)
        let supportsCodeExecution = modelSupport.supportsCodeExecution(modelID)
        let supportsFunctionCalling = modelSupport.supportsFunctionCalling(modelID)
        var toolArray: [[String: Any]] = []

        if controls.webSearch?.enabled == true, supportsWebSearch {
            toolArray.append(["googleSearch": [:]])
        }
        if controls.codeExecution?.enabled == true, supportsCodeExecution {
            toolArray.append(["codeExecution": [:]])
        }
        if let googleMapsTool = makeGoogleMapsTool(modelID: modelID, controls: controls) {
            toolArray.append(googleMapsTool)
        }
        if supportsFunctionCalling,
           !tools.isEmpty,
           let functionDeclarations = Self.translateTools(tools) as? [[String: Any]] {
            toolArray.append(["functionDeclarations": functionDeclarations])
        }

        return toolArray
    }

    private func makeGoogleMapsTool(
        modelID: String,
        controls: GenerationControls
    ) -> [String: Any]? {
        guard controls.googleMaps?.enabled == true,
              modelSupport.supportsGoogleMaps(modelID) else {
            return nil
        }

        var mapsConfig: [String: Any] = [:]
        if controls.googleMaps?.enableWidget == true {
            mapsConfig["enableWidget"] = true
        }
        return ["googleMaps": mapsConfig]
    }

    private func makeToolConfig(modelID: String, controls: GenerationControls) -> [String: Any]? {
        guard controls.googleMaps?.enabled == true,
              modelSupport.supportsGoogleMaps(modelID) else {
            return nil
        }

        var retrievalConfig: [String: Any] = [:]
        if let lat = controls.googleMaps?.latitude,
           let lng = controls.googleMaps?.longitude {
            retrievalConfig["latLng"] = ["latitude": lat, "longitude": lng]
        }
        if let languageCode = normalizedTrimmedString(controls.googleMaps?.languageCode) {
            retrievalConfig["languageCode"] = languageCode
        }
        guard !retrievalConfig.isEmpty else { return nil }
        return ["retrievalConfig": retrievalConfig]
    }

    private func supportsNativePDF(modelID: String, controls: GenerationControls) -> Bool {
        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native
        return allowNativePDF && modelSupport.supportsNativePDF(modelID)
    }

    private func makeGenerationConfig(_ controls: GenerationControls, modelID: String) -> [String: Any] {
        var config: [String: Any] = [:]
        addSamplingControls(to: &config, controls: controls)
        addThinkingConfig(to: &config, controls: controls, modelID: modelID)
        addImageConfig(to: &config, controls: controls, modelID: modelID)
        return config
    }

    private func addSamplingControls(to config: inout [String: Any], controls: GenerationControls) {
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

    private func addThinkingConfig(
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

    private func addImageConfig(
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

    private func makeImageOutputOptions(_ imageControls: ImageGenerationControls?) -> [String: Any]? {
        var imageOutputOptions: [String: Any] = [:]
        if let mime = imageControls?.vertexOutputMIMEType {
            imageOutputOptions["mimeType"] = mime.rawValue
        }
        if let quality = imageControls?.vertexCompressionQuality {
            imageOutputOptions["compressionQuality"] = min(100, max(0, quality))
        }
        return imageOutputOptions.isEmpty ? nil : imageOutputOptions
    }

    private var baseURL: String {
        if location == "global" {
            return "https://aiplatform.googleapis.com/v1"
        }
        return "https://\(location)-aiplatform.googleapis.com/v1"
    }

    private var location: String {
        serviceAccountJSON.location ?? "global"
    }

    private static func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "parametersJsonSchema": [
                    "type": tool.parameters.type,
                    "properties": tool.parameters.properties.mapValues { $0.toDictionary() },
                    "required": tool.parameters.required
                ]
            ]
        }
    }
}
