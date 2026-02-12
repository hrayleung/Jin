import Foundation

/// Factory for creating rerank provider adapters.
actor RerankProviderManager {
    /// Create a rerank adapter for the given configuration.
    func createAdapter(for config: RerankProviderConfigEntity) throws -> any RerankProviderAdapter {
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            throw LLMError.authenticationFailed(message: "API key not configured for rerank provider \(config.name)")
        }

        guard let providerType = RerankProviderType(rawValue: config.typeRaw) else {
            throw LLMError.invalidRequest(message: "Unknown rerank provider type: \(config.typeRaw)")
        }

        let baseURL = config.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch providerType {
        case .cohere:
            return CohereRerankAdapter(
                apiKey: apiKey,
                baseURL: baseURL ?? "https://api.cohere.com"
            )
        case .voyage:
            return VoyageRerankAdapter(
                apiKey: apiKey,
                baseURL: baseURL ?? "https://api.voyageai.com"
            )
        case .jina:
            return JinaRerankAdapter(
                apiKey: apiKey,
                baseURL: baseURL ?? "https://api.jina.ai"
            )
        }
    }
}
