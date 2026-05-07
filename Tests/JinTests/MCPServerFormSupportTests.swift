import XCTest
@testable import Jin

final class MCPServerFormSupportTests: XCTestCase {
    func testParsedEndpointRequiresNonEmptyAbsoluteURLWithScheme() {
        XCTAssertEqual(MCPServerFormSupport.parsedEndpoint(" https://mcp.example.com/path ")?.absoluteString, "https://mcp.example.com/path")
        XCTAssertNil(MCPServerFormSupport.parsedEndpoint(""))
        XCTAssertNil(MCPServerFormSupport.parsedEndpoint("mcp.example.com/path"))
    }

    func testAddServerDisabledMatchesTransportSpecificRequiredFields() {
        XCTAssertTrue(
            MCPServerFormSupport.isAddServerDisabled(
                name: " ",
                transportKind: .stdio,
                command: "npx",
                parsedEndpoint: nil,
                parsedHTTPAuthentication: nil
            )
        )
        XCTAssertTrue(
            MCPServerFormSupport.isAddServerDisabled(
                name: "Exa",
                transportKind: .stdio,
                command: " ",
                parsedEndpoint: nil,
                parsedHTTPAuthentication: nil
            )
        )
        XCTAssertFalse(
            MCPServerFormSupport.isAddServerDisabled(
                name: "Exa",
                transportKind: .stdio,
                command: "npx",
                parsedEndpoint: nil,
                parsedHTTPAuthentication: nil
            )
        )
        XCTAssertTrue(
            MCPServerFormSupport.isAddServerDisabled(
                name: "Exa",
                transportKind: .http,
                command: "",
                parsedEndpoint: URL(string: "https://mcp.example.com"),
                parsedHTTPAuthentication: nil
            )
        )
        XCTAssertFalse(
            MCPServerFormSupport.isAddServerDisabled(
                name: "Exa",
                transportKind: .http,
                command: "",
                parsedEndpoint: URL(string: "https://mcp.example.com"),
                parsedHTTPAuthentication: MCPHTTPAuthentication.none
            )
        )
    }

    func testTransportValidationErrorMatchesEditFormRules() {
        XCTAssertTrue(
            MCPServerFormSupport.hasTransportValidationError(
                transportKind: .stdio,
                command: " ",
                argsError: nil,
                endpoint: "",
                endpointError: nil,
                httpAuthenticationValidationError: nil
            )
        )
        XCTAssertTrue(
            MCPServerFormSupport.hasTransportValidationError(
                transportKind: .stdio,
                command: "npx",
                argsError: "Unterminated quote.",
                endpoint: "",
                endpointError: nil,
                httpAuthenticationValidationError: nil
            )
        )
        XCTAssertFalse(
            MCPServerFormSupport.hasTransportValidationError(
                transportKind: .stdio,
                command: "npx",
                argsError: nil,
                endpoint: "",
                endpointError: nil,
                httpAuthenticationValidationError: nil
            )
        )
        XCTAssertTrue(
            MCPServerFormSupport.hasTransportValidationError(
                transportKind: .http,
                command: "",
                argsError: nil,
                endpoint: " ",
                endpointError: nil,
                httpAuthenticationValidationError: nil
            )
        )
        XCTAssertTrue(
            MCPServerFormSupport.hasTransportValidationError(
                transportKind: .http,
                command: "",
                argsError: nil,
                endpoint: "https://mcp.example.com",
                endpointError: "Invalid endpoint URL.",
                httpAuthenticationValidationError: nil
            )
        )
        XCTAssertFalse(
            MCPServerFormSupport.hasTransportValidationError(
                transportKind: .http,
                command: "",
                argsError: nil,
                endpoint: "https://mcp.example.com",
                endpointError: nil,
                httpAuthenticationValidationError: nil
            )
        )
    }

    func testNodeIsolationNoteRecognizesNodeLaunchersAndPaths() {
        XCTAssertTrue(MCPServerFormSupport.shouldShowNodeIsolationNote(command: "npx"))
        XCTAssertTrue(MCPServerFormSupport.shouldShowNodeIsolationNote(command: "/opt/homebrew/bin/pnpm dlx"))
        XCTAssertTrue(MCPServerFormSupport.shouldShowNodeIsolationNote(command: #""/usr/local/bin/bunx" package"#))
        XCTAssertFalse(MCPServerFormSupport.shouldShowNodeIsolationNote(command: "python"))
    }

    func testFirecrawlDetectionChecksCommandAndTokenizedArguments() {
        XCTAssertTrue(MCPServerFormSupport.isFirecrawlMCP(command: "npx firecrawl-mcp", argsText: ""))
        XCTAssertTrue(MCPServerFormSupport.isFirecrawlMCP(command: "npx", argsText: "-y firecrawl-mcp"))
        XCTAssertFalse(MCPServerFormSupport.isFirecrawlMCP(command: "npx", argsText: "-y exa-mcp-server"))
    }

    func testFirecrawlAPIKeyRequiresExactTrimmedKeyAndNonEmptyValue() {
        XCTAssertTrue(
            MCPServerFormSupport.hasFirecrawlAPIKey(
                in: [EnvironmentVariablePair(key: " FIRECRAWL_API_KEY ", value: " token ")]
            )
        )
        XCTAssertFalse(
            MCPServerFormSupport.hasFirecrawlAPIKey(
                in: [EnvironmentVariablePair(key: "firecrawl_api_key", value: "token")]
            )
        )
        XCTAssertFalse(
            MCPServerFormSupport.hasFirecrawlAPIKey(
                in: [EnvironmentVariablePair(key: "FIRECRAWL_API_KEY", value: " ")]
            )
        )
    }

    func testNormalizedServerIDAndIconIDPreserveExistingRules() {
        XCTAssertEqual(MCPServerFormSupport.normalizedServerID(" exa "), "exa")
        XCTAssertEqual(MCPServerFormSupport.normalizedServerID(" ", fallback: { "generated" }), "generated")
        XCTAssertEqual(MCPServerFormSupport.normalizedServerName(" Exa ", fallback: "fallback"), "Exa")
        XCTAssertEqual(MCPServerFormSupport.normalizedServerName(" ", fallback: "fallback"), "fallback")
        XCTAssertEqual(MCPServerFormSupport.normalizedServerName(nil, fallback: "fallback"), "fallback")
        XCTAssertEqual(MCPServerFormSupport.normalizedIconID(" github "), "github")
        XCTAssertNil(MCPServerFormSupport.normalizedIconID(""))
        XCTAssertNil(MCPServerFormSupport.normalizedIconID("MCP"))
    }

    func testEnvironmentDictionaryTrimsKeysDropsBlankKeysAndKeepsLastDuplicateValue() {
        let pairs = [
            EnvironmentVariablePair(key: " API_KEY ", value: "one"),
            EnvironmentVariablePair(key: "", value: "ignored"),
            EnvironmentVariablePair(key: "API_KEY", value: "two")
        ]

        XCTAssertEqual(MCPServerFormSupport.environmentDictionary(from: pairs), ["API_KEY": "two"])
    }

    func testHeadersTrimNamesDropBlankNamesAndMarkSensitiveHeaders() {
        let headers = MCPServerFormSupport.headers(
            from: [
                EnvironmentVariablePair(key: " Authorization ", value: "Bearer token"),
                EnvironmentVariablePair(key: "X-Client", value: "jin"),
                EnvironmentVariablePair(key: " ", value: "ignored")
            ]
        )

        XCTAssertEqual(headers.count, 2)
        XCTAssertEqual(headers[0], MCPHeader(name: "Authorization", value: "Bearer token", isSensitive: true))
        XCTAssertEqual(headers[1], MCPHeader(name: "X-Client", value: "jin", isSensitive: false))
    }

    func testHeaderTrimsNameDropsBlankNamesAndMarksSensitiveHeaders() {
        XCTAssertEqual(
            MCPServerFormSupport.header(name: " X-API-Key ", value: "token"),
            MCPHeader(name: "X-API-Key", value: "token", isSensitive: true)
        )
        XCTAssertNil(MCPServerFormSupport.header(name: " ", value: "ignored"))
    }
}
