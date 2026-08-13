import Foundation

enum MCPOAuthClient {
    static func discover(endpoint: URL, session: URLSession = .shared) async throws -> (
        resource: String,
        authorizationServer: MCPOAuthAuthorizationServerMetadata,
        scopes: [String]
    ) {
        let resource = MCPOAuthDiscovery.canonicalResource(for: endpoint)
        let metadata = try await fetchProtectedResourceMetadata(endpoint: endpoint, session: session)
        guard let issuer = metadata.authorizationServers.first else {
            throw MCPOAuthError.discoveryFailed("The server didn’t advertise an authorization server.")
        }

        let authorizationServer = try await fetchAuthorizationServerMetadata(issuer: issuer, session: session)
        if let methods = authorizationServer.codeChallengeMethodsSupported,
           !methods.contains(where: { $0.caseInsensitiveCompare("S256") == .orderedSame }) {
            throw MCPOAuthError.discoveryFailed("This authorization server doesn’t support PKCE S256.")
        }

        return (
            resource: metadata.resource ?? resource,
            authorizationServer: authorizationServer,
            scopes: metadata.scopesSupported ?? authorizationServer.scopesSupported ?? []
        )
    }

    static func registerClient(
        registrationEndpoint: URL,
        redirectURI: String,
        session: URLSession = .shared
    ) async throws -> MCPOAuthClientRegistration {
        var request = URLRequest(url: registrationEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "client_name": MCPOAuthConstants.clientName,
            "redirect_uris": [redirectURI],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none",
            "application_type": "native"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MCPOAuthError.registrationFailed("Invalid registration response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MCPOAuthError.registrationFailed(errorMessage(from: data, status: http.statusCode))
        }
        return try JSONDecoder().decode(MCPOAuthClientRegistration.self, from: data)
    }

    static func authorizationURL(
        authorizationEndpoint: URL,
        clientID: String,
        redirectURI: String,
        state: String,
        codeChallenge: String,
        resource: String,
        scope: String?
    ) throws -> URL {
        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "resource", value: resource)
        ]
        if let scope, !scope.isEmpty {
            items.append(URLQueryItem(name: "scope", value: scope))
        }
        components?.queryItems = items
        guard let url = components?.url else {
            throw MCPOAuthError.authorizationFailed("Couldn’t build the sign-in URL.")
        }
        return url
    }

    static func parseCallback(_ url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let values = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })

        if let error = values["error"] {
            let description = values["error_description"] ?? error
            throw MCPOAuthError.authorizationFailed(description)
        }
        guard let code = values["code"], !code.isEmpty else {
            throw MCPOAuthError.invalidCallback
        }
        guard values["state"] == expectedState else {
            throw MCPOAuthError.stateMismatch
        }
        return code
    }

    static func exchangeCode(
        tokenEndpoint: URL,
        code: String,
        redirectURI: String,
        clientID: String,
        clientSecret: String?,
        codeVerifier: String,
        resource: String,
        session: URLSession = .shared
    ) async throws -> MCPOAuthTokenResponse {
        var fields = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": codeVerifier,
            "resource": resource
        ]
        if let clientSecret, !clientSecret.isEmpty {
            fields["client_secret"] = clientSecret
        }
        return try await postForm(tokenEndpoint: tokenEndpoint, fields: fields, session: session)
    }

    static func refresh(
        tokenEndpoint: URL,
        refreshToken: String,
        clientID: String,
        clientSecret: String?,
        resource: String,
        session: URLSession = .shared
    ) async throws -> MCPOAuthTokenResponse {
        var fields = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "resource": resource
        ]
        if let clientSecret, !clientSecret.isEmpty {
            fields["client_secret"] = clientSecret
        }
        return try await postForm(tokenEndpoint: tokenEndpoint, fields: fields, session: session)
    }

    static func storedSession(
        from tokens: MCPOAuthTokenResponse,
        clientID: String,
        clientSecret: String?,
        tokenEndpoint: URL,
        authorizationEndpoint: URL?,
        resource: String,
        previousRefreshToken: String? = nil
    ) -> MCPOAuthStoredSession {
        let expiresAt = tokens.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        return MCPOAuthStoredSession(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken ?? previousRefreshToken,
            tokenType: tokens.tokenType ?? "Bearer",
            expiresAt: expiresAt,
            scope: tokens.scope,
            clientID: clientID,
            clientSecret: clientSecret,
            tokenEndpoint: tokenEndpoint,
            authorizationEndpoint: authorizationEndpoint,
            resource: resource
        )
    }

    private static func fetchProtectedResourceMetadata(
        endpoint: URL,
        session: URLSession
    ) async throws -> MCPOAuthProtectedResourceMetadata {
        var urls = MCPOAuthDiscovery.protectedResourceMetadataURLs(for: endpoint)
        if let challengeURL = try await resourceMetadataFromUnauthorizedProbe(endpoint: endpoint, session: session) {
            urls.insert(challengeURL, at: 0)
        }

        var lastMessage = "No protected-resource metadata was found."
        for url in urls {
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    continue
                }
                let metadata = try JSONDecoder().decode(MCPOAuthProtectedResourceMetadata.self, from: data)
                if !metadata.authorizationServers.isEmpty {
                    return metadata
                }
            } catch {
                lastMessage = error.localizedDescription
            }
        }
        throw MCPOAuthError.discoveryFailed(lastMessage)
    }

    private static func resourceMetadataFromUnauthorizedProbe(
        endpoint: URL,
        session: URLSession
    ) async throws -> URL? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"Jin","version":"0.1.0"}}}"#.utf8)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 401,
              let header = http.value(forHTTPHeaderField: "WWW-Authenticate") else {
            return nil
        }
        return MCPOAuthDiscovery.resourceMetadataURL(fromWWWAuthenticate: header)
    }

    private static func fetchAuthorizationServerMetadata(
        issuer: URL,
        session: URLSession
    ) async throws -> MCPOAuthAuthorizationServerMetadata {
        var lastMessage = "No authorization-server metadata was found."
        for url in MCPOAuthDiscovery.authorizationServerMetadataURLs(for: issuer) {
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    continue
                }
                return try JSONDecoder().decode(MCPOAuthAuthorizationServerMetadata.self, from: data)
            } catch {
                lastMessage = error.localizedDescription
            }
        }
        throw MCPOAuthError.discoveryFailed(lastMessage)
    }

    private static func postForm(
        tokenEndpoint: URL,
        fields: [String: String],
        session: URLSession
    ) async throws -> MCPOAuthTokenResponse {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formURLEncoded(fields)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MCPOAuthError.tokenExchangeFailed("Invalid token response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MCPOAuthError.tokenExchangeFailed(errorMessage(from: data, status: http.statusCode))
        }
        return try JSONDecoder().decode(MCPOAuthTokenResponse.self, from: data)
    }

    private static func formURLEncoded(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))
        let body = fields
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private static func errorMessage(from data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let description = object["error_description"] as? String, !description.isEmpty {
                return description
            }
            if let error = object["error"] as? String, !error.isEmpty {
                return error
            }
        }
        if let text = String(data: data, encoding: .utf8)?.trimmedNonEmpty {
            return text
        }
        return "HTTP \(status)"
    }
}
