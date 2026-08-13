import MCP
import XCTest
@testable import Jin

final class MCPOAuthSupportTests: XCTestCase {
    func testOAuthAuthenticationRoundTripsAndHasNoResolvedHeader() throws {
        let transport: MCPTransportConfig = .http(
            MCPHTTPTransportConfig(
                endpoint: URL(string: "https://agent.tinyfish.ai/mcp")!,
                authentication: .oauth
            )
        )
        let decoded = try JSONDecoder().decode(
            MCPTransportConfig.self,
            from: try JSONEncoder().encode(transport)
        )
        guard case .http(let http) = decoded else {
            return XCTFail("Expected HTTP transport")
        }
        XCTAssertEqual(http.authentication, .oauth)
        XCTAssertNil(http.authentication.resolvedHeader)
        XCTAssertEqual(http.authentication.formFields.kind, .oauth)
        XCTAssertNil(
            MCPHTTPAuthentication.formValidationError(
                kind: .oauth,
                bearerToken: "",
                headerName: "",
                headerValue: ""
            )
        )
    }

    func testLoopbackRedirectURIUsesHTTPLocalhostAndEphemeralPort() {
        let uri = MCPOAuthLoopbackListener.makeRedirectURI()
        XCTAssertEqual(uri.scheme, "http")
        XCTAssertEqual(uri.host, "127.0.0.1")
        XCTAssertEqual(uri.path, "/callback")
        XCTAssertNotNil(uri.port)
        XCTAssertGreaterThanOrEqual(uri.port ?? 0, 49_152)
    }

    func testRedirectURIIsExtractedFromAuthorizationURL() {
        let url = URL(string: "https://auth.example.com/authorize?client_id=jin&redirect_uri=http://127.0.0.1:54321/callback&state=abc")!
        XCTAssertEqual(
            MCPOAuthLoopbackListener.redirectURI(fromAuthorizationURL: url)?.absoluteString,
            "http://127.0.0.1:54321/callback"
        )
        XCTAssertNil(MCPOAuthLoopbackListener.redirectURI(fromAuthorizationURL: URL(string: "https://auth.example.com/authorize")!))
    }

    func testHTTPRequestIsParsedIntoCallbackURL() {
        let redirect = URL(string: "http://127.0.0.1:54321/callback")!
        let request = "GET /callback?code=abc&state=xyz HTTP/1.1\r\nHost: 127.0.0.1:54321\r\n\r\n"
        XCTAssertEqual(
            MCPOAuthLoopbackListener.callbackURL(fromHTTPRequest: request, redirectURI: redirect)?.absoluteString,
            "http://127.0.0.1:54321/callback?code=abc&state=xyz"
        )
        XCTAssertNil(
            MCPOAuthLoopbackListener.callbackURL(
                fromHTTPRequest: "GET /favicon.ico HTTP/1.1\r\n\r\n",
                redirectURI: redirect
            )
        )
    }

    func testCallbackErrorQueryIsSurfaced() {
        let url = URL(string: "http://127.0.0.1:54321/callback?error=access_denied&error_description=Nope")!
        XCTAssertEqual(MCPOAuthLoopbackListener.errorMessage(fromCallback: url), "Nope")
        XCTAssertNil(MCPOAuthLoopbackListener.errorMessage(fromCallback: URL(string: "http://127.0.0.1:54321/callback?code=abc")!))
    }

    func testLegacyStoredSessionMigratesOntoSDKToken() {
        let legacy = MCPOAuthStoredSession(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            tokenType: "Bearer",
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000),
            scope: "mcp read",
            clientID: "registered-client",
            clientSecret: nil,
            tokenEndpoint: URL(string: "https://auth.example.com/token")!,
            authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
            resource: "https://agent.tinyfish.ai/mcp"
        )
        let token = MCPOAuthKeychainTokenStorage.migrate(legacy)
        XCTAssertEqual(token.value, "access-1")
        XCTAssertEqual(token.refreshToken, "refresh-1")
        XCTAssertEqual(token.clientID, "registered-client")
        XCTAssertEqual(token.scopes, ["mcp", "read"])
    }

    func testLoopbackServerCapturesAuthorizationRedirect() async throws {
        let redirect = MCPOAuthLoopbackListener.makeRedirectURI()
        let server = MCPOAuthLoopbackServer()
        try await server.start(redirectURI: redirect)
        defer { server.stop() }

        async let accepted = server.accept(timeoutSeconds: 5)
        let callbackURL = URL(string: "\(redirect.absoluteString)?code=abc&state=xyz")!
        let (data, response) = try await URLSession.shared.data(from: callbackURL)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("Signed in") == true)

        let callback = try await accepted
        XCTAssertEqual(callback.query, "code=abc&state=xyz")
    }

    func testOAuthErrorsAreMappedForUsers() {
        let mapped = MCPOAuthCoordinator.mapError(OAuthAuthorizationError.metadataDiscoveryFailed)
        XCTAssertEqual(mapped as? MCPOAuthError, .discoveryFailed(OAuthAuthorizationError.metadataDiscoveryFailed.localizedDescription))

        let passedThrough = MCPOAuthCoordinator.mapError(MCPClientError.notRunning)
        XCTAssertTrue(passedThrough is MCPClientError)
    }
}
