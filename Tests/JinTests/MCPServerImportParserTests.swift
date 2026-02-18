import XCTest
@testable import Jin

final class MCPServerImportParserTests: XCTestCase {
    func testParseClaudeStyleStdioServer() throws {
        let json = """
        {
          "mcpServers": {
            "exa": {
              "command": "npx",
              "args": ["-y", "exa-mcp-server"],
              "env": {
                "EXA_API_KEY": "secret"
              }
            }
          }
        }
        """

        let imported = try MCPServerImportParser.parse(json: json)

        XCTAssertEqual(imported.id, "exa")
        XCTAssertEqual(imported.name, "exa")

        guard case .stdio(let stdio) = imported.transport else {
            return XCTFail("Expected stdio transport")
        }

        XCTAssertEqual(stdio.command, "npx")
        XCTAssertEqual(stdio.args, ["-y", "exa-mcp-server"])
        XCTAssertEqual(stdio.env["EXA_API_KEY"], "secret")
    }

    func testParseHTTPServerAsNativeHTTPTransport() throws {
        let json = """
        {
          "id": "exa",
          "name": "Exa",
          "type": "http",
          "url": "https://mcp.exa.ai/mcp",
          "headers": {
            "X-Client": "jin"
          },
          "bearerToken": "token"
        }
        """

        let imported = try MCPServerImportParser.parse(json: json)

        XCTAssertEqual(imported.id, "exa")

        guard case .http(let http) = imported.transport else {
            return XCTFail("Expected HTTP transport")
        }

        XCTAssertEqual(http.endpoint.absoluteString, "https://mcp.exa.ai/mcp")
        XCTAssertEqual(http.authentication, .bearerToken("token"))
        XCTAssertEqual(http.additionalHeaders.first?.name, "X-Client")
        XCTAssertEqual(http.additionalHeaders.first?.value, "jin")
    }

    func testParseHTTPAuthorizationBearerHeaderExtractsToken() throws {
        let json = """
        {
          "id": "remote",
          "name": "Remote",
          "type": "http",
          "url": "https://example.com/mcp",
          "headers": {
            "Authorization": "Bearer abc123",
            "X-Foo": "bar"
          }
        }
        """

        let imported = try MCPServerImportParser.parse(json: json)

        guard case .http(let http) = imported.transport else {
            return XCTFail("Expected HTTP transport")
        }

        XCTAssertEqual(http.authentication, .bearerToken("abc123"))
        XCTAssertEqual(http.additionalHeaders.count, 1)
        XCTAssertEqual(http.additionalHeaders.first?.name, "X-Foo")
    }

    func testParseHTTPAuthorizationBasicHeaderMapsToCustomAuthenticationHeader() throws {
        let json = """
        {
          "id": "remote",
          "name": "Remote",
          "type": "http",
          "url": "https://example.com/mcp",
          "headers": {
            "Authorization": "Basic YWJjOnh5eg==",
            "X-Foo": "bar"
          }
        }
        """

        let imported = try MCPServerImportParser.parse(json: json)

        guard case .http(let http) = imported.transport else {
            return XCTFail("Expected HTTP transport")
        }

        XCTAssertEqual(
            http.authentication,
            .header(MCPHeader(name: "Authorization", value: "Basic YWJjOnh5eg==", isSensitive: true))
        )
        XCTAssertEqual(http.additionalHeaders.count, 1)
        XCTAssertEqual(http.additionalHeaders.first?.name, "X-Foo")
    }

    func testParseHTTPMissingURLThrows() throws {
        let json = """
        {
          "id": "broken",
          "name": "Broken",
          "type": "http"
        }
        """

        XCTAssertThrowsError(try MCPServerImportParser.parse(json: json)) { error in
            guard let importError = error as? MCPServerImportError else {
                return XCTFail("Expected MCPServerImportError")
            }

            XCTAssertEqual(importError.errorDescription, MCPServerImportError.missingHTTPURL.errorDescription)
        }
    }
}
