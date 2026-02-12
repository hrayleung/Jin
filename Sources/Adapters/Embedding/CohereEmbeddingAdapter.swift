import Foundation

/// Cohere embedding adapter using the v2/embed endpoint.
actor CohereEmbeddingAdapter: EmbeddingProviderAdapter {
    private let apiKey: String
    private let baseURL: String
    private let networkManager = NetworkManager()

    init(apiKey: String, baseURL: String = "https://api.cohere.com") {
        self.apiKey = apiKey
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    }

    func embed(texts: [String], modelID: String, inputType: EmbeddingInputType?) async throws -> EmbeddingResponse {
        let url = URL(string: "\(baseURL)/v2/embed")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "texts": texts,
            "model": modelID,
            "embedding_types": ["float"]
        ]

        if let inputType {
            body["input_type"] = inputType.rawValue
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await networkManager.sendRequest(request)
        return try parseResponse(data)
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        let url = URL(string: "\(baseURL)/v2/embed")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "texts": ["test"],
            "model": "embed-english-v3.0",
            "embedding_types": ["float"],
            "input_type": "search_query"
        ])

        let (_, response) = try await networkManager.sendRequest(request)
        return response.statusCode == 200
    }

    func fetchAvailableModels() async throws -> [EmbeddingModelInfo] {
        [
            EmbeddingModelInfo(id: "embed-v4.0", name: "Embed v4.0", dimensions: 1024, maxInputTokens: 128000),
            EmbeddingModelInfo(id: "embed-english-v3.0", name: "Embed English v3.0", dimensions: 1024, maxInputTokens: 512),
            EmbeddingModelInfo(id: "embed-multilingual-v3.0", name: "Embed Multilingual v3.0", dimensions: 1024, maxInputTokens: 512)
        ]
    }

    private func parseResponse(_ data: Data) throws -> EmbeddingResponse {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Cohere v2 returns embeddings under "embeddings" -> "float"
        guard let embeddingsObj = json?["embeddings"] as? [String: Any],
              let floatEmbeddings = embeddingsObj["float"] as? [[Double]] else {
            throw LLMError.decodingError(message: "Invalid Cohere embedding response format")
        }

        let embeddings = floatEmbeddings.map { $0.map { Float($0) } }
        let model = json?["model"] as? String ?? "unknown"
        let meta = json?["meta"] as? [String: Any]
        let billedUnits = meta?["billed_units"] as? [String: Any]

        let usage = billedUnits.map {
            EmbeddingUsage(
                promptTokens: $0["input_tokens"] as? Int ?? 0,
                totalTokens: $0["input_tokens"] as? Int ?? 0
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
