import Foundation

/// Generic OpenAI-compatible provider adapter (Chat Completions API).
///
/// Expected endpoints:
/// - GET  /models
/// - POST /chat/completions
///
/// Reasoning field and capability bits come from `OpenAICompatibleProfile`
/// so new generic providers need a profile entry, not a new actor.
actor OpenAICompatibleAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability
    private let profile: OpenAICompatibleProfile

    let networkManager: NetworkManager
    let apiKey: String

    init(providerConfig: ProviderConfig, apiKey: String, networkManager: NetworkManager = NetworkManager()) {
        let profile = OpenAICompatibleProfile.profile(for: providerConfig.type) ?? .default
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager
        self.profile = profile
        self.capabilities = profile.capabilities
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

        let effectiveStreaming = profile.disablesStreamingWithTools
            ? (streaming && tools.isEmpty)
            : streaming

        let request = try buildRequest(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: effectiveStreaming
        )

        return try await sendOpenAICompatibleMessage(
            request: request,
            streaming: effectiveStreaming,
            reasoningField: profile.reasoningField,
            networkManager: networkManager
        )
    }

}
