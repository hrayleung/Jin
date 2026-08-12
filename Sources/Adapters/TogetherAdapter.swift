import Foundation

/// Together AI provider adapter (OpenAI-compatible Chat Completions + async Videos API).
///
/// Endpoints:
/// - GET  /v1/models
/// - POST /v1/chat/completions
/// - POST /v2/videos  (Seedance and other video models)
/// - GET  /v2/videos/{id}
actor TogetherAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning, .videoGeneration]

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

    var baseURL: String {
        let raw = (providerConfig.baseURL ?? ProviderType.together.defaultBaseURL ?? "https://api.together.xyz/v1")
            .trimmed
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
}
