import Foundation

/// Cohere official provider adapter (Chat API v2).
///
/// Docs:
/// - Base URL: https://api.cohere.com/v2
/// - Endpoint: POST /chat (streaming via SSE when `stream=true`)
actor CohereAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling]

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

        if !streaming {
            let (data, _) = try await networkManager.sendRequest(request)
            let response = try decodeChatResponse(data)
            return makeNonStreamingStream(response: response)
        }

        let parser = SSEParser()
        let sseStream = await networkManager.streamRequest(request, parser: parser)
        return makeStreamingStream(sseStream: sseStream)
    }

    var baseURL: String {
        let raw = (providerConfig.baseURL ?? providerConfig.type.defaultBaseURL ?? "https://api.cohere.com/v2")
            .trimmed
        var trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        let lower = trimmed.lowercased()

        if lower.hasSuffix("/chat") {
            trimmed = String(trimmed.dropLast(5))
            trimmed = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        }

        if lower.hasSuffix("/v2") {
            return trimmed
        }

        if let url = URL(string: trimmed), url.path.isEmpty || url.path == "/" {
            return "\(trimmed)/v2"
        }

        return trimmed
    }
}
