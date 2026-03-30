import Foundation

struct VertexAICachedContentClient {
    private let serviceAccountJSON: ServiceAccountCredentials
    private let networkManager: NetworkManager

    init(
        serviceAccountJSON: ServiceAccountCredentials,
        networkManager: NetworkManager
    ) {
        self.serviceAccountJSON = serviceAccountJSON
        self.networkManager = networkManager
    }

    func listCachedContents(accessToken: String) async throws -> [VertexAIAdapter.CachedContentResource] {
        var allCachedContents: [VertexAIAdapter.CachedContentResource] = []
        var seenPageTokens = Set<String>()
        var nextPageToken: String?

        repeat {
            let response = try await listCachedContentsPage(
                accessToken: accessToken,
                pageToken: nextPageToken
            )
            allCachedContents.append(contentsOf: response.cachedContents ?? [])

            let upcomingPageToken = normalizedPageToken(response.nextPageToken)
            if let upcomingPageToken,
               !seenPageTokens.insert(upcomingPageToken).inserted {
                break
            }
            nextPageToken = upcomingPageToken
        } while nextPageToken != nil

        return allCachedContents
    }

    func getCachedContent(named name: String, accessToken: String) async throws -> VertexAIAdapter.CachedContentResource {
        let request = NetworkRequestFactory.makeRequest(
            url: try cachedContentURL(named: name),
            headers: vertexHeaders(accessToken: accessToken, accept: "application/json")
        )
        let (data, _) = try await networkManager.sendRequest(request)
        return try decode(VertexAIAdapter.CachedContentResource.self, from: data)
    }

    func createCachedContent(
        payload: [String: Any],
        accessToken: String
    ) async throws -> VertexAIAdapter.CachedContentResource {
        try validate(payload: payload)
        let request = try NetworkRequestFactory.makeJSONRequest(
            url: validatedURL(cachedContentsCollectionEndpoint),
            headers: vertexHeaders(accessToken: accessToken),
            body: payload
        )
        let (data, _) = try await networkManager.sendRequest(request)
        return try decode(VertexAIAdapter.CachedContentResource.self, from: data)
    }

    func updateCachedContent(
        named name: String,
        payload: [String: Any],
        updateMask: String? = nil,
        accessToken: String
    ) async throws -> VertexAIAdapter.CachedContentResource {
        try validate(payload: payload)
        let request = try NetworkRequestFactory.makeJSONRequest(
            url: try cachedContentURL(named: name, updateMask: updateMask),
            method: "PATCH",
            headers: vertexHeaders(accessToken: accessToken),
            body: payload
        )
        let (data, _) = try await networkManager.sendRequest(request)
        return try decode(VertexAIAdapter.CachedContentResource.self, from: data)
    }

    func deleteCachedContent(named name: String, accessToken: String) async throws {
        let request = NetworkRequestFactory.makeRequest(
            url: try cachedContentURL(named: name),
            method: "DELETE",
            headers: vertexHeaders(accessToken: accessToken)
        )
        _ = try await networkManager.sendRequest(request)
    }

    func cachedContentURL(named rawName: String) throws -> URL {
        try validatedURL(cachedContentEndpoint(for: rawName))
    }

    private func cachedContentURL(named rawName: String, updateMask: String?) throws -> URL {
        guard var components = URLComponents(string: cachedContentEndpoint(for: rawName)) else {
            throw LLMError.invalidRequest(message: "Invalid cachedContent URL.")
        }
        if let updateMask {
            components.queryItems = [URLQueryItem(name: "updateMask", value: updateMask)]
        }
        guard let url = components.url else {
            throw LLMError.invalidRequest(message: "Invalid cachedContent URL.")
        }
        return url
    }

    private func listCachedContentsPage(
        accessToken: String,
        pageToken: String?
    ) async throws -> VertexCachedContentsListResponse {
        let request = NetworkRequestFactory.makeRequest(
            url: try cachedContentsURL(pageToken: pageToken),
            headers: vertexHeaders(accessToken: accessToken, accept: "application/json")
        )
        let (data, _) = try await networkManager.sendRequest(request)
        return try decode(VertexCachedContentsListResponse.self, from: data)
    }

    private func cachedContentsURL(pageToken: String?) throws -> URL {
        guard var components = URLComponents(string: cachedContentsCollectionEndpoint) else {
            throw LLMError.invalidRequest(message: "Invalid cachedContents URL.")
        }

        if let pageToken = normalizedPageToken(pageToken) {
            components.queryItems = [URLQueryItem(name: "pageToken", value: pageToken)]
        }

        guard let url = components.url else {
            throw LLMError.invalidRequest(message: "Invalid cachedContents URL.")
        }
        return url
    }

    private func normalizedPageToken(_ pageToken: String?) -> String? {
        let trimmed = pageToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }

    private func validate(payload: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw LLMError.invalidRequest(message: "Invalid cachedContent payload.")
        }
    }

    private func vertexHeaders(
        accessToken: String,
        accept: String? = nil,
        contentType: String? = nil
    ) -> [String: String] {
        var headers: [String: String] = ["Authorization": "Bearer \(accessToken)"]
        if let accept {
            headers["Accept"] = accept
        }
        if let contentType {
            headers["Content-Type"] = contentType
        }
        return headers
    }

    private func cachedContentEndpoint(for rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("projects/") {
            return "\(baseURL)/\(trimmed)"
        }
        return "\(cachedContentsCollectionEndpoint)/\(trimmed)"
    }

    private var cachedContentsCollectionEndpoint: String {
        "\(baseURL)/projects/\(serviceAccountJSON.projectID)/locations/\(location)/cachedContents"
    }

    private var baseURL: String {
        if location == "global" {
            return "https://aiplatform.googleapis.com/v1"
        }
        return "https://\(location)-aiplatform.googleapis.com/v1"
    }

    private var location: String {
        serviceAccountJSON.location ?? "global"
    }
}
