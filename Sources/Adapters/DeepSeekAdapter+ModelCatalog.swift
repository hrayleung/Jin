import Foundation

extension DeepSeekAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        await validateAPIKeyViaGET(
            url: try validatedURL("\(baseURLRoot)/v1/models"),
            apiKey: key,
            networkManager: networkManager
        )
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        let request = makeGETRequest(url: try validatedURL("\(baseURLRoot)/v1/models"), apiKey: apiKey)
        let (data, _) = try await networkManager.sendRequest(request)
        let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return response.data.map { makeModelInfo(id: $0.id) }
    }

    private func makeModelInfo(id: String) -> ModelInfo {
        if ModelCatalog.entry(for: id, provider: .deepseek) != nil {
            return ModelCatalog.modelInfo(for: id, provider: .deepseek)
        }

        var capabilities: ModelCapability = [.streaming, .toolCalling]
        var reasoningConfig: ModelReasoningConfig?

        if id.lowercased().contains("reasoner") {
            capabilities.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .toggle)
        }

        return ModelInfo(
            id: id,
            name: id,
            capabilities: capabilities,
            contextWindow: 128000,
            reasoningConfig: reasoningConfig
        )
    }
}
