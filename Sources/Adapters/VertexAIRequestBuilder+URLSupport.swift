import Foundation

extension VertexAIRequestBuilder {
    func makeRequestURL(modelID: String, streaming: Bool) throws -> URL {
        let method = streaming ? "streamGenerateContent" : "generateContent"
        let endpoint = "\(baseURL)/projects/\(serviceAccountJSON.projectID)/locations/\(location)/publishers/google/models/\(modelID):\(method)"
        return try validatedURL(endpoint)
    }

    func normalizedModelID(from rawModelID: String) -> String {
        guard let trimmed = rawModelID.trimmedNonEmpty else { return rawModelID }

        let segments = trimmed
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !segments.isEmpty else { return trimmed }

        if let index = segments.lastIndex(of: "models"),
           index < segments.index(before: segments.endIndex) {
            return segments[segments.index(after: index)]
        }

        return segments.last ?? trimmed
    }

    var baseURL: String {
        if location == "global" {
            return "https://aiplatform.googleapis.com/v1"
        }
        return "https://\(location)-aiplatform.googleapis.com/v1"
    }

    var location: String {
        serviceAccountJSON.location ?? "global"
    }
}
