import Foundation

// MARK: - Vertex AI-specific DTOs

struct VertexCachedContentsListResponse: Codable {
    let cachedContents: [VertexAIAdapter.CachedContentResource]?
    let nextPageToken: String?
}

/// Vertex AI uses the shared Google generateContent response format.
typealias VertexGenerateContentResponse = GoogleGenerateContentResponse
