import Foundation

/// Jina AI rerank adapter.
actor JinaRerankAdapter: RerankProviderAdapter {
    private let apiKey: String
    private let baseURL: String
    private let networkManager = NetworkManager()

    init(apiKey: String, baseURL: String = "https://api.jina.ai") {
        self.apiKey = apiKey
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    }

    func rerank(query: String, documents: [String], modelID: String, topN: Int?) async throws -> RerankResponse {
        let url = URL(string: "\(baseURL)/v1/rerank")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "query": query,
            "documents": documents,
            "model": modelID
        ]

        if let topN {
            body["top_n"] = topN
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await networkManager.sendRequest(request)
        return try parseResponse(data)
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        let url = URL(string: "\(baseURL)/v1/rerank")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": "test",
            "documents": ["test document"],
            "model": "jina-reranker-v2-base-multilingual"
        ])

        let (_, response) = try await networkManager.sendRequest(request)
        return response.statusCode == 200
    }

    func fetchAvailableModels() async throws -> [RerankModelInfo] {
        [
            RerankModelInfo(id: "jina-reranker-v2-base-multilingual", name: "Jina Reranker v2 Multilingual", maxInputTokens: 8192)
        ]
    }

    private func parseResponse(_ data: Data) throws -> RerankResponse {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let results = json?["results"] as? [[String: Any]] else {
            throw LLMError.decodingError(message: "Invalid Jina rerank response format")
        }

        let parsed = results.compactMap { result -> RerankResponse.Result? in
            guard let index = result["index"] as? Int,
                  let score = result["relevance_score"] as? Double else {
                return nil
            }
            return RerankResponse.Result(index: index, relevanceScore: score)
        }
        .sorted { $0.relevanceScore > $1.relevanceScore }

        return RerankResponse(results: parsed)
    }
}
