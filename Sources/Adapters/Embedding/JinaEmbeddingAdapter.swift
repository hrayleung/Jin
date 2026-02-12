import Foundation

/// Jina AI embedding adapter.
actor JinaEmbeddingAdapter: EmbeddingProviderAdapter {
    private let apiKey: String
    private let baseURL: String
    private let networkManager = NetworkManager()

    init(apiKey: String, baseURL: String = "https://api.jina.ai") {
        self.apiKey = apiKey
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    }

    func embed(texts: [String], modelID: String, inputType: EmbeddingInputType?) async throws -> EmbeddingResponse {
        let url = URL(string: "\(baseURL)/v1/embeddings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "input": texts,
            "model": modelID
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await networkManager.sendRequest(request)
        return try parseOpenAIFormatResponse(data)
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        let url = URL(string: "\(baseURL)/v1/embeddings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "input": ["test"],
            "model": "jina-embeddings-v3"
        ])

        let (_, response) = try await networkManager.sendRequest(request)
        return response.statusCode == 200
    }

    func fetchAvailableModels() async throws -> [EmbeddingModelInfo] {
        [
            EmbeddingModelInfo(id: "jina-embeddings-v3", name: "Jina Embeddings v3", dimensions: 1024, maxInputTokens: 8192)
        ]
    }

    private func parseOpenAIFormatResponse(_ data: Data) throws -> EmbeddingResponse {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let dataArray = json?["data"] as? [[String: Any]] else {
            throw LLMError.decodingError(message: "Invalid Jina embedding response format")
        }

        let embeddings = dataArray
            .sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
            .compactMap { $0["embedding"] as? [Double] }
            .map { $0.map { Float($0) } }

        let model = json?["model"] as? String ?? "unknown"
        let usage = (json?["usage"] as? [String: Any]).map {
            EmbeddingUsage(
                promptTokens: $0["prompt_tokens"] as? Int ?? 0,
                totalTokens: $0["total_tokens"] as? Int ?? 0
            )
        }

        return EmbeddingResponse(
            embeddings: embeddings,
            model: model,
            dimensions: embeddings.first?.count ?? 0,
            usage: usage
        )
    }
}
