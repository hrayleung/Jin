import Foundation
import MCP

struct MCPOAuthAuthorizationDelegate: OAuthAuthorizationDelegate {
    func presentAuthorizationURL(_ url: URL) async throws -> URL {
        try await MCPOAuthBrowserSession().start(authorizationURL: url)
    }
}

enum MCPOAuthCoordinator {
    static func authorizer(for endpoint: URL, legacyServerID: String? = nil) -> OAuthAuthorizer {
        _ = MCPOAuthTokenStore.loadToken(endpoint: endpoint, legacyServerID: legacyServerID)
        return makeAuthorizer(endpoint: endpoint)
    }

    @MainActor
    static func signIn(endpoint: URL, legacyServerID: String? = nil) async throws {
        let challenge = await probeChallenge(endpoint: endpoint)
        let authorizer = authorizer(for: endpoint, legacyServerID: legacyServerID)
        do {
            let handled = try await authorizer.handleChallenge(
                statusCode: challenge.statusCode,
                headers: challenge.headers,
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
        notifyChange(endpoint: endpoint)
    }

    static func signOut(endpoint: URL, legacyServerID: String? = nil) {
        MCPOAuthTokenStore.delete(endpoint: endpoint, legacyServerID: legacyServerID)
        notifyChange(endpoint: endpoint)
    }

    static func status(for endpoint: URL, legacyServerID: String? = nil) -> OAuthAccessToken? {
        MCPOAuthTokenStore.loadToken(endpoint: endpoint, legacyServerID: legacyServerID)
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
        case .pkceCodeChallengeMethodsMissing, .pkceS256NotSupported:
            return MCPOAuthError.authorizationFailed(
                "This server doesn’t support MCP’s required PKCE S256 browser flow. Use a token or API key instead."
            )
        case .protectedResourceMismatch:
            return MCPOAuthError.authorizationFailed(
                "Sign-in used metadata from a different MCP server. Choose the server again, then sign in."
            )
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

    private static func makeAuthorizer(endpoint: URL) -> OAuthAuthorizer {
        let stored = MCPOAuthTokenStore.loadToken(endpoint: endpoint)
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
            tokenStorage: MCPOAuthTokenStore(endpoint: endpoint)
        )
    }

    /// Asks the MCP endpoint for a 401 so we can pass `WWW-Authenticate` into the SDK.
    private static func probeChallenge(endpoint: URL) async -> (statusCode: Int, headers: [String: String]) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"Jin","version":"0.1.0"}}}"#.utf8
        )

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return (401, [:])
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                guard let name = key as? String else { continue }
                headers[name] = String(describing: value)
            }
            let status = (400...499).contains(http.statusCode) ? http.statusCode : 401
            return (status == 403 ? 403 : 401, headers)
        } catch {
            return (401, [:])
        }
    }

    private static func notifyChange(endpoint: URL) {
        NotificationCenter.default.post(
            name: .mcpOAuthStatusDidChange,
            object: nil,
            userInfo: ["endpoint": MCPOAuthTokenStore.account(for: endpoint)]
        )
    }
}
