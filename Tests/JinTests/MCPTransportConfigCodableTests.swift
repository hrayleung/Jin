import XCTest
@testable import Jin

final class MCPTransportConfigCodableTests: XCTestCase {
    func testStdioTransportRoundTrip() throws {
        let transport: MCPTransportConfig = .stdio(
            MCPStdioTransportConfig(
                command: "npx",
                args: ["-y", "exa-mcp-server"],
                env: ["EXA_API_KEY": "test-key"]
            )
        )

        let data = try JSONEncoder().encode(transport)
        let decoded = try JSONDecoder().decode(MCPTransportConfig.self, from: data)

        XCTAssertEqual(decoded, transport)
        XCTAssertEqual(decoded.kind, .stdio)
    }

    func testHTTPTransportRoundTripKeepsAuthenticationAndHeadersSeparated() throws {
        let transport: MCPTransportConfig = .http(
            MCPHTTPTransportConfig(
                endpoint: URL(string: "https://mcp.example.com")!,
                streaming: true,
                authentication: .bearerToken("token-123"),
                additionalHeaders: [
                    MCPHeader(name: "X-Test", value: "abc"),
                    MCPHeader(name: "Authorization", value: "Basic ignored")
                ],
            )
        )

        let data = try JSONEncoder().encode(transport)
        let decoded = try JSONDecoder().decode(MCPTransportConfig.self, from: data)

        XCTAssertEqual(decoded, transport)

        guard case .http(let http) = decoded else {
            return XCTFail("Expected HTTP transport")
        }

        XCTAssertEqual(http.authentication, .bearerToken("token-123"))
        XCTAssertEqual(http.additionalHeaders.count, 1)
        XCTAssertEqual(http.additionalHeaders.first?.name, "X-Test")

        let headers = http.resolvedHeaders()
        XCTAssertEqual(headers["X-Test"], "abc")
        XCTAssertEqual(headers["Authorization"], "Bearer token-123")
    }

    func testHTTPTransportLegacyDecodeSupportsBearerTokenFieldAndNormalizesHeaders() throws {
        let payload = """
        {
          "kind": "http",
          "http": {
            "endpoint": "https://mcp.example.com",
            "streaming": true,
            "headers": [
              { "name": "X-Test", "value": "abc", "isSensitive": false },
              { "name": "Authorization", "value": "Basic ignored", "isSensitive": true }
            ],
            "bearerToken": "token-123"
          }
        }
        """

        let decoded = try JSONDecoder().decode(MCPTransportConfig.self, from: Data(payload.utf8))

        guard case .http(let http) = decoded else {
            return XCTFail("Expected HTTP transport")
        }

        XCTAssertEqual(http.authentication, .bearerToken("token-123"))
        XCTAssertEqual(http.additionalHeaders.count, 1)
        XCTAssertEqual(http.additionalHeaders.first?.name, "X-Test")

        let headers = http.resolvedHeaders()
        XCTAssertEqual(headers["Authorization"], "Bearer token-123")
        XCTAssertEqual(headers["X-Test"], "abc")
    }
}
