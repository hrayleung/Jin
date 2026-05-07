import Foundation

extension MorphLLMAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        let body: [String: Any] = [
            "model": "auto",
            "messages": [["role": "user", "content": "hi"]],
            "max_tokens": 1,
            "stream": false
        ]

        let request = try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURLRoot)/v1/chat/completions"),
            apiKey: key,
            body: body
        )

        do {
            let (_, response) = try await networkManager.sendRequest(request)
            return response.statusCode != 401 && response.statusCode != 403
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        Self.knownModelIDs.map { makeModelInfo(id: $0) }
    }

    static let knownModelIDs: [String] = [
        "morph-v3-fast",
        "morph-v3-large",
        "auto",
    ]

    private func makeModelInfo(id: String) -> ModelInfo {
        if ModelCatalog.entry(for: id, provider: .morphllm) != nil {
            return ModelCatalog.modelInfo(for: id, provider: .morphllm)
        }

        return ModelInfo(
            id: id,
            name: id,
            capabilities: [.streaming],
            contextWindow: 128_000
        )
    }
}
