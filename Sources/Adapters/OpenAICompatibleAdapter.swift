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
            authHeader: providerAuthenticationHeader(apiKey: key),
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
            authHeader: providerAuthenticationHeader(apiKey: apiKey),
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
        let models = response.data.map(makeModelInfo(from:))
        if providerConfig.type == .mimoTokenPlanOpenAI {
            return models.filter { !Self.isMiMoTTSModelID($0.id) }
        }
        return models
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
            "messages": try translateMessages(messages, modelID: modelID),
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
            body[providerConfig.type == .mimoTokenPlanOpenAI ? "max_completion_tokens" : "max_tokens"] = maxTokens
        }

        if providerConfig.type == .openai,
           let serviceTier = resolvedOpenAIServiceTier(from: controls) {
            body["service_tier"] = serviceTier
        }

        var toolObjects: [[String: Any]] = []
        if controls.webSearch?.enabled == true,
           providerConfig.type == .mimoTokenPlanOpenAI,
           ModelCapabilityRegistry.supportsWebSearch(for: providerConfig.type, modelID: modelID) {
            toolObjects.append(buildMiMoWebSearchTool(from: controls.webSearch))
        }

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            toolObjects.append(contentsOf: functionTools)
        }

        if !toolObjects.isEmpty {
            body["tools"] = toolObjects
        }

        for (key, value) in controls.providerSpecific {
            if providerConfig.type == .openai, key == "service_tier" {
                continue
            }

            if key == "chat_template_kwargs",
               OpenAICompatibleReasoningSupport.isCloudflareKimiK26Model(
                   providerConfig: providerConfig,
                   modelID: modelID
               ),
               let templateKwargs = value.value as? [String: Any] {
                OpenAICompatibleReasoningSupport.mergeChatTemplateKwargs(
                    into: &body,
                    additional: templateKwargs
                )
                continue
            }
            body[key] = value.value
        }

        OpenAICompatibleReasoningSupport.finalizeOpenAICompatibleReasoningBody(
            &body,
            controls: controls,
            providerConfig: providerConfig,
            modelID: modelID
        )

        var request = try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/chat/completions"),
            apiKey: apiKey,
            authHeader: providerAuthenticationHeader(apiKey: apiKey),
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

    private func providerAuthenticationHeader(apiKey: String) -> (key: String, value: String)? {
        guard providerConfig.type == .mimoTokenPlanOpenAI else { return nil }
        return (key: "api-key", value: apiKey)
    }

    private func validateGitHubModelsToken(_ key: String) async throws -> Bool {
        var request = makeGETRequest(
            url: try validatedURL(modelsListURLString),
            apiKey: key,
            authHeader: providerAuthenticationHeader(apiKey: key),
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

    private func translateMessages(_ messages: [Message], modelID: String) throws -> [[String: Any]] {
        try translateMessagesToOpenAIFormat(messages) { message in
            try translateNonToolMessage(message, modelID: modelID)
        }
    }

    private func translateNonToolMessage(_ message: Message, modelID: String) throws -> [String: Any] {
        let supportsAudioInput = supportsAudioInput(modelID: modelID)
        let supportsVideoInput = supportsVideoInput(modelID: modelID)
        let split = splitContentParts(
            message.content,
            separator: "\n",
            includeImages: true,
            includeAudio: supportsAudioInput,
            includeVideo: supportsVideoInput
        )

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system:
            dict["content"] = split.visible

        case .assistant:
            if let thinking = split.thinkingOrNil {
                if OpenAICompatibleReasoningSupport.isMistralMedium35Model(
                    providerConfig: providerConfig,
                    modelID: modelID
                ) {
                    dict["content"] = mistralAssistantContentChunks(visible: split.visible, thinking: thinking)
                } else if providerConfig.type == .zhipuCodingPlan
                    || providerConfig.type == .minimax
                    || providerConfig.type == .mimoTokenPlanOpenAI {
                    dict["content"] = split.visible
                    dict["reasoning_content"] = thinking
                } else {
                    dict["content"] = split.visible
                    dict["reasoning"] = thinking
                }
            } else {
                dict["content"] = split.visible
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCallsToOpenAIFormat(toolCalls)
            }

        case .user:
            if split.hasRichUserContent {
                let audioBuilder: ((AudioContent) throws -> [String: Any]?)? = {
                    guard supportsAudioInput else { return nil }
                    return providerConfig.type == .mimoTokenPlanOpenAI ? mimoInputAudioPart : mistralAudioPartBuilder
                }()
                dict["content"] = try translateUserContentPartsToOpenAIFormat(
                    message.content,
                    audioPartBuilder: audioBuilder,
                    videoPartBuilder: supportsVideoInput ? mimoInputVideoPart : nil
                )
            } else {
                dict["content"] = split.visible
            }

        case .tool:
            dict["content"] = split.visible
        }

        return dict
    }

    private func supportsAudioInput(modelID: String) -> Bool {
        if OpenAICompatibleReasoningSupport.isMistralMedium35Model(
            providerConfig: providerConfig,
            modelID: modelID
        ) {
            return false
        }
        if providerConfig.type == .mimoTokenPlanOpenAI {
            return Self.miMoFullModalInputModelIDs.contains(modelID.lowercased())
        }
        return true
    }

    private func supportsVideoInput(modelID: String) -> Bool {
        providerConfig.type == .mimoTokenPlanOpenAI
            && Self.miMoFullModalInputModelIDs.contains(modelID.lowercased())
    }

    private func mistralAssistantContentChunks(visible: String, thinking: String) -> [[String: Any]] {
        var chunks: [[String: Any]] = [
            [
                "type": "thinking",
                "thinking": [
                    [
                        "type": "text",
                        "text": thinking
                    ]
                ],
                "closed": true
            ]
        ]

        if !visible.isEmpty {
            chunks.append([
                "type": "text",
                "text": visible
            ])
        }

        return chunks
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

    private func mimoInputAudioPart(_ audio: AudioContent) throws -> [String: Any]? {
        if let url = audio.url, !url.isFileURL {
            return [
                "type": "input_audio",
                "input_audio": ["data": url.absoluteString]
            ]
        }
        guard let payloadData = try resolveAudioData(audio) else { return nil }
        return [
            "type": "input_audio",
            "input_audio": [
                "data": mediaDataURI(mimeType: audio.mimeType, data: payloadData)
            ]
        ]
    }

    private func mimoInputVideoPart(_ video: VideoContent) throws -> [String: Any]? {
        let urlString: String?
        if let url = video.url, !url.isFileURL {
            urlString = url.absoluteString
        } else if let payloadData = try resolveVideoData(video) {
            urlString = mediaDataURI(mimeType: video.mimeType, data: payloadData)
        } else {
            urlString = nil
        }
        guard let urlString else { return nil }

        return [
            "type": "video_url",
            "video_url": ["url": urlString],
            "fps": 2,
            "media_resolution": "default"
        ]
    }

    private func buildMiMoWebSearchTool(from controls: WebSearchControls?) -> [String: Any] {
        var tool: [String: Any] = ["type": "web_search"]

        if let limit = controls?.maxUses, limit > 0 {
            tool["limit"] = limit
            tool["max_keyword"] = limit
        }

        if let location = controls?.userLocation,
           let userLocation = buildMiMoUserLocation(location) {
            tool["user_location"] = userLocation
        }

        return tool
    }

    private func buildMiMoUserLocation(_ location: WebSearchUserLocation) -> [String: Any]? {
        var userLocation: [String: Any] = ["type": "approximate"]

        if let country = normalizedWebSearchLocationField(location.country) {
            userLocation["country"] = country
        }
        if let region = normalizedWebSearchLocationField(location.region) {
            userLocation["region"] = region
        }
        if let city = normalizedWebSearchLocationField(location.city) {
            userLocation["city"] = city
        }
        if let timezone = normalizedWebSearchLocationField(location.timezone) {
            userLocation["timezone"] = timezone
        }

        return userLocation.count > 1 ? userLocation : nil
    }

    private func normalizedWebSearchLocationField(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static let miMoFullModalInputModelIDs: Set<String> = [
        "mimo-v2.5",
        "mimo-v2-omni"
    ]

    private static func isMiMoTTSModelID(_ modelID: String) -> Bool {
        switch modelID.lowercased() {
        case "mimo-v2.5-tts", "mimo-v2.5-tts-voicedesign", "mimo-v2.5-tts-voiceclone", "mimo-v2-tts":
            return true
        default:
            return false
        }
    }

    private func makeModelInfo(from model: OpenAIModelsResponse.Model) -> ModelInfo {
        if providerConfig.type == .vercelAIGateway {
            return makeVercelModelInfo(from: model)
        }
        return makeModelInfo(id: model.id)
    }

    private func makeModelInfo(id: String) -> ModelInfo {
        ModelCatalog.modelInfo(for: id, provider: providerConfig.type)
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
                maxOutputTokens: entry.maxOutputTokens,
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
