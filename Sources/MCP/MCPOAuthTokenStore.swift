import Foundation
import MCP
import Security

final class MCPOAuthKeychainTokenStorage: TokenStorage, @unchecked Sendable {
    private static let service = "com.jin.app.mcp.oauth"

    let serverID: String

    init(serverID: String) {
        self.serverID = serverID
    }

    func save(_ token: OAuthAccessToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        Self.delete(serverID: serverID)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: serverID,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func load() -> OAuthAccessToken? {
        Self.loadToken(serverID: serverID)
    }

    func clear() {
        Self.delete(serverID: serverID)
    }

    static func loadToken(serverID: String) -> OAuthAccessToken? {
        guard let data = loadData(serverID: serverID) else { return nil }
        if let token = try? JSONDecoder().decode(OAuthAccessToken.self, from: data) {
            return token
        }
        if let legacy = try? JSONDecoder().decode(MCPOAuthStoredSession.self, from: data) {
            let token = migrate(legacy)
            MCPOAuthKeychainTokenStorage(serverID: serverID).save(token)
            return token
        }
        return nil
    }

    static func delete(serverID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverID
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func move(from oldServerID: String, to newServerID: String) {
        guard oldServerID != newServerID, let token = loadToken(serverID: oldServerID) else { return }
        let storage = MCPOAuthKeychainTokenStorage(serverID: newServerID)
        storage.save(token)
        delete(serverID: oldServerID)
    }

    static func migrate(_ session: MCPOAuthStoredSession) -> OAuthAccessToken {
        let scopes = Set(
            (session.scope ?? "")
                .split(separator: " ")
                .map(String.init)
                .filter { !$0.isEmpty }
        )
        return OAuthAccessToken(
            value: session.accessToken,
            tokenType: session.tokenType,
            expiresAt: session.expiresAt,
            scopes: scopes,
            authorizationServer: nil,
            refreshToken: session.refreshToken,
            clientID: session.clientID.trimmedNonEmpty
        )
    }

    private static func loadData(serverID: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }
}
