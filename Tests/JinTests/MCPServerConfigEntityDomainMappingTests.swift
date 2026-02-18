import XCTest
@testable import Jin

final class MCPServerConfigEntityDomainMappingTests: XCTestCase {
    func testToConfigReadsHTTPTransport() throws {
        let transport: MCPTransportConfig = .http(
            MCPHTTPTransportConfig(
                endpoint: URL(string: "https://mcp.example.com")!,
                streaming: true,
                authentication: .bearerToken("token"),
                additionalHeaders: [MCPHeader(name: "X-Test", value: "1")]
            )
        )

        let entity = MCPServerConfigEntity(
            id: "remote",
            name: "Remote",
            transportKindRaw: transport.kind.rawValue,
            transportData: try JSONEncoder().encode(transport),
            lifecycleRaw: MCPLifecyclePolicy.persistent.rawValue,
            isEnabled: true,
            runToolsAutomatically: true,
            isLongRunning: true
        )

        let config = entity.toConfig()
        XCTAssertEqual(config.id, "remote")
        XCTAssertEqual(config.transport, transport)
        XCTAssertEqual(config.lifecycle, .persistent)
    }

    func testSetTransportKeepsLegacyFieldsForStdio() throws {
        let transport: MCPTransportConfig = .stdio(
            MCPStdioTransportConfig(
                command: "npx",
                args: ["-y", "firecrawl-mcp"],
                env: ["FIRECRAWL_API_KEY": "secret"]
            )
        )

        let entity = MCPServerConfigEntity(
            id: "firecrawl",
            name: "Firecrawl",
            transportKindRaw: MCPTransportKind.stdio.rawValue,
            transportData: Data(),
            lifecycleRaw: MCPLifecyclePolicy.persistent.rawValue,
            isEnabled: false,
            runToolsAutomatically: true,
            isLongRunning: true
        )

        entity.setTransport(transport)

        XCTAssertEqual(entity.transportKind, .stdio)
        XCTAssertEqual(entity.command, "npx")

        let decodedArgs = try JSONDecoder().decode([String].self, from: entity.argsData)
        XCTAssertEqual(decodedArgs, ["-y", "firecrawl-mcp"])

        let decodedEnv = try JSONDecoder().decode([String: String].self, from: entity.envData ?? Data())
        XCTAssertEqual(decodedEnv["FIRECRAWL_API_KEY"], "secret")
    }
}
