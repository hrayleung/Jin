import Foundation
import MCP
import Security

final class MCPOAuthKeychainTokenStorage: TokenStorage, @unchecked Sendable {
    private static let service = "com.jin.app.mcp.oauth"

    let account: String

    init(account: String) {
        self.account = account
    }

    convenience init(endpoint: URL) {
        self.init(account: Self.account(for: endpoint))
    }

    func save(_ token: OAuthAccessToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        Self.delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func load() -> OAuthAccessToken? {
        Self.loadToken(account: account)
    }

    func clear() {
        Self.delete(account: account)
    }

    static func account(for endpoint: URL) -> String {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        var value = (components?.string ?? endpoint.absoluteString).trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count > 1, value.hasSuffix("/") {
            value.removeLast()
        }
        return value.lowercased()
    }

    static func loadToken(endpoint: URL, legacyServerID: String? = nil) -> OAuthAccessToken? {
        let resourceAccount = account(for: endpoint)
        if let token = loadToken(account: resourceAccount) {
            return token
        }
        guard let legacyServerID, !legacyServerID.isEmpty, legacyServerID != resourceAccount else {
            return nil
        }
        guard let token = loadToken(account: legacyServerID) else { return nil }
        MCPOAuthKeychainTokenStorage(account: resourceAccount).save(token)
        delete(account: legacyServerID)
        return token
    }

    static func loadToken(account: String) -> OAuthAccessToken? {
        guard let data = loadData(account: account) else { return nil }
        if let token = try? JSONDecoder().decode(OAuthAccessToken.self, from: data) {
            return token
        }
        if let legacy = try? JSONDecoder().decode(MCPOAuthStoredSession.self, from: data) {
            let token = migrate(legacy)
            MCPOAuthKeychainTokenStorage(account: account).save(token)
            return token
        }
        return nil
    }

    static func delete(endpoint: URL, legacyServerID: String? = nil) {
        delete(account: account(for: endpoint))
        if let legacyServerID, !legacyServerID.isEmpty {
            delete(account: legacyServerID)
        }
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func move(from oldEndpoint: URL, to newEndpoint: URL) {
        let oldAccount = account(for: oldEndpoint)
        let newAccount = account(for: newEndpoint)
        guard oldAccount != newAccount, let token = loadToken(account: oldAccount) else { return }
        MCPOAuthKeychainTokenStorage(account: newAccount).save(token)
        delete(account: oldAccount)
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

    private static func loadData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }
}
