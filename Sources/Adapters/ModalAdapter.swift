import Foundation

/// Modal adapter (OpenAI-compatible Chat Completions).
///
/// Docs (modal.com/docs/guide/endpoints, verified 2026-08-13):
/// - Each `modal endpoint create --model …` deployment has its own URL.
///   Chat is `POST <endpoint-url>/v1/chat/completions` with `model` set to the
///   Hugging Face repo ID.
/// - Shared catalog models (Kimi / Qwen / Inkling) use the default Shared API
///   host `https://inference.us-west.modal.direct/v1`. Region is a deploy-time
///   choice on the endpoint, not a client setting.
/// - Auth: proxy token pair as `Modal-Key` / `Modal-Secret` (or Bearer `wk-….ws-…`).
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
