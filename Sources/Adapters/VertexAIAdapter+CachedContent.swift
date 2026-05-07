import Foundation

extension VertexAIAdapter {
    struct CachedContentResource: Codable, Hashable, Sendable {
        let name: String
        let model: String?
        let displayName: String?
        let createTime: String?
        let updateTime: String?
        let expireTime: String?
    }

    func listCachedContents() async throws -> [CachedContentResource] {
        let token = try await getAccessToken()
        return try await cachedContentClient.listCachedContents(accessToken: token)
    }

    func getCachedContent(named name: String) async throws -> CachedContentResource {
        let token = try await getAccessToken()
        return try await cachedContentClient.getCachedContent(named: name, accessToken: token)
    }

    func createCachedContent(payload: [String: Any]) async throws -> CachedContentResource {
        let token = try await getAccessToken()
        return try await cachedContentClient.createCachedContent(payload: payload, accessToken: token)
    }

    func updateCachedContent(
        named name: String,
        payload: [String: Any],
        updateMask: String? = nil
    ) async throws -> CachedContentResource {
        let token = try await getAccessToken()
        return try await cachedContentClient.updateCachedContent(
            named: name,
            payload: payload,
            updateMask: updateMask,
            accessToken: token
        )
    }

    func deleteCachedContent(named name: String) async throws {
        let token = try await getAccessToken()
        try await cachedContentClient.deleteCachedContent(named: name, accessToken: token)
    }
}
