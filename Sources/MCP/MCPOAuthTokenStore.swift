import Foundation
import Security

enum MCPOAuthTokenStore {
    private static let service = "com.jin.app.mcp.oauth"

    static func load(serverID: String) -> MCPOAuthStoredSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(MCPOAuthStoredSession.self, from: data)
    }

    static func save(_ session: MCPOAuthStoredSession, serverID: String) throws {
        let data = try JSONEncoder().encode(session)
        delete(serverID: serverID)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverID,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw MCPOAuthError.tokenExchangeFailed("Couldn’t save the signed-in session.")
        }
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
        guard oldServerID != newServerID, let session = load(serverID: oldServerID) else { return }
        try? save(session, serverID: newServerID)
        delete(serverID: oldServerID)
    }

    static func isSignedIn(serverID: String) -> Bool {
        load(serverID: serverID)?.accessToken.trimmedNonEmpty != nil
    }
}
