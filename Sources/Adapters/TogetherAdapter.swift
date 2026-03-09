import Foundation

/// Together AI provider adapter (OpenAI-compatible Chat Completions API).
///
/// Endpoints:
/// - GET  /models
/// - POST /chat/completions
actor TogetherAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning]

    private let networkManager: NetworkManager
    private let apiKey: String

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
            url: try validatedURL("\(baseURL)/models"),
            apiKey: key,
            includeUserAgent: false
        )

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        let request = makeGETRequest(
            url: try validatedURL("\(baseURL)/models"),
            apiKey: apiKey,
            includeUserAgent: false
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()

        if let models = try? decoder.decode([TogetherModelInfo].self, from: data) {
            return models.map(makeModelInfo(from:))
        }

        // Compatibility fallback when a proxy returns OpenAI's `data` shape.
        if let openAIModels = try? decoder.decode(OpenAIModelsResponse.self, from: data) {
            return openAIModels.data.map { makeModelInfo(id: $0.id, displayName: nil) }
        }

        throw LLMError.decodingError(message: "Together /models response could not be decoded.")
    }

    // MARK: - Private

    private var baseURL: String {
        let raw = (providerConfig.baseURL ?? ProviderType.together.defaultBaseURL ?? "https://api.together.xyz/v1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        let lower = trimmed.lowercased()

        if lower.hasSuffix("/v1") {
            return trimmed
        }

        if let url = URL(string: trimmed), url.path.isEmpty || url.path == "/" {
            return "\(trimmed)/v1"
        }

        return trimmed
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

        if let temperature = controls.temperature {
            body["temperature"] = temperature
        }
        if let topP = controls.topP {
            body["top_p"] = topP
        }
        if let maxTokens = controls.maxTokens {
            body["max_tokens"] = maxTokens
        }

        applyReasoning(to: &body, controls: controls, modelID: modelID)

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            body["tools"] = functionTools
        }

        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/chat/completions"),
            apiKey: apiKey,
            body: body,
            includeUserAgent: false
        )
    }

    private func applyReasoning(to body: inout [String: Any], controls: GenerationControls, modelID: String) {
        guard modelSupportsReasoning(providerConfig: providerConfig, modelID: modelID) else { return }
        guard let reasoning = controls.reasoning else { return }

        switch resolvedReasoningType(for: modelID) {
        case .toggle:
            body["reasoning"] = ["enabled": reasoning.enabled]

        case .effort:
            guard reasoning.enabled else { return }
            let effort = reasoning.effort ?? .medium
            switch effort {
            case .none, .minimal, .low:
                body["reasoning_effort"] = "low"
            case .medium:
                body["reasoning_effort"] = "medium"
            case .high, .xhigh:
                body["reasoning_effort"] = "high"
            }

        case .budget, .none, .noneSet:
            break
        }
    }

    private func resolvedReasoningType(for modelID: String) -> TogetherReasoningType {
        if let configuredModel = findConfiguredModel(in: providerConfig, for: modelID) {
            let resolved = ModelSettingsResolver.resolve(model: configuredModel, providerType: providerConfig.type)
            guard let reasoningType = resolved.reasoningConfig?.type else { return .noneSet }
            return TogetherReasoningType(reasoningType)
        }

        if let catalogType = ModelCatalog.entry(for: modelID, provider: .together)?.reasoningConfig?.type {
            return TogetherReasoningType(catalogType)
        }

        return .noneSet
    }

    private func translateMessages(_ messages: [Message]) throws -> [[String: Any]] {
        try translateMessagesToOpenAIFormat(messages, translateNonToolMessage: translateNonToolMessage)
    }

    private func translateNonToolMessage(_ message: Message) throws -> [String: Any] {
        let split = splitContentParts(message.content, separator: "\n", includeImages: true, includeAudio: true)

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system:
            dict["content"] = split.visible

        case .assistant:
            dict["content"] = split.visible
            if let thinking = split.thinkingOrNil {
                dict["reasoning"] = thinking
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCallsToOpenAIFormat(toolCalls)
            }

        case .user:
            if split.hasRichUserContent {
                dict["content"] = try translateUserContentPartsToOpenAIFormat(message.content)
            } else {
                dict["content"] = split.visible
            }

        case .tool:
            dict["content"] = split.visible
        }

        return dict
    }

    private func makeModelInfo(from model: TogetherModelInfo) -> ModelInfo {
        makeModelInfo(id: model.id, displayName: model.displayName)
    }

    private func makeModelInfo(id: String, displayName: String?) -> ModelInfo {
        ModelCatalog.modelInfo(for: id, provider: .together, name: displayName ?? id)
    }
}

private struct TogetherModelInfo: Decodable {
    let id: String
    let type: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case displayName = "display_name"
    }
}

private enum TogetherReasoningType {
    case toggle
    case effort
    case budget
    case none
    case noneSet

    init(_ raw: ReasoningConfigType) {
        switch raw {
        case .toggle:
            self = .toggle
        case .effort:
            self = .effort
        case .budget:
            self = .budget
        case .none:
            self = .none
        }
    }
}
