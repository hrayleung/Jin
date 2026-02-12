import Foundation

/// Factory for creating embedding provider adapters.
actor EmbeddingProviderManager {
    /// Create an embedding adapter for the given configuration.
    func createAdapter(for config: EmbeddingProviderConfigEntity) throws -> any EmbeddingProviderAdapter {
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            throw LLMError.authenticationFailed(message: "API key not configured for embedding provider \(config.name)")
        }

        guard let providerType = EmbeddingProviderType(rawValue: config.typeRaw) else {
            throw LLMError.invalidRequest(message: "Unknown embedding provider type: \(config.typeRaw)")
        }

        let baseURL = config.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch providerType {
        case .openai:
            return OpenAIEmbeddingAdapter(
                apiKey: apiKey,
                baseURL: baseURL ?? "https://api.openai.com"
            )
        case .cohere:
            return CohereEmbeddingAdapter(
                apiKey: apiKey,
                baseURL: baseURL ?? "https://api.cohere.com"
            )
        case .voyage:
            return VoyageEmbeddingAdapter(
                apiKey: apiKey,
                baseURL: baseURL ?? "https://api.voyageai.com"
            )
        case .jina:
            return JinaEmbeddingAdapter(
                apiKey: apiKey,
                baseURL: baseURL ?? "https://api.jina.ai"
            )
        case .gemini:
            return GeminiEmbeddingAdapter(
                apiKey: apiKey,
                baseURL: baseURL ?? "https://generativelanguage.googleapis.com"
            )
        case .openaiCompatible:
            guard let customBaseURL = baseURL, !customBaseURL.isEmpty else {
                throw LLMError.invalidRequest(message: "Base URL required for OpenAI-compatible embedding provider")
            }
            return OpenAICompatibleEmbeddingAdapter(
                apiKey: apiKey,
                baseURL: customBaseURL
            )
        }
    }
}
