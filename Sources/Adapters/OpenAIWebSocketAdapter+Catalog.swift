import Foundation

extension OpenAIWebSocketAdapter {
    func validateOpenAIWebSocketAPIKey(_ key: String) async throws -> Bool {
        await validateAPIKeyViaGET(
            url: try validatedURL("\(resolvedHTTPBaseURLString())/models"),
            apiKey: key,
            networkManager: networkManager
        )
    }

    func fetchOpenAIWebSocketModels() async throws -> [ModelInfo] {
        let request = makeGETRequest(
            url: try validatedURL("\(resolvedHTTPBaseURLString())/models"),
            apiKey: apiKey,
            accept: nil,
            includeUserAgent: false
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let response = try JSONDecoder().decode(OpenAIWebSocketModelsResponse.self, from: data)
        return response.data
            .filter { ModelCatalog.isOpenAIWebSocketAdapterCompatible(modelID: $0.id) }
            .map(makeModelInfo)
    }

    private func makeModelInfo(from model: OpenAIWebSocketModelData) -> ModelInfo {
        var info = ModelCatalog.modelInfo(for: model.id, provider: .openaiWebSocket, name: model.id)
        let contextWindow = model.contextWindow.flatMap { $0 > 0 ? $0 : nil }
        let maxOutputTokens = model.maxTokens.flatMap { $0 > 0 ? $0 : nil }

        if let contextWindow {
            info = replacingLimits(
                in: info,
                contextWindow: contextWindow,
                maxOutputTokens: maxOutputTokens ?? info.maxOutputTokens
            )
        } else if let maxOutputTokens {
            info = replacingLimits(
                in: info,
                contextWindow: info.contextWindow,
                maxOutputTokens: maxOutputTokens
            )
        }

        return info
    }

    private func replacingLimits(
        in info: ModelInfo,
        contextWindow: Int,
        maxOutputTokens: Int?
    ) -> ModelInfo {
        ModelInfo(
            id: info.id,
            name: info.name,
            capabilities: info.capabilities,
            contextWindow: contextWindow,
            maxOutputTokens: maxOutputTokens,
            reasoningConfig: info.reasoningConfig,
            overrides: info.overrides,
            catalogMetadata: info.catalogMetadata,
            isEnabled: info.isEnabled
        )
    }
}

private struct OpenAIWebSocketModelsResponse: Codable {
    let data: [OpenAIWebSocketModelData]
}

private struct OpenAIWebSocketModelData: Codable {
    let id: String
    let contextWindow: Int?
    let maxTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case contextWindow = "context_window"
        case maxTokens = "max_tokens"
    }
}
