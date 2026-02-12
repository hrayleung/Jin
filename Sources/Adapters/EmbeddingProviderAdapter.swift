import Foundation

/// Protocol for embedding provider adapters.
protocol EmbeddingProviderAdapter: Actor {
    /// Generate embeddings for the given texts.
    func embed(
        texts: [String],
        modelID: String,
        inputType: EmbeddingInputType?
    ) async throws -> EmbeddingResponse

    /// Validate an API key.
    func validateAPIKey(_ key: String) async throws -> Bool

    /// Fetch available embedding models.
    func fetchAvailableModels() async throws -> [EmbeddingModelInfo]
}

/// Input type hint for embedding models that support it.
enum EmbeddingInputType: String, Codable {
    case searchDocument = "search_document"
    case searchQuery = "search_query"
}

/// Response from an embedding API call.
struct EmbeddingResponse: Sendable {
    let embeddings: [[Float]]
    let model: String
    let dimensions: Int
    let usage: EmbeddingUsage?
}

/// Token usage from an embedding API call.
struct EmbeddingUsage: Sendable {
    let promptTokens: Int
    let totalTokens: Int
}

/// Metadata about an embedding model.
struct EmbeddingModelInfo: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let dimensions: Int
    let maxInputTokens: Int
}

/// Embedding provider type.
enum EmbeddingProviderType: String, Codable, CaseIterable {
    case openai
    case cohere
    case voyage
    case jina
    case gemini
    case openaiCompatible

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .cohere: return "Cohere"
        case .voyage: return "Voyage AI"
        case .jina: return "Jina AI"
        case .gemini: return "Gemini"
        case .openaiCompatible: return "OpenAI Compatible"
        }
    }

    var defaultBaseURL: String? {
        switch self {
        case .openai: return "https://api.openai.com"
        case .cohere: return "https://api.cohere.com"
        case .voyage: return "https://api.voyageai.com"
        case .jina: return "https://api.jina.ai"
        case .gemini: return "https://generativelanguage.googleapis.com"
        case .openaiCompatible: return nil
        }
    }
}

/// Rerank provider type.
enum RerankProviderType: String, Codable, CaseIterable {
    case cohere
    case voyage
    case jina

    var displayName: String {
        switch self {
        case .cohere: return "Cohere"
        case .voyage: return "Voyage AI"
        case .jina: return "Jina AI"
        }
    }

    var defaultBaseURL: String? {
        switch self {
        case .cohere: return "https://api.cohere.com"
        case .voyage: return "https://api.voyageai.com"
        case .jina: return "https://api.jina.ai"
        }
    }
}
