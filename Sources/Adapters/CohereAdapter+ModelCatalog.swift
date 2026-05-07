import Foundation

extension CohereAdapter {
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
            includeUserAgent: false
        )

        let (data, _) = try await networkManager.sendRequest(request)

        // Cohere models response isn't OpenAI-shaped; parse defensively.
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let models = json["models"] as? [[String: Any]] {
                let ids = models.compactMap { dict in
                    (dict["name"] as? String)
                        ?? (dict["id"] as? String)
                        ?? (dict["model"] as? String)
                }
                if !ids.isEmpty {
                    return ids.map(makeModelInfo(id:))
                }
            }

            if let dataModels = json["data"] as? [[String: Any]] {
                let ids = dataModels.compactMap { dict in
                    (dict["id"] as? String)
                        ?? (dict["name"] as? String)
                        ?? (dict["model"] as? String)
                }
                if !ids.isEmpty {
                    return ids.map(makeModelInfo(id:))
                }
            }
        }

        return providerConfig.models
    }

    private func makeModelInfo(id: String) -> ModelInfo {
        ModelInfo(
            id: id,
            name: id,
            capabilities: [.streaming, .toolCalling],
            contextWindow: 128_000,
            reasoningConfig: nil,
            isEnabled: true
        )
    }
}
