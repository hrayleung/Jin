import Foundation

extension Notification.Name {
    static let mcpOAuthStatusDidChange = Notification.Name("mcpOAuthStatusDidChange")
}

enum MCPOAuthCoordinator {
    @MainActor
    static func signIn(serverID: String, endpoint: URL) async throws {
        let discovery = try await MCPOAuthClient.discover(endpoint: endpoint)
        let redirectURI = MCPOAuthConstants.redirectURI

        let registration: MCPOAuthClientRegistration
        if let registrationEndpoint = discovery.authorizationServer.registrationEndpoint {
            registration = try await MCPOAuthClient.registerClient(
                registrationEndpoint: registrationEndpoint,
                redirectURI: redirectURI
            )
        } else {
            throw MCPOAuthError.registrationFailed("No dynamic client registration endpoint was advertised.")
        }

        let verifier = MCPOAuthPKCE.makeVerifier()
        let state = MCPOAuthPKCE.makeState()
        let challenge = MCPOAuthPKCE.challenge(for: verifier)
        let scope = discovery.scopes.isEmpty ? nil : discovery.scopes.joined(separator: " ")

        let authorizationURL = try MCPOAuthClient.authorizationURL(
            authorizationEndpoint: discovery.authorizationServer.authorizationEndpoint,
            clientID: registration.clientID,
            redirectURI: redirectURI,
            state: state,
            codeChallenge: challenge,
            resource: discovery.resource,
            scope: scope
        )

        let callbackURL = try await MCPOAuthBrowserSession().start(url: authorizationURL)
        let code = try MCPOAuthClient.parseCallback(callbackURL, expectedState: state)

        let tokens = try await MCPOAuthClient.exchangeCode(
            tokenEndpoint: discovery.authorizationServer.tokenEndpoint,
            code: code,
            redirectURI: redirectURI,
            clientID: registration.clientID,
            clientSecret: registration.clientSecret,
            codeVerifier: verifier,
            resource: discovery.resource
        )

        let stored = MCPOAuthClient.storedSession(
            from: tokens,
            clientID: registration.clientID,
            clientSecret: registration.clientSecret,
            tokenEndpoint: discovery.authorizationServer.tokenEndpoint,
            authorizationEndpoint: discovery.authorizationServer.authorizationEndpoint,
            resource: discovery.resource
        )
        try MCPOAuthTokenStore.save(stored, serverID: serverID)
        notifyChange(serverID: serverID)
    }

    static func signOut(serverID: String) {
        MCPOAuthTokenStore.delete(serverID: serverID)
        notifyChange(serverID: serverID)
    }

    static func validAccessToken(for serverID: String, endpoint: URL) async throws -> String {
        guard var session = MCPOAuthTokenStore.load(serverID: serverID) else {
            throw MCPOAuthError.notAuthenticated
        }

        if session.isExpired {
            guard let refreshToken = session.refreshToken else {
                throw MCPOAuthError.notAuthenticated
            }
            let tokens = try await MCPOAuthClient.refresh(
                tokenEndpoint: session.tokenEndpoint,
                refreshToken: refreshToken,
                clientID: session.clientID,
                clientSecret: session.clientSecret,
                resource: session.resource
            )
            session = MCPOAuthClient.storedSession(
                from: tokens,
                clientID: session.clientID,
                clientSecret: session.clientSecret,
                tokenEndpoint: session.tokenEndpoint,
                authorizationEndpoint: session.authorizationEndpoint,
                resource: session.resource,
                previousRefreshToken: refreshToken
            )
            try MCPOAuthTokenStore.save(session, serverID: serverID)
            notifyChange(serverID: serverID)
        }

        guard let token = session.accessToken.trimmedNonEmpty else {
            throw MCPOAuthError.notAuthenticated
        }
        _ = endpoint
        return token
    }

    static func status(for serverID: String) -> MCPOAuthStoredSession? {
        MCPOAuthTokenStore.load(serverID: serverID)
    }

    private static func notifyChange(serverID: String) {
        NotificationCenter.default.post(
            name: .mcpOAuthStatusDidChange,
            object: nil,
            userInfo: ["serverID": serverID]
        )
    }
}
