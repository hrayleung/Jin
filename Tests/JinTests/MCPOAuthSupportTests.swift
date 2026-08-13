import XCTest
@testable import Jin

final class MCPOAuthSupportTests: XCTestCase {
    func testWWWAuthenticateExtractsResourceMetadataURL() {
        let header = #"Bearer realm="mcp", resource_metadata="https://mcp.example.com/.well-known/oauth-protected-resource""#
        XCTAssertEqual(
            MCPOAuthDiscovery.resourceMetadataURL(fromWWWAuthenticate: header)?.absoluteString,
            "https://mcp.example.com/.well-known/oauth-protected-resource"
        )
        XCTAssertNil(MCPOAuthDiscovery.resourceMetadataURL(fromWWWAuthenticate: "Bearer"))
    }

    func testProtectedResourceMetadataURLsInsertWellKnownBetweenHostAndPath() {
        let endpoint = URL(string: "https://mcp.linear.app/mcp")!
        let urls = MCPOAuthDiscovery.protectedResourceMetadataURLs(for: endpoint).map(\.absoluteString)
        XCTAssertTrue(urls.contains("https://mcp.linear.app/.well-known/oauth-protected-resource/mcp"))
        XCTAssertTrue(urls.contains("https://mcp.linear.app/.well-known/oauth-protected-resource"))
    }

    func testCanonicalResourceDropsQueryAndTrailingSlash() {
        XCTAssertEqual(
            MCPOAuthDiscovery.canonicalResource(for: URL(string: "https://mcp.example.com/mcp/?x=1")!),
            "https://mcp.example.com/mcp"
        )
    }

    func testPKCEVerifierAndChallengeAreURLSafe() {
        let verifier = MCPOAuthPKCE.makeVerifier()
        let challenge = MCPOAuthPKCE.challenge(for: verifier)
        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        XCTAssertFalse(verifier.contains("+"))
        XCTAssertFalse(verifier.contains("/"))
        XCTAssertFalse(verifier.contains("="))
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
        XCTAssertEqual(MCPOAuthPKCE.challenge(for: verifier), challenge)
    }

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

    func testParseCallbackRequiresMatchingStateAndCode() throws {
        let url = URL(string: "jin-mcp://oauth?code=abc&state=xyz")!
        XCTAssertEqual(try MCPOAuthClient.parseCallback(url, expectedState: "xyz"), "abc")
        XCTAssertThrowsError(try MCPOAuthClient.parseCallback(url, expectedState: "nope"))
        XCTAssertThrowsError(
            try MCPOAuthClient.parseCallback(
                URL(string: "jin-mcp://oauth?error=access_denied")!,
                expectedState: "xyz"
            )
        )
    }
}
