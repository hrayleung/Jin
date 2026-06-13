import Foundation

extension VertexAIRequestBuilder {
    func makeRequestURL(modelID: String, streaming: Bool) throws -> URL {
        let method = streaming ? "streamGenerateContent" : "generateContent"
        return try validatedURL(modelEndpoint(modelID: modelID, verb: method))
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

    /// Assembles the canonical Vertex AI model endpoint path.
    func modelEndpoint(modelID: String, verb: String) -> String {
        "\(serviceAccountJSON.vertexBaseURL)/projects/\(serviceAccountJSON.projectID)/locations/\(serviceAccountJSON.resolvedLocation)/publishers/google/models/\(modelID):\(verb)"
    }

    var baseURL: String { serviceAccountJSON.vertexBaseURL }
    var location: String { serviceAccountJSON.resolvedLocation }
}
