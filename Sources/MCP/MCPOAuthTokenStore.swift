import Foundation
import MCP

/// Local MCP OAuth token store.
///
/// Tokens stay on this Mac under Application Support. Keychain is not used —
/// ad-hoc / iteratively signed debug builds prompted on every SecItem read.
final class MCPOAuthTokenStore: TokenStorage, @unchecked Sendable {
    private static let lock = NSLock()
    private static let fileName = "mcp-oauth-tokens.json"

    /// Tests replace the store file so they never touch the real app-support tree.
    static var storeURLOverride: URL?

    let account: String

    init(account: String) {
        self.account = account
    }

    convenience init(endpoint: URL) {
        self.init(account: Self.account(for: endpoint))
    }

    func save(_ token: OAuthAccessToken) {
        Self.update { store in
            store[account] = token
        }
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
        MCPOAuthTokenStore(account: resourceAccount).save(token)
        delete(account: legacyServerID)
        return token
    }

    static func loadToken(account: String) -> OAuthAccessToken? {
        lock.lock()
        defer { lock.unlock() }
        return readStore()[account]
    }

    static func delete(endpoint: URL, legacyServerID: String? = nil) {
        delete(account: account(for: endpoint))
        if let legacyServerID, !legacyServerID.isEmpty {
            delete(account: legacyServerID)
        }
    }

    static func delete(account: String) {
        update { store in
            store.removeValue(forKey: account)
        }
    }

    static func move(from oldEndpoint: URL, to newEndpoint: URL) {
        let oldAccount = account(for: oldEndpoint)
        let newAccount = account(for: newEndpoint)
        guard oldAccount != newAccount, let token = loadToken(account: oldAccount) else { return }
        MCPOAuthTokenStore(account: newAccount).save(token)
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

    private static func update(_ body: (inout [String: OAuthAccessToken]) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var store = readStore()
        body(&store)
        writeStore(store)
    }

    private static func readStore() -> [String: OAuthAccessToken] {
        guard let url = try? storeURL(),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: OAuthAccessToken].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func writeStore(_ store: [String: OAuthAccessToken]) {
        guard let url = try? storeURL() else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private static func storeURL() throws -> URL {
        if let storeURLOverride {
            return storeURLOverride
        }
        return try AppDataLocations.preferencesDirectoryURL()
            .appendingPathComponent(fileName, isDirectory: false)
    }
}
