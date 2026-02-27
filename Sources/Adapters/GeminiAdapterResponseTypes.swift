import Foundation

// MARK: - Gemini-specific DTOs

struct GeminiCachedContentsListResponse: Codable {
    let cachedContents: [GeminiAdapter.CachedContentResource]?
    let nextPageToken: String?
}

struct GeminiListModelsResponse: Codable {
    let models: [GeminiModel]
    let nextPageToken: String?

    struct GeminiModel: Codable {
        let name: String
        let displayName: String?
        let description: String?
        let inputTokenLimit: Int?
        let outputTokenLimit: Int?
        let supportedGenerationMethods: [String]?

        var id: String {
            if name.lowercased().hasPrefix("models/") {
                return String(name.dropFirst("models/".count))
            }
            return name
        }
    }
}

/// Gemini uses the shared Google generateContent response format.
typealias GeminiGenerateContentResponse = GoogleGenerateContentResponse
