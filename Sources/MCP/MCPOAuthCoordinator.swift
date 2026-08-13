import Foundation
import MCP

struct MCPOAuthAuthorizationDelegate: OAuthAuthorizationDelegate {
    func presentAuthorizationURL(_ url: URL) async throws -> URL {
        try await MCPOAuthBrowserSession().start(authorizationURL: url)
    }
}

enum MCPOAuthCoordinator {
    private static let lock = NSLock()
    private static var authorizers: [String: OAuthAuthorizer] = [:]

    static func authorizer(for serverID: String) -> OAuthAuthorizer {
        lock.lock()
        defer { lock.unlock() }
        if let existing = authorizers[serverID] {
            return existing
        }
        let created = makeAuthorizer(serverID: serverID)
        authorizers[serverID] = created
        return created
    }

    @MainActor
    static func signIn(serverID: String, endpoint: URL) async throws {
        let authorizer = authorizer(for: serverID)
        do {
            let handled = try await authorizer.handleChallenge(
                statusCode: 401,
                headers: [:],
                endpoint: endpoint,
                operationKey: "signin",
                session: .shared
            )
            guard handled else {
                throw MCPOAuthError.authorizationFailed("The server didn’t accept browser sign-in.")
            }
        } catch {
            let mapped = mapError(error)
            if mapped is MCPOAuthError {
                throw mapped
            }
            throw MCPOAuthError.authorizationFailed(mapped.localizedDescription)
        }
        notifyChange(serverID: serverID)
    }

    static func signOut(serverID: String) {
        lock.lock()
        authorizers.removeValue(forKey: serverID)
        lock.unlock()
        MCPOAuthKeychainTokenStorage.delete(serverID: serverID)
        notifyChange(serverID: serverID)
    }

    static func status(for serverID: String) -> OAuthAccessToken? {
        MCPOAuthKeychainTokenStorage.loadToken(serverID: serverID)
    }

    static func mapError(_ error: Error) -> Error {
        if error is MCPOAuthError { return error }
        if error is CancellationError { return MCPOAuthError.cancelled }

        guard let oauth = error as? OAuthAuthorizationError else {
            return error
        }

        switch oauth {
        case .metadataDiscoveryFailed, .authorizationServerMetadataDiscoveryFailed, .missingAuthorizationServer:
            return MCPOAuthError.discoveryFailed(oauth.localizedDescription)
        case .registrationInformationRequired, .cimdNotSupported:
            return MCPOAuthError.registrationFailed(oauth.localizedDescription)
        case .tokenRequestFailed, .tokenResponseInvalid, .tokenEndpointMissing:
            return MCPOAuthError.tokenExchangeFailed(oauth.localizedDescription)
        case .authorizationResponseStateMismatch:
            return MCPOAuthError.stateMismatch
        case .authorizationResponseMissingCode, .authorizationResponseMissingState, .authorizationResponseMissingRedirectLocation:
            return MCPOAuthError.invalidCallback
        default:
            return MCPOAuthError.authorizationFailed(oauth.localizedDescription)
        }
    }

    private static func makeAuthorizer(serverID: String) -> OAuthAuthorizer {
        let stored = MCPOAuthKeychainTokenStorage.loadToken(serverID: serverID)
        let clientID = stored?.clientID?.trimmedNonEmpty ?? MCPOAuthConstants.placeholderClientID
        let configuration = OAuthConfiguration(
            grantType: .authorizationCode,
            authentication: .none(clientID: clientID),
            authorizationRedirectURI: MCPOAuthLoopbackListener.makeRedirectURI(),
            clientName: MCPOAuthConstants.clientName,
            authorizationDelegate: MCPOAuthAuthorizationDelegate()
        )
        return OAuthAuthorizer(
            configuration: configuration,
            tokenStorage: MCPOAuthKeychainTokenStorage(serverID: serverID)
        )
    }

    private static func notifyChange(serverID: String) {
        NotificationCenter.default.post(
            name: .mcpOAuthStatusDidChange,
            object: nil,
            userInfo: ["serverID": serverID]
        )
    }
}
