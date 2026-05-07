import Foundation

extension OpenAIAdapter {
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
        let response = try JSONDecoder().decode(OpenAIResponsesModelsListResponse.self, from: data)
        return response.data.map(makeModelInfo(from:))
    }

    private func makeModelInfo(from model: OpenAIResponsesModelsListResponse.ModelData) -> ModelInfo {
        var info = ModelCatalog.modelInfo(for: model.id, provider: .openai, name: model.id)
        let contextWindow = model.contextWindow.flatMap { $0 > 0 ? $0 : nil }
        let maxOutputTokens = model.maxTokens.flatMap { $0 > 0 ? $0 : nil }

        if let contextWindow {
            info = ModelInfo(
                id: info.id,
                name: info.name,
                capabilities: info.capabilities,
                contextWindow: contextWindow,
                maxOutputTokens: maxOutputTokens ?? info.maxOutputTokens,
                reasoningConfig: info.reasoningConfig,
                overrides: info.overrides,
                catalogMetadata: info.catalogMetadata,
                isEnabled: info.isEnabled
            )
        } else if let maxOutputTokens {
            info = ModelInfo(
                id: info.id,
                name: info.name,
                capabilities: info.capabilities,
                contextWindow: info.contextWindow,
                maxOutputTokens: maxOutputTokens,
                reasoningConfig: info.reasoningConfig,
                overrides: info.overrides,
                catalogMetadata: info.catalogMetadata,
                isEnabled: info.isEnabled
            )
        }

        return info
    }
}

private struct OpenAIResponsesModelsListResponse: Codable {
    let data: [ModelData]

    struct ModelData: Codable {
        let id: String
        let contextWindow: Int?
        let maxTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case id
            case contextWindow = "context_window"
            case maxTokens = "max_tokens"
        }
    }
}
