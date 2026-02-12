import Foundation

/// Cohere rerank adapter using the v2/rerank endpoint.
actor CohereRerankAdapter: RerankProviderAdapter {
    private let apiKey: String
    private let baseURL: String
    private let networkManager = NetworkManager()

    init(apiKey: String, baseURL: String = "https://api.cohere.com") {
        self.apiKey = apiKey
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    }

    func rerank(query: String, documents: [String], modelID: String, topN: Int?) async throws -> RerankResponse {
        let url = URL(string: "\(baseURL)/v2/rerank")!
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
        let url = URL(string: "\(baseURL)/v2/rerank")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": "test",
            "documents": ["test document"],
            "model": "rerank-v3.5"
        ])

        let (_, response) = try await networkManager.sendRequest(request)
        return response.statusCode == 200
    }

    func fetchAvailableModels() async throws -> [RerankModelInfo] {
        [
            RerankModelInfo(id: "rerank-v3.5", name: "Rerank v3.5", maxInputTokens: 4096),
            RerankModelInfo(id: "rerank-english-v3.0", name: "Rerank English v3.0", maxInputTokens: 4096)
        ]
    }

    private func parseResponse(_ data: Data) throws -> RerankResponse {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let results = json?["results"] as? [[String: Any]] else {
            throw LLMError.decodingError(message: "Invalid Cohere rerank response format")
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
