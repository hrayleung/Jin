import Foundation

/// OpenAI embedding adapter. Also serves as base for OpenAI-compatible endpoints.
actor OpenAIEmbeddingAdapter: EmbeddingProviderAdapter {
    private let apiKey: String
    private let baseURL: String
    private let networkManager = NetworkManager()

    init(apiKey: String, baseURL: String = "https://api.openai.com") {
        self.apiKey = apiKey
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    }

    func embed(texts: [String], modelID: String, inputType: EmbeddingInputType?) async throws -> EmbeddingResponse {
        let url = URL(string: "\(baseURL)/v1/embeddings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "input": texts,
            "model": modelID
        ]
        body["encoding_format"] = "float"

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await networkManager.sendRequest(request)
        return try parseResponse(data)
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        let url = URL(string: "\(baseURL)/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await networkManager.sendRequest(request)
        return response.statusCode == 200
    }

    func fetchAvailableModels() async throws -> [EmbeddingModelInfo] {
        [
            EmbeddingModelInfo(id: "text-embedding-3-small", name: "Text Embedding 3 Small", dimensions: 1536, maxInputTokens: 8191),
            EmbeddingModelInfo(id: "text-embedding-3-large", name: "Text Embedding 3 Large", dimensions: 3072, maxInputTokens: 8191)
        ]
    }

    private func parseResponse(_ data: Data) throws -> EmbeddingResponse {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let dataArray = json?["data"] as? [[String: Any]] else {
            throw LLMError.decodingError(message: "Invalid embedding response format")
        }

        let embeddings = dataArray
            .sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
            .compactMap { $0["embedding"] as? [Double] }
            .map { $0.map { Float($0) } }

        guard !embeddings.isEmpty else {
            throw LLMError.decodingError(message: "No embeddings in response")
        }

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
