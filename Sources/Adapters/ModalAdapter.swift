import Foundation

/// Modal adapter (OpenAI-compatible Chat Completions).
///
/// Docs (modal.com/docs/guide/endpoints, .../endpoint-integrations, verified 2026-08-01):
/// - Shared API base URL: https://inference.<region>.modal.direct/v1
///   Regions: us-west (default), us-east, ca-central, eu-west, ap-south.
/// - Chat: POST /v1/chat/completions
/// - Models: GET /v1/models — scoped to the proxy token's workspace, so it is the
///   only way to learn which models a given token can reach.
/// - Auth: a proxy token pair, sent as `Modal-Key` / `Modal-Secret` headers. The
///   same pair joined with a `.` also works as `Authorization: Bearer`, which is
///   what Jin falls back to for a credential that isn't a recognizable pair
///   (an `--unauthenticated` endpoint, or a plain key on a custom server).
/// - Model IDs are Hugging Face repo IDs for Shared API models
///   (`moonshotai/Kimi-K3`), or the endpoint hostname for your own Auto Endpoints
///   reached through the shared gateway (`my-endpoint.us-west.modal.direct`).
///
/// The same adapter also serves an Auto Endpoint directly: paste that endpoint's
/// URL as the base URL and the model ID becomes the base model repo ID.
actor ModalAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning]

    let networkManager: NetworkManager
    let apiKey: String

    init(providerConfig: ProviderConfig, apiKey: String, networkManager: NetworkManager = NetworkManager()) {
        self.providerConfig = providerConfig
        self.apiKey = ModalProxyToken.normalized(apiKey)
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

        // vLLM emits thinking on `reasoning_content`; Modal's own sample client
        // reads `reasoning` or `reasoning_content`, so accept either.
        return try await sendOpenAICompatibleMessage(
            request: request,
            streaming: streaming,
            reasoningField: .reasoningOrReasoningContent,
            networkManager: networkManager
        )
    }

    var baseURL: String {
        let raw = (providerConfig.baseURL ?? ProviderType.modal.defaultBaseURL ?? "https://inference.us-west.modal.direct/v1")
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

    /// Auth headers for a credential.
    ///
    /// A proxy token pair goes out as `Modal-Key` / `Modal-Secret`, which is what
    /// Modal's dashboard hands you and what the proxy speaks natively. Anything
    /// else falls back to the default `Authorization: Bearer` handling.
    static func authHeaders(for key: String) -> (auth: (key: String, value: String)?, additional: [String: String]) {
        guard let token = ModalProxyToken.parse(key) else { return (nil, [:]) }
        return (
            (key: ModalProxyToken.keyHeaderName, value: token.id),
            [ModalProxyToken.secretHeaderName: token.secret]
        )
    }
}
