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

    func testHTTPTransportRoundTripAndBearerPrecedence() throws {
        let transport: MCPTransportConfig = .http(
            MCPHTTPTransportConfig(
                endpoint: URL(string: "https://mcp.example.com")!,
                streaming: true,
                headers: [
                    MCPHeader(name: "X-Test", value: "abc"),
                    MCPHeader(name: "Authorization", value: "Basic ignored")
                ],
                bearerToken: "token-123"
            )
        )

        let data = try JSONEncoder().encode(transport)
        let decoded = try JSONDecoder().decode(MCPTransportConfig.self, from: data)

        XCTAssertEqual(decoded, transport)

        guard case .http(let http) = decoded else {
            return XCTFail("Expected HTTP transport")
        }

        let headers = http.resolvedHeaders()
        XCTAssertEqual(headers["X-Test"], "abc")
        XCTAssertEqual(headers["Authorization"], "Bearer token-123")
    }
}
