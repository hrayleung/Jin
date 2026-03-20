import Foundation

/// Generic OpenAI-compatible provider adapter (Chat Completions API).
///
/// Expected endpoints:
/// - GET  /models
/// - POST /chat/completions
actor OpenAICompatibleAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning]

    private let networkManager: NetworkManager
    private let apiKey: String
    private let gitHubModelsAPIVersion = "2022-11-28"

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
        if providerConfig.type == .mistral, isMistralTranscriptionOnlyModelID(modelID.lowercased()) {
            throw LLMError.invalidRequest(
                message: "Model \(modelID) is transcription-only on Mistral /v1/audio/transcriptions. Use voxtral-mini-latest or voxtral-small-latest for chat."
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
        if providerConfig.type == .githubCopilot {
            return try await validateGitHubModelsToken(key)
        }

        var request = makeGETRequest(
            url: try validatedURL(modelsListURLString),
            apiKey: key,
            accept: acceptHeaderValue,
            includeUserAgent: false
        )
        applyProviderHeaders(to: &request)

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        var request = makeGETRequest(
            url: try validatedURL(modelsListURLString),
            apiKey: apiKey,
            accept: acceptHeaderValue,
            includeUserAgent: false
        )
        applyProviderHeaders(to: &request)

        let (data, _) = try await networkManager.sendRequest(request)

        if providerConfig.type == .githubCopilot {
            let response = try JSONDecoder().decode([GitHubModelsCatalogModel].self, from: data)
            return response.compactMap(makeGitHubModelInfo(from:))
        }

        let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return response.data.map(makeModelInfo(from:))
    }

    // MARK: - Private

    private var baseURL: String {
        let raw = (providerConfig.baseURL ?? providerConfig.type.defaultBaseURL ?? "https://api.openai.com/v1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = normalizedCloudflareGatewayBaseURL(from: raw.hasSuffix("/") ? String(raw.dropLast()) : raw)
        let lower = trimmed.lowercased()

        if lower.hasSuffix("/api/v1") || lower.hasSuffix("/v1") {
            return trimmed
        }

        if lower.hasSuffix("/api") {
            return "\(trimmed)/v1"
        }

        if let url = URL(string: trimmed), url.path.isEmpty || url.path == "/" {
            return "\(trimmed)/v1"
        }

        return trimmed
    }

    private var modelsListURLString: String {
        if providerConfig.type == .githubCopilot {
            guard let base = URL(string: baseURL), let host = base.host else {
                return "https://models.github.ai/catalog/models"
            }

            var components = URLComponents()
            components.scheme = base.scheme ?? "https"
            components.host = host
            components.port = base.port
            components.path = "/catalog/models"
            return components.url?.absoluteString ?? "https://models.github.ai/catalog/models"
        }

        return "\(baseURL)/models"
    }

    private var acceptHeaderValue: String {
        providerConfig.type == .githubCopilot ? "application/vnd.github+json" : "application/json"
    }

    private func normalizedCloudflareGatewayBaseURL(from value: String) -> String {
        guard providerConfig.type == .cloudflareAIGateway else { return value }

        let lower = value.lowercased()
        if lower.hasSuffix("/{provider}") {
            let prefix = value.dropLast("/{provider}".count)
            return "\(prefix)/compat"
        }

        return value
    }

    private func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        var body: [String: Any] = [
            "model": modelID,
            "messages": try translateMessages(messages),
            "stream": streaming
        ]

        let requestShape = ModelCapabilityRegistry.requestShape(for: providerConfig.type, modelID: modelID)
        let shouldOmitSamplingControls = OpenAICompatibleReasoningSupport.applyReasoning(
            to: &body,
            controls: controls,
            providerConfig: providerConfig,
            modelID: modelID,
            requestShape: requestShape
        )

        if !shouldOmitSamplingControls {
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

        if providerConfig.type == .openai,
           let serviceTier = resolvedOpenAIServiceTier(from: controls) {
            body["service_tier"] = serviceTier
        }

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            body["tools"] = functionTools
        }

        for (key, value) in controls.providerSpecific {
            if providerConfig.type == .openai, key == "service_tier" {
                continue
            }
            body[key] = value.value
        }

        var request = try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/chat/completions"),
            apiKey: apiKey,
            body: body,
            accept: acceptHeaderValue,
            includeUserAgent: false
        )
        applyProviderHeaders(to: &request)
        applyCloudflareGatewayCacheHeaders(to: &request, controls: controls)
        return request
    }

    private func applyProviderHeaders(to request: inout URLRequest) {
        request.setValue(jinUserAgent, forHTTPHeaderField: "User-Agent")

        guard providerConfig.type == .githubCopilot else { return }
        request.setValue(gitHubModelsAPIVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
    }

    private func validateGitHubModelsToken(_ key: String) async throws -> Bool {
        var request = makeGETRequest(
            url: try validatedURL(modelsListURLString),
            apiKey: key,
            accept: acceptHeaderValue,
            includeUserAgent: false
        )
        applyProviderHeaders(to: &request)

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            return false
        }
    }

    private func applyCloudflareGatewayCacheHeaders(to request: inout URLRequest, controls: GenerationControls) {
        guard providerConfig.type == .cloudflareAIGateway else { return }

        if controls.contextCache?.mode == .off {
            request.setValue("true", forHTTPHeaderField: "cf-aig-skip-cache")
            return
        }

        let ttlSeconds = cloudflareGatewayCacheTTLSeconds(from: controls.contextCache?.ttl)
        request.setValue(String(ttlSeconds), forHTTPHeaderField: "cf-aig-cache-ttl")
    }

    private func cloudflareGatewayCacheTTLSeconds(from ttl: ContextCacheTTL?) -> Int {
        switch ttl {
        case .hour1:
            return 3_600
        case .customSeconds(let seconds):
            return max(1, seconds)
        case .providerDefault, .minutes5, .none:
            return 300
        }
    }

    private func translateMessages(_ messages: [Message]) throws -> [[String: Any]] {
        try translateMessagesToOpenAIFormat(messages, translateNonToolMessage: translateNonToolMessage)
    }

    private func translateNonToolMessage(_ message: Message) throws -> [String: Any] {
        let split = splitContentParts(
            message.content,
            separator: "\n",
            includeImages: true,
            includeAudio: true
        )

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system:
            dict["content"] = split.visible

        case .assistant:
            dict["content"] = split.visible
            if let thinking = split.thinkingOrNil {
                if providerConfig.type == .zhipuCodingPlan
                    || providerConfig.type == .minimax {
                    dict["reasoning_content"] = thinking
                } else {
                    dict["reasoning"] = thinking
                }
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCallsToOpenAIFormat(toolCalls)
            }

        case .user:
            if split.hasRichUserContent {
                dict["content"] = try translateUserContentPartsToOpenAIFormat(
                    message.content,
                    audioPartBuilder: mistralAudioPartBuilder
                )
            } else {
                dict["content"] = split.visible
            }

        case .tool:
            dict["content"] = split.visible
        }

        return dict
    }

    /// Mistral Voxtral expects a raw base64 string for `input_audio`, not the standard OpenAI format.
    private func mistralAudioPartBuilder(_ audio: AudioContent) throws -> [String: Any]? {
        if providerConfig.type == .mistral {
            guard let payloadData = try resolveAudioData(audio) else { return nil }
            return [
                "type": "input_audio",
                "input_audio": payloadData.base64EncodedString()
            ]
        }
        return try openAIInputAudioPart(audio)
    }

    private func makeModelInfo(from model: OpenAIModelsResponse.Model) -> ModelInfo {
        if providerConfig.type == .vercelAIGateway {
            return makeVercelModelInfo(from: model)
        }
        return makeModelInfo(id: model.id)
    }

    private func makeModelInfo(id: String) -> ModelInfo {
        ModelCatalog.modelInfo(for: id, provider: providerConfig.type, name: id)
    }

    private func makeGitHubModelInfo(from model: GitHubModelsCatalogModel) -> ModelInfo? {
        let lowerOutputModalities = Set((model.supportedOutputModalities ?? []).map { $0.lowercased() })
        guard lowerOutputModalities.contains("text") else { return nil }

        if let entry = ModelCatalog.entry(for: model.id, provider: .githubCopilot) {
            return ModelInfo(
                id: model.id,
                name: entry.displayName,
                capabilities: entry.capabilities,
                contextWindow: entry.contextWindow,
                maxOutputTokens: entry.maxOutputTokens ?? model.maxOutputTokens,
                reasoningConfig: entry.reasoningConfig
            )
        }

        let lowerInputModalities = Set((model.supportedInputModalities ?? []).map { $0.lowercased() })
        let lowerCapabilities = Set((model.capabilities ?? []).map { $0.lowercased() })
        let lowerTags = Set((model.tags ?? []).map { $0.lowercased() })

        var capabilities: ModelCapability = []

        if lowerCapabilities.contains("streaming") {
            capabilities.insert(.streaming)
        }
        if lowerInputModalities.contains("image") {
            capabilities.insert(.vision)
        }
        if lowerInputModalities.contains("audio") || lowerOutputModalities.contains("audio") {
            capabilities.insert(.audio)
        }
        if lowerOutputModalities.contains("image") {
            capabilities.insert(.imageGeneration)
        }
        if lowerOutputModalities.contains("video") {
            capabilities.insert(.videoGeneration)
        }
        if lowerInputModalities.contains("pdf")
            || lowerCapabilities.contains("pdf")
            || lowerCapabilities.contains("native_pdf")
            || lowerCapabilities.contains("native-pdf") {
            capabilities.insert(.nativePDF)
        }
        if lowerCapabilities.contains("tool_calling")
            || lowerCapabilities.contains("tool-calling")
            || lowerCapabilities.contains("function_calling")
            || lowerCapabilities.contains("function-calling")
            || lowerCapabilities.contains("tools") {
            capabilities.insert(.toolCalling)
        }
        if lowerCapabilities.contains("reasoning") || lowerCapabilities.contains("thinking") || lowerTags.contains("reasoning") {
            capabilities.insert(.reasoning)
        }
        if lowerCapabilities.contains("prompt_caching")
            || lowerCapabilities.contains("prompt-caching")
            || lowerCapabilities.contains("caching") {
            capabilities.insert(.promptCaching)
        }

        return ModelInfo(
            id: model.id,
            name: normalizedTrimmedString(model.name) ?? model.id,
            capabilities: capabilities,
            contextWindow: max(1, model.maxInputTokens ?? 128_000),
            maxOutputTokens: model.maxOutputTokens,
            reasoningConfig: capabilities.contains(.reasoning)
                ? ModelCapabilityRegistry.defaultReasoningConfig(for: .githubCopilot, modelID: model.id)
                : nil,
            catalogMetadata: gitHubCatalogMetadata(from: model)
        )
    }

    private func gitHubCatalogMetadata(from model: GitHubModelsCatalogModel) -> ModelCatalogMetadata? {
        let details = [
            normalizedTrimmedString(model.publisher),
            normalizedTrimmedString(model.summary),
            normalizedTrimmedString(model.rateLimitTier).map { "Rate limit tier: \($0)" }
        ]
        .compactMap { $0 }

        guard !details.isEmpty else { return nil }
        return ModelCatalogMetadata(availabilityMessage: details.joined(separator: "\n"))
    }

    private func makeVercelModelInfo(from model: OpenAIModelsResponse.Model) -> ModelInfo {
        let modelID = model.id
        let displayName = normalizedTrimmedString(model.name) ?? modelID

        if let entry = ModelCatalog.entry(for: modelID, provider: .vercelAIGateway) {
            return ModelInfo(
                id: modelID,
                name: entry.displayName,
                capabilities: entry.capabilities,
                contextWindow: entry.contextWindow,
                reasoningConfig: entry.reasoningConfig
            )
        }

        var capabilities = derivedVercelCapabilities(from: model)
        let contextWindow = max(1, model.contextWindow ?? 128_000)
        var reasoningConfig = ModelCapabilityRegistry.defaultReasoningConfig(
            for: .vercelAIGateway,
            modelID: modelID
        )
        if !capabilities.contains(.reasoning) {
            reasoningConfig = nil
        }

        if capabilities.contains(.imageGeneration) || capabilities.contains(.videoGeneration) {
            // Media-generation models exposed through the gateway are not guaranteed
            // to support OpenAI function-calling semantics for MCP/tools.
            capabilities.remove(.toolCalling)
            capabilities.remove(.audio)
        }

        return ModelInfo(
            id: modelID,
            name: displayName,
            capabilities: capabilities,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig
        )
    }

    private func derivedVercelCapabilities(from model: OpenAIModelsResponse.Model) -> ModelCapability {
        let lowerType = model.type?.lowercased()
        let lowerTags = Set((model.tags ?? []).map { $0.lowercased() })

        if lowerType == "image" {
            return [.imageGeneration]
        }

        if lowerType == "video" {
            return [.videoGeneration]
        }

        var capabilities: ModelCapability = [.streaming, .toolCalling]

        if lowerTags.contains("reasoning") {
            capabilities.insert(.reasoning)
        }
        if lowerTags.contains("vision") || lowerTags.contains("image-generation") {
            capabilities.insert(.vision)
        }
        if lowerTags.contains("implicit-caching") {
            capabilities.insert(.promptCaching)
        }
        if lowerTags.contains("image-generation") {
            capabilities.insert(.imageGeneration)
        }
        if lowerTags.contains("video-generation") {
            capabilities.insert(.videoGeneration)
        }

        return capabilities
    }

    private func isMistralTranscriptionOnlyModelID(_ lowerModelID: String) -> Bool {
        lowerModelID == "voxtral-mini-2602" || lowerModelID.contains("transcribe")
    }
}

private struct GitHubModelsCatalogModel: Decodable {
    let id: String
    let name: String?
    let capabilities: [String]?
    let supportedInputModalities: [String]?
    let supportedOutputModalities: [String]?
    let directMaxInputTokens: Int?
    let directMaxOutputTokens: Int?
    let limits: Limits?
    let publisher: String?
    let summary: String?
    let rateLimitTier: String?
    let tags: [String]?

    var maxInputTokens: Int? { directMaxInputTokens ?? limits?.maxInputTokens }
    var maxOutputTokens: Int? { directMaxOutputTokens ?? limits?.maxOutputTokens }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case capabilities
        case supportedInputModalities = "supported_input_modalities"
        case supportedOutputModalities = "supported_output_modalities"
        case directMaxInputTokens = "max_input_tokens"
        case directMaxOutputTokens = "max_output_tokens"
        case limits
        case publisher
        case summary
        case rateLimitTier = "rate_limit_tier"
        case tags
    }

    struct Limits: Decodable {
        let maxInputTokens: Int?
        let maxOutputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case maxInputTokens = "max_input_tokens"
            case maxOutputTokens = "max_output_tokens"
        }
    }
}
