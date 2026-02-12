import Foundation

/// Protocol for rerank provider adapters.
protocol RerankProviderAdapter: Actor {
    /// Rerank documents by relevance to a query.
    func rerank(
        query: String,
        documents: [String],
        modelID: String,
        topN: Int?
    ) async throws -> RerankResponse

    /// Validate an API key.
    func validateAPIKey(_ key: String) async throws -> Bool

    /// Fetch available rerank models.
    func fetchAvailableModels() async throws -> [RerankModelInfo]
}

/// Response from a rerank API call.
struct RerankResponse: Sendable {
    struct Result: Sendable {
        let index: Int
        let relevanceScore: Double
    }

    /// Results sorted by relevance descending.
    let results: [Result]
}

/// Metadata about a rerank model.
struct RerankModelInfo: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let maxInputTokens: Int
}
