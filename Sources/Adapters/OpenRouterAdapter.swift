import Foundation

/// OpenRouter provider adapter (OpenAI-compatible Chat Completions API)
///
/// Docs:
/// - Base URL: https://openrouter.ai/api/v1
/// - Endpoint: POST /chat/completions
/// - Models: GET /models
/// - Async video models: GET /videos/models
actor OpenRouterAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning, .videoGeneration]

    let networkManager: NetworkManager
    let apiKey: String

    init(providerConfig: ProviderConfig, apiKey: String, networkManager: NetworkManager = NetworkManager()) {
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager
    }

    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        if isVideoGenerationModel(modelID) {
            return try makeVideoGenerationStream(
                messages: messages,
                modelID: modelID,
                controls: controls
            )
        }

        let request = try buildRequest(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: streaming
        )

        return try await sendOpenAICompatibleMessage(
            request: request,
            streaming: streaming,
            reasoningField: .reasoningOrReasoningContent,
            networkManager: networkManager
        )
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        let request = makeGETRequest(
            url: try validatedURL("\(baseURL)/key"),
            apiKey: key,
            additionalHeaders: openRouterHeaders,
            includeUserAgent: false
        )

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        let standardModels = try await fetchStandardModels()
        let videoModels = await fetchVideoModelsIfAvailable()

        var seenIDs = Set<String>()
        return (standardModels + videoModels).filter { model in
            seenIDs.insert(model.id).inserted
        }
    }

    private func fetchStandardModels() async throws -> [ModelInfo] {
        let request = makeGETRequest(
            url: try validatedURL("\(baseURL)/models"),
            apiKey: apiKey,
            additionalHeaders: openRouterHeaders,
            includeUserAgent: false
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(OpenRouterModelsResponse.self, from: data)
        return response.data.map(makeModelInfo(from:))
    }

    private func fetchVideoModelsIfAvailable() async -> [ModelInfo] {
        do {
            return try await fetchVideoModels()
        } catch {
            return []
        }
    }

    private func fetchVideoModels() async throws -> [ModelInfo] {
        let request = makeGETRequest(
            url: try validatedURL("\(baseURL)/videos/models"),
            apiKey: apiKey,
            additionalHeaders: openRouterHeaders,
            includeUserAgent: false
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(OpenRouterVideoModelsResponse.self, from: data)
        return response.data.map(makeModelInfo(from:))
    }

    // MARK: - Private

    var baseURL: String {
        let raw = (providerConfig.baseURL ?? "https://openrouter.ai/api/v1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        let lower = trimmed.lowercased()

        if lower.hasSuffix("/api/v1") || lower.hasSuffix("/v1") {
            return trimmed
        }

        if lower.hasSuffix("/api") {
            return "\(trimmed)/v1"
        }

        if let url = URL(string: trimmed),
           url.host?.lowercased().contains("openrouter.ai") == true,
           (url.path.isEmpty || url.path == "/") {
            return "\(trimmed)/api/v1"
        }

        return trimmed
    }

    var openRouterHeaders: [String: String] {
        [
            "HTTP-Referer": "https://jin.app",
            "X-Title": "Jin"
        ]
    }

    private func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        let imageGenerationModel = isImageGenerationModel(modelID)
        let lowerModelID = modelID.lowercased()
        let omitsSamplingParameters = lowerModelID == "openai/gpt-5.4-image-2"
        let unsupportedSamplingParameterKeys: Set<String> = [
            "temperature",
            "top_p",
            "top_k",
            "min_p",
            "repetition_penalty"
        ]

        var body: [String: Any] = [
            "model": modelID,
            "messages": try translateMessages(messages),
            "stream": streaming
        ]

        let requestShape = ModelCapabilityRegistry.requestShape(for: providerConfig.type, modelID: modelID)
        let shouldOmitSamplingControls = applyReasoning(
            to: &body,
            controls: controls,
            modelID: modelID,
            requestShape: requestShape
        )

        if !shouldOmitSamplingControls && !omitsSamplingParameters {
            if let temperature = controls.temperature {
                body["temperature"] = temperature
            }
            if let topP = controls.topP {
                body["top_p"] = topP
            }
        }

        if let maxTokens = controls.maxTokens {
            body["max_tokens"] = maxTokens
        }

        if imageGenerationModel {
            applyImageGeneration(to: &body, controls: controls)
        }

        if controls.webSearch?.enabled == true, modelSupportsWebSearch(for: modelID) {
            var plugins = body["plugins"] as? [[String: Any]] ?? []
            plugins.append(["id": "web"])
            body["plugins"] = plugins
        }

        if !imageGenerationModel,
           !tools.isEmpty,
           let functionTools = translateTools(tools) as? [[String: Any]] {
            body["tools"] = functionTools
        }

        for (key, value) in controls.providerSpecific {
            if omitsSamplingParameters,
               unsupportedSamplingParameterKeys.contains(key.lowercased()) {
                continue
            }
            body[key] = value.value
        }

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/chat/completions"),
            apiKey: apiKey,
            body: body,
            additionalHeaders: openRouterHeaders,
            includeUserAgent: false
        )
    }

    private func translateMessages(_ messages: [Message]) throws -> [[String: Any]] {
        try translateMessagesToOpenAIFormat(messages, translateNonToolMessage: translateNonToolMessage)
    }

    private func translateNonToolMessage(_ message: Message) throws -> [String: Any] {
        let split = splitContentParts(message.content, includeImages: true, includeAudio: true)

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system:
            dict["content"] = split.visible

        case .user:
            if split.hasRichUserContent {
                dict["content"] = try translateUserContentPartsToOpenAIFormat(message.content)
            } else {
                dict["content"] = split.visible
            }

        case .assistant:
            let hasToolCalls = (message.toolCalls?.isEmpty == false)
            if split.visible.isEmpty {
                dict["content"] = hasToolCalls ? NSNull() : ""
            } else {
                dict["content"] = split.visible
            }

            if !split.thinking.isEmpty {
                dict["reasoning"] = split.thinking
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCallsToOpenAIFormat(toolCalls)
            }

        case .tool:
            dict["content"] = ""
        }

        return dict
    }

    // MARK: - Image Generation

    private func applyImageGeneration(
        to body: inout [String: Any],
        controls: GenerationControls
    ) {
        let responseMode = controls.imageGeneration?.responseMode ?? .textAndImage
        body["modalities"] = openRouterModalities(for: responseMode)

        if let seed = controls.imageGeneration?.seed {
            body["seed"] = seed
        }
    }

    private func openRouterModalities(for responseMode: ImageResponseMode) -> [String] {
        switch responseMode {
        case .textAndImage:
            return ["text", "image"]
        case .imageOnly:
            return ["image"]
        }
    }

    // MARK: - Reasoning

    /// OpenRouter-specific reasoning application. Adds `include_reasoning` field
    /// on top of the standard OpenAI-compatible reasoning logic.
    private func applyReasoning(
        to body: inout [String: Any],
        controls: GenerationControls,
        modelID: String,
        requestShape: ModelRequestShape
    ) -> Bool {
        guard modelSupportsReasoning(providerConfig: providerConfig, modelID: modelID) else {
            return false
        }
        guard let reasoning = controls.reasoning else { return false }

        switch requestShape {
        case .openAIResponses, .openAICompatible:
            if reasoning.enabled == false || (reasoning.effort ?? ReasoningEffort.none) == ReasoningEffort.none {
                body["include_reasoning"] = false
                body["reasoning"] = ["effort": "none"]
                return false
            }

            let effort = reasoning.effort ?? .medium
            body["include_reasoning"] = true
            body["reasoning"] = [
                "effort": OpenAICompatibleReasoningSupport.mapReasoningEffort(
                    effort,
                    providerConfig: providerConfig,
                    modelID: modelID
                )
            ]
            return requestShape == .openAIResponses

        case .anthropic, .gemini:
            return OpenAICompatibleReasoningSupport.applyReasoning(
                to: &body,
                controls: controls,
                providerConfig: providerConfig,
                modelID: modelID,
                requestShape: requestShape
            )
        }
    }

    // MARK: - Web Search

    private func modelSupportsWebSearch(for modelID: String) -> Bool {
        guard let model = findConfiguredModel(in: providerConfig, for: modelID) else {
            return ModelCapabilityRegistry.supportsWebSearch(
                for: providerConfig.type,
                modelID: modelID
            )
        }

        let resolved = ModelSettingsResolver.resolve(model: model, providerType: providerConfig.type)
        return resolved.supportsWebSearch
    }

    // MARK: - Model Info

    private func makeModelInfo(from model: OpenRouterModelsResponse.Model) -> ModelInfo {
        let id = model.id
        let lower = id.lowercased()
        let apiContextWindow = positiveInt(model.contextLength)
            ?? positiveInt(model.topProvider?.contextLength)
        let apiMaxOutputTokens = positiveInt(model.topProvider?.maxCompletionTokens)

        if let entry = ModelCatalog.entry(for: id, provider: .openrouter) {
            return ModelInfo(
                id: id,
                name: entry.displayName,
                capabilities: entry.capabilities,
                contextWindow: apiContextWindow ?? entry.contextWindow,
                maxOutputTokens: apiMaxOutputTokens ?? entry.maxOutputTokens,
                reasoningConfig: entry.reasoningConfig
            )
        }

        let inputModalities = Set((model.architecture?.inputModalities ?? []).map { $0.lowercased() })
        let outputModalities = Set((model.architecture?.outputModalities ?? []).map { $0.lowercased() })
        let supportedParameters = Set((model.supportedParameters ?? []).map { $0.lowercased() })
        let hasImageLikeModalities = inputModalities.contains(where: { $0.contains("image") || $0.contains("video") })
            || outputModalities.contains(where: { $0.contains("image") || $0.contains("video") })
        let hasAudioLikeModalities = inputModalities.contains(where: { $0.contains("audio") })
            || outputModalities.contains(where: { $0.contains("audio") })
        let supportsReasoning = supportedParameters.contains("reasoning")
            || supportedParameters.contains("include_reasoning")
            || supportedParameters.contains("reasoning_effort")
        let outputsText = outputModalities.contains(where: { $0.contains("text") })
        let outputsImage = outputModalities.contains(where: { $0.contains("image") }) || lower.contains("image")
        let outputsVideo = outputModalities.contains(where: { $0.contains("video") }) || lower.contains("video")
        let isMediaOnlyModel = (outputsImage || outputsVideo) && !outputsText

        var caps: ModelCapability = isMediaOnlyModel ? [] : [.streaming]

        if !isMediaOnlyModel, supportedParameters.contains("tools") {
            caps.insert(.toolCalling)
        }
        if hasImageLikeModalities {
            caps.insert(.vision)
        }
        if !isMediaOnlyModel, hasAudioLikeModalities || isAudioInputModelID(lower) {
            caps.insert(.audio)
        }
        if !isMediaOnlyModel, supportsReasoning {
            caps.insert(.reasoning)
        }
        if !isMediaOnlyModel, model.pricing?.inputCacheRead != nil {
            caps.insert(.promptCaching)
        }
        if outputsImage {
            caps.insert(.imageGeneration)
        }
        if outputsVideo {
            caps.insert(.videoGeneration)
        }

        return ModelInfo(
            id: id,
            name: model.name ?? id,
            capabilities: caps,
            contextWindow: apiContextWindow ?? 128_000,
            maxOutputTokens: apiMaxOutputTokens,
            reasoningConfig: (!isMediaOnlyModel && supportsReasoning)
                ? ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                : nil
        )
    }

    private func makeModelInfo(from model: OpenRouterVideoModelsResponse.Model) -> ModelInfo {
        let id = model.id

        if let entry = ModelCatalog.entry(for: id, provider: .openrouter) {
            return ModelInfo(
                id: id,
                name: entry.displayName,
                capabilities: entry.capabilities,
                contextWindow: entry.contextWindow,
                maxOutputTokens: entry.maxOutputTokens,
                reasoningConfig: entry.reasoningConfig
            )
        }

        return ModelInfo(
            id: id,
            name: model.name ?? id,
            capabilities: [.videoGeneration],
            contextWindow: 32_768,
            maxOutputTokens: nil,
            reasoningConfig: nil
        )
    }

    private func positiveInt(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func isImageGenerationModel(_ modelID: String) -> Bool {
        if let model = findConfiguredModel(in: providerConfig, for: modelID) {
            let resolved = ModelSettingsResolver.resolve(model: model, providerType: providerConfig.type)
            if resolved.capabilities.contains(.imageGeneration) {
                return true
            }
        }

        return ModelCatalog.entry(for: modelID, provider: .openrouter)?.capabilities.contains(.imageGeneration) == true
    }

    private func isVideoGenerationModel(_ modelID: String) -> Bool {
        if let model = findConfiguredModel(in: providerConfig, for: modelID) {
            let resolved = ModelSettingsResolver.resolve(model: model, providerType: providerConfig.type)
            if resolved.capabilities.contains(.videoGeneration) {
                return true
            }
        }

        return ModelCatalog.entry(for: modelID, provider: .openrouter)?.capabilities.contains(.videoGeneration) == true
    }

}

private struct OpenRouterModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
        let name: String?
        let contextLength: Int?
        let architecture: Architecture?
        let topProvider: TopProvider?
        let supportedParameters: [String]?
        let pricing: Pricing?
    }

    struct Architecture: Decodable {
        let inputModalities: [String]?
        let outputModalities: [String]?
    }

    struct TopProvider: Decodable {
        let contextLength: Int?
        let maxCompletionTokens: Int?
    }

    struct Pricing: Decodable {
        let inputCacheRead: String?
    }
}

private struct OpenRouterVideoModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
        let name: String?
    }
}
