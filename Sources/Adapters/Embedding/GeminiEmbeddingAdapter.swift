import Foundation

/// Gemini embedding adapter using the embedContent endpoint.
actor GeminiEmbeddingAdapter: EmbeddingProviderAdapter {
    private let apiKey: String
    private let baseURL: String
    private let networkManager = NetworkManager()

    init(apiKey: String, baseURL: String = "https://generativelanguage.googleapis.com") {
        self.apiKey = apiKey
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    }

    func embed(texts: [String], modelID: String, inputType: EmbeddingInputType?) async throws -> EmbeddingResponse {
        // Gemini uses batchEmbedContents for multiple texts
        let url = URL(string: "\(baseURL)/v1beta/models/\(modelID):batchEmbedContents?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requests = texts.map { text -> [String: Any] in
            [
                "model": "models/\(modelID)",
                "content": ["parts": [["text": text]]]
            ]
        }

        let body: [String: Any] = ["requests": requests]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await networkManager.sendRequest(request)
        return try parseResponse(data, modelID: modelID)
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        let url = URL(string: "\(baseURL)/v1beta/models?key=\(key)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (_, response) = try await networkManager.sendRequest(request)
        return response.statusCode == 200
    }

    func fetchAvailableModels() async throws -> [EmbeddingModelInfo] {
        [
            EmbeddingModelInfo(id: "text-embedding-004", name: "Text Embedding 004", dimensions: 768, maxInputTokens: 2048)
        ]
    }

    private func parseResponse(_ data: Data, modelID: String) throws -> EmbeddingResponse {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let embeddingsArray = json?["embeddings"] as? [[String: Any]] else {
            throw LLMError.decodingError(message: "Invalid Gemini embedding response format")
        }

        let embeddings = embeddingsArray.compactMap { obj -> [Float]? in
            guard let values = obj["values"] as? [Double] else { return nil }
            return values.map { Float($0) }
        }

        return EmbeddingResponse(
            embeddings: embeddings,
            model: modelID,
            dimensions: embeddings.first?.count ?? 0,
            usage: nil
        )
    }
}
