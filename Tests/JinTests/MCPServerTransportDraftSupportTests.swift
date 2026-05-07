import XCTest
@testable import Jin

final class MCPServerTransportDraftSupportTests: XCTestCase {
    func testStdioDraftRendersArgsSortsEnvironmentAndClearsHTTPFields() {
        let draft = MCPServerTransportDraftSupport.draft(
            from: .stdio(
                MCPStdioTransportConfig(
                    command: "npx",
                    args: ["-y", "exa-mcp-server", "quoted value"],
                    env: [
                        "Z_TOKEN": "last",
                        "A_TOKEN": "first"
                    ]
                )
            )
        )

        XCTAssertEqual(draft.transportKind, .stdio)
        XCTAssertEqual(draft.command, "npx")
        XCTAssertEqual(draft.argsText, #"-y exa-mcp-server "quoted value""#)
        XCTAssertEqual(draft.envPairs.map(\.key), ["A_TOKEN", "Z_TOKEN"])
        XCTAssertEqual(draft.envPairs.map(\.value), ["first", "last"])
        XCTAssertEqual(draft.endpoint, "")
        XCTAssertEqual(draft.httpAuthentication, .none)
        XCTAssertEqual(draft.headerPairs, [])
        XCTAssertTrue(draft.httpStreaming)
    }

    func testHTTPDraftMapsEndpointAuthenticationHeadersStreamingAndClearsStdioFields() throws {
        let draft = MCPServerTransportDraftSupport.draft(
            from: .http(
                MCPHTTPTransportConfig(
                    endpoint: try XCTUnwrap(URL(string: "https://mcp.example.com/stream")),
                    streaming: false,
                    authentication: .bearerToken("token"),
                    additionalHeaders: [
                        MCPHeader(name: "X-Client", value: "jin"),
                        MCPHeader(name: "X-Trace", value: "abc")
                    ]
                )
            )
        )

        XCTAssertEqual(draft.transportKind, .http)
        XCTAssertEqual(draft.command, "")
        XCTAssertEqual(draft.argsText, "")
        XCTAssertEqual(draft.envPairs, [])
        XCTAssertEqual(draft.endpoint, "https://mcp.example.com/stream")
        XCTAssertEqual(draft.httpAuthentication, .bearerToken("token"))
        XCTAssertEqual(draft.headerPairs.map(\.key), ["X-Client", "X-Trace"])
        XCTAssertEqual(draft.headerPairs.map(\.value), ["jin", "abc"])
        XCTAssertFalse(draft.httpStreaming)
    }

    func testBuildStdioTransportParsesArgsTrimsCommandAndBuildsEnvironment() throws {
        let transport = try MCPServerTransportDraftSupport.buildTransport(
            from: buildRequest(
                transportKind: .stdio,
                command: " npx ",
                argsText: #"-y "exa mcp""#,
                envPairs: [
                    EnvironmentVariablePair(key: " API_KEY ", value: "one"),
                    EnvironmentVariablePair(key: " ", value: "ignored")
                ]
            )
        )

        guard case .stdio(let stdio) = transport else {
            return XCTFail("Expected stdio transport")
        }

        XCTAssertEqual(stdio.command, "npx")
        XCTAssertEqual(stdio.args, ["-y", "exa mcp"])
        XCTAssertEqual(stdio.env, ["API_KEY": "one"])
    }

    func testBuildStdioTransportReportsArgumentParseErrors() {
        XCTAssertThrowsError(
            try MCPServerTransportDraftSupport.buildTransport(
                from: buildRequest(transportKind: .stdio, argsText: #""unterminated"#)
            )
        ) { error in
            guard case MCPServerTransportDraftSupport.BuildError.invalidArguments(let message) = error else {
                return XCTFail("Expected invalid arguments error")
            }

            XCTAssertFalse(message.isEmpty)
        }
    }

    func testBuildHTTPTransportParsesEndpointAuthenticationHeadersAndStreaming() throws {
        let transport = try MCPServerTransportDraftSupport.buildTransport(
            from: buildRequest(
                transportKind: .http,
                endpoint: " https://mcp.example.com/stream ",
                httpAuthentication: .bearerToken("token"),
                headerPairs: [
                    EnvironmentVariablePair(key: " X-API-Key ", value: "key"),
                    EnvironmentVariablePair(key: " ", value: "ignored")
                ],
                httpStreaming: false
            )
        )

        guard case .http(let http) = transport else {
            return XCTFail("Expected HTTP transport")
        }

        XCTAssertEqual(http.endpoint.absoluteString, "https://mcp.example.com/stream")
        XCTAssertEqual(http.authentication, .bearerToken("token"))
        XCTAssertEqual(http.additionalHeaders, [MCPHeader(name: "X-API-Key", value: "key", isSensitive: true)])
        XCTAssertFalse(http.streaming)
    }

    func testBuildHTTPTransportReportsEndpointAndAuthenticationErrors() {
        XCTAssertThrowsError(
            try MCPServerTransportDraftSupport.buildTransport(
                from: buildRequest(
                    transportKind: .http,
                    endpoint: "mcp.example.com",
                    httpAuthentication: MCPHTTPAuthentication.none
                )
            )
        ) { error in
            XCTAssertEqual(error as? MCPServerTransportDraftSupport.BuildError, .invalidEndpointURL)
        }

        XCTAssertThrowsError(
            try MCPServerTransportDraftSupport.buildTransport(
                from: buildRequest(
                    transportKind: .http,
                    endpoint: "https://mcp.example.com",
                    httpAuthentication: nil
                )
            )
        ) { error in
            XCTAssertEqual(error as? MCPServerTransportDraftSupport.BuildError, .invalidAuthentication)
        }
    }

    private func buildRequest(
        transportKind: MCPTransportKind,
        command: String = "",
        argsText: String = "",
        envPairs: [EnvironmentVariablePair] = [],
        endpoint: String = "",
        httpAuthentication: MCPHTTPAuthentication? = MCPHTTPAuthentication.none,
        headerPairs: [EnvironmentVariablePair] = [],
        httpStreaming: Bool = true
    ) -> MCPServerTransportDraftSupport.BuildRequest {
        MCPServerTransportDraftSupport.BuildRequest(
            transportKind: transportKind,
            command: command,
            argsText: argsText,
            envPairs: envPairs,
            endpoint: endpoint,
            httpAuthentication: httpAuthentication,
            headerPairs: headerPairs,
            httpStreaming: httpStreaming
        )
    }
}
