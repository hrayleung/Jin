import Foundation

extension GeminiAdapter {
    func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> URLRequest {
        let modelPath = modelIDForPath(modelID)
        let method = streaming ? "streamGenerateContent?alt=sse" : "generateContent"
        let endpoint = "\(baseURL)/models/\(modelPath):\(method)"

        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native
        let nativePDFEnabled = allowNativePDF && supportsNativePDF(modelID)

        var body: [String: Any] = [
            "contents": try await translateContents(messages, supportsNativePDF: nativePDFEnabled),
            "generationConfig": GeminiRequestSupport.generationConfig(controls: controls, modelID: modelID)
        ]

        let explicitCachedContent = GeminiRequestSupport.explicitCachedContentName(from: controls)

        if explicitCachedContent == nil, let systemInstruction = GeminiRequestSupport.systemInstructionText(from: messages) {
            body["systemInstruction"] = [
                "parts": [
                    ["text": systemInstruction]
                ]
            ]
        }

        if let cachedContent = explicitCachedContent {
            body["cachedContent"] = cachedContent
        }

        let functionDeclarations = tools.isEmpty ? [] : (translateTools(tools) as? [[String: Any]] ?? [])
        let toolArray = GeminiRequestSupport.toolArray(
            controls: controls,
            functionDeclarations: functionDeclarations,
            supportsWebSearch: supportsWebSearch(modelID),
            supportsCodeExecution: supportsCodeExecution(modelID),
            supportsGoogleMaps: supportsGoogleMaps(modelID),
            supportsFunctionCalling: supportsFunctionCalling(modelID)
        )
        if !toolArray.isEmpty {
            body["tools"] = toolArray
        }

        if let toolConfig = GeminiRequestSupport.toolConfig(
            controls: controls,
            supportsGoogleMaps: supportsGoogleMaps(modelID)
        ) {
            body["toolConfig"] = toolConfig
        }

        if !controls.providerSpecific.isEmpty {
            deepMergeDictionary(into: &body, additional: controls.providerSpecific.mapValues { $0.value })
        }

        return try NetworkRequestFactory.makeJSONRequest(
            url: validatedURL(endpoint),
            headers: geminiHeaders(),
            body: body
        )
    }

    func modelIDForPath(_ modelID: String) -> String {
        GeminiRequestSupport.modelIDForPath(modelID)
    }

    func supportsNativePDF(_ modelID: String) -> Bool {
        GeminiModelConstants.supportsNativePDF(modelID)
    }

    func isGemini3Model(_ modelID: String) -> Bool {
        GeminiModelConstants.isGemini3Model(modelID)
    }

    func isImageGenerationModel(_ modelID: String) -> Bool {
        GeminiModelConstants.isImageGenerationModel(modelID)
    }

    func isVideoGenerationModel(_ modelID: String) -> Bool {
        GoogleVideoGenerationCore.isVideoGenerationModel(modelID)
    }

    func supportsFunctionCalling(_ modelID: String) -> Bool {
        GeminiRequestSupport.supportsFunctionCalling(modelID)
    }

    func supportsWebSearch(_ modelID: String) -> Bool {
        modelSupportsWebSearch(providerConfig: providerConfig, modelID: modelID)
    }

    func supportsCodeExecution(_ modelID: String) -> Bool {
        ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: modelID)
    }

    func supportsGoogleMaps(_ modelID: String) -> Bool {
        ModelCapabilityRegistry.supportsGoogleMaps(for: .gemini, modelID: modelID)
    }

    func supportsThinking(_ modelID: String) -> Bool {
        GeminiRequestSupport.supportsThinking(modelID)
    }

    func supportsThinkingConfig(_ modelID: String) -> Bool {
        GeminiRequestSupport.supportsThinkingConfig(modelID)
    }

    func supportsThinkingLevel(_ modelID: String) -> Bool {
        GeminiRequestSupport.supportsThinkingLevel(modelID)
    }
}
