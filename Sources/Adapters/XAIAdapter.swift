import Foundation

/// xAI provider adapter.
///
/// - Chat models use the Responses API (`/responses`).
/// - Image models use `/images/generations` + `/images/edits`.
/// - Video models use `/videos/generations` (text/image) and `/videos/edits` (video edit), both async.
///
/// Responses API conversation handling is in `XAIAdapter+ResponsesConversation.swift`.
/// Image generation is in `XAIAdapter+ImageGeneration.swift`.
/// Media helpers are in `XAIMediaHelpers.swift`.
/// Video generation is in `XAIVideoGeneration.swift`.
/// Citation resolution is in `XAICitationResolver.swift`.
/// Response types are in `XAIAdapterResponseTypes.swift`.
/// Message translation is in `XAIAdapterMessageTranslation.swift`.
/// SSE stream parsing is in `XAIAdapterStreamParsing.swift`.
actor XAIAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .imageGeneration, .videoGeneration]
    let networkManager: NetworkManager
    let r2Uploader: CloudflareR2Uploader
    let apiKey: String

    init(
        providerConfig: ProviderConfig,
        apiKey: String,
        networkManager: NetworkManager = NetworkManager(),
        r2Uploader: CloudflareR2Uploader? = nil
    ) {
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager
        self.r2Uploader = r2Uploader ?? CloudflareR2Uploader(networkManager: networkManager)
    }

    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        if isVideoGenerationModel(modelID) {
            return try makeVideoGenerationStream(messages: messages, modelID: modelID, controls: controls)
        }

        if isImageGenerationModel(modelID) {
            return try makeImageGenerationStream(messages: messages, modelID: modelID, controls: controls)
        }

        return try await sendResponsesConversation(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: streaming
        )
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        await validateAPIKeyViaGET(
            url: try validatedURL("\(baseURL)/models"),
            apiKey: key,
            networkManager: networkManager
        )
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        let request = makeGETRequest(
            url: try validatedURL("\(baseURL)/models"),
            apiKey: apiKey,
            accept: nil,
            includeUserAgent: false
        )

        let (data, _) = try await networkManager.sendRequest(request)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(XAIModelsResponse.self, from: data)

        return response.data
            .map { model in
                if ModelCatalog.entry(for: model.id, provider: .xai) != nil {
                    return ModelCatalog.modelInfo(for: model.id, provider: .xai)
                }

                return XAIModelSupport.modelInfo(from: model)
            }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }

    // MARK: - Private

    var baseURL: String {
        providerConfig.baseURL ?? "https://api.x.ai/v1"
    }

    // MARK: - Capability / Model Inference

    func isImageGenerationModel(_ modelID: String) -> Bool {
        if providerConfig.models.first(where: { $0.id == modelID })?.capabilities.contains(.imageGeneration) == true {
            return true
        }
        return XAIModelSupport.isImageGenerationModelID(modelID)
    }

    func isVideoGenerationModel(_ modelID: String) -> Bool {
        if providerConfig.models.first(where: { $0.id == modelID })?.capabilities.contains(.videoGeneration) == true {
            return true
        }
        return XAIModelSupport.isVideoGenerationModelID(modelID)
    }

    // MARK: - Shared Helpers

    func applyProviderSpecificOverrides(
        controls: GenerationControls,
        modelID: String? = nil,
        body: inout [String: Any]
    ) {
        XAIResponsesRequestSupport.applyProviderSpecificOverrides(
            to: &body,
            controls: controls,
            modelID: modelID
        )
    }
}
