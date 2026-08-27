import Foundation

/// RunInfra Model APIs adapter (OpenAI-compatible Chat Completions).
///
/// Official docs (verified 2026-08-27):
/// - Base URL: https://api.runinfra.ai/v1
/// - Chat: POST /v1/chat/completions
/// - Models: GET /v1/models
/// - Auth: `Authorization: Bearer` workspace key (`rp_…`)
/// - Reasoning: top-level `reasoning_effort` only. A `reasoning` object is
///   dropped by the gateway before dispatch.
/// - Reasoning text arrives on `message.reasoning` / `delta.reasoning`.
actor RunInfraAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .reasoning]

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
        let raw = (providerConfig.baseURL ?? ProviderType.runinfra.defaultBaseURL ?? "https://api.runinfra.ai/v1")
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
