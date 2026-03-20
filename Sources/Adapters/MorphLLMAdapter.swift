import Foundation

/// MorphLLM provider adapter (OpenAI-compatible Chat Completions API)
///
/// Docs: https://docs.morphllm.com
/// - Base URL: https://api.morphllm.com/v1
/// - Endpoint: POST /v1/chat/completions
/// - Models: `morph-v3-fast` (10,500 tok/s), `morph-v3-large` (98% accuracy), `auto` (recommended)
///
/// Fast Apply models are specialized for code editing — they accept standard chat completions
/// format and return merged code. No tool calling support.
actor MorphLLMAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming]

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
            streaming: streaming
        )

        return try await sendOpenAICompatibleMessage(
            request: request,
            streaming: streaming,
            reasoningField: .reasoning,
            networkManager: networkManager
        )
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        let body: [String: Any] = [
            "model": "auto",
            "messages": [["role": "user", "content": "hi"]],
            "max_tokens": 1,
            "stream": false
        ]

        let request = try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURLRoot)/v1/chat/completions"),
            apiKey: key,
            body: body
        )

        do {
            let (_, response) = try await networkManager.sendRequest(request)
            return response.statusCode != 401 && response.statusCode != 403
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        MorphLLMAdapter.knownModelIDs.map { makeModelInfo(id: $0) }
    }

    // MARK: - Known Models

    static let knownModelIDs: [String] = [
        "morph-v3-fast",
        "morph-v3-large",
        "auto",
    ]

    // MARK: - Private

    private var baseURLRoot: String {
        let raw = (providerConfig.baseURL ?? "https://api.morphllm.com")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripTrailingV1(raw)
    }

    private func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        streaming: Bool
    ) throws -> URLRequest {
        var body: [String: Any] = [
            "model": modelID,
            "messages": translateMessages(messages),
            "stream": streaming
        ]

        if let temperature = controls.temperature {
            body["temperature"] = temperature
        }

        if let maxTokens = controls.maxTokens {
            body["max_tokens"] = maxTokens
        }

        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURLRoot)/v1/chat/completions"),
            apiKey: apiKey,
            body: body
        )
    }

    // MARK: - Message Translation

    private func translateMessages(_ messages: [Message]) -> [[String: Any]] {
        translateMessagesToOpenAIFormat(messages, translateNonToolMessage: translateNonToolMessage)
    }

    private func translateNonToolMessage(_ message: Message) -> [String: Any] {
        let split = splitContentParts(message.content)
        var dict: [String: Any] = ["role": message.role.rawValue]

        switch message.role {
        case .system, .user:
            dict["content"] = split.visible

        case .assistant:
            dict["content"] = split.visible

        case .tool:
            dict["content"] = split.visible
        }

        return dict
    }

    // MARK: - Model Info

    private func makeModelInfo(id: String) -> ModelInfo {
        if ModelCatalog.entry(for: id, provider: .morphllm) != nil {
            return ModelCatalog.modelInfo(for: id, provider: .morphllm)
        }

        return ModelInfo(
            id: id,
            name: id,
            capabilities: [.streaming],
            contextWindow: 128_000
        )
    }
}
