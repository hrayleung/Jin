import Foundation

extension GeminiAdapter {
    struct CachedContentResource: Codable, Hashable, Sendable {
        let name: String
        let model: String?
        let displayName: String?
        let createTime: String?
        let updateTime: String?
        let expireTime: String?
        let usageMetadata: UsageMetadata?

        struct UsageMetadata: Codable, Hashable, Sendable {
            let textCount: Int?
        }
    }

    func listCachedContents() async throws -> [CachedContentResource] {
        let request = NetworkRequestFactory.makeRequest(
            url: try validatedURL("\(baseURL)/cachedContents"),
            headers: geminiHeaders(accept: "application/json")
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(GeminiCachedContentsListResponse.self, from: data)
        return response.cachedContents ?? []
    }

    func getCachedContent(named name: String) async throws -> CachedContentResource {
        let path = GeminiRequestSupport.normalizedCachedContentName(name)
        let request = NetworkRequestFactory.makeRequest(
            url: try validatedURL("\(baseURL)/\(path)"),
            headers: geminiHeaders(accept: "application/json")
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CachedContentResource.self, from: data)
    }

    func createCachedContent(payload: [String: Any]) async throws -> CachedContentResource {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw LLMError.invalidRequest(message: "Invalid cachedContent payload.")
        }

        let request = try NetworkRequestFactory.makeJSONRequest(
            url: validatedURL("\(baseURL)/cachedContents"),
            headers: geminiHeaders(),
            body: payload
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CachedContentResource.self, from: data)
    }

    func updateCachedContent(
        named name: String,
        payload: [String: Any],
        updateMask: String? = nil
    ) async throws -> CachedContentResource {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw LLMError.invalidRequest(message: "Invalid cachedContent payload.")
        }

        var components = URLComponents(string: "\(baseURL)/\(GeminiRequestSupport.normalizedCachedContentName(name))")
        if let updateMask {
            components?.queryItems = [URLQueryItem(name: "updateMask", value: updateMask)]
        }
        guard let url = components?.url else {
            throw LLMError.invalidRequest(message: "Invalid cachedContent URL.")
        }

        let request = try NetworkRequestFactory.makeJSONRequest(
            url: url,
            method: "PATCH",
            headers: geminiHeaders(),
            body: payload
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CachedContentResource.self, from: data)
    }

    func deleteCachedContent(named name: String) async throws {
        let request = NetworkRequestFactory.makeRequest(
            url: try validatedURL("\(baseURL)/\(GeminiRequestSupport.normalizedCachedContentName(name))"),
            method: "DELETE",
            headers: geminiHeaders()
        )
        _ = try await networkManager.sendRequest(request)
    }
}
