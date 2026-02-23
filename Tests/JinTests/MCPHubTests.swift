import XCTest
@testable import Jin

final class MCPHubTests: XCTestCase {
    func testBuildToolDefinitionsAndRoutesKeepsNamesUniqueAndWithin64CharsOnHighCollision() {
        let server = makeServer(id: "abcdefgh-server")
        let sharedPrefix = String(repeating: "x", count: 120)
        let tools = (0..<100).map { idx in
            makeTool(name: "\(sharedPrefix)-\(idx)", description: "tool \(idx)")
        }

        let built = MCPHub.buildToolDefinitionsAndRoutes(from: [(server: server, tools: tools)])
        let names = built.definitions.map(\.name)

        XCTAssertEqual(names.count, 100)
        XCTAssertEqual(Set(names).count, 100)
        XCTAssertTrue(names.allSatisfy { $0.count <= MCPHub.functionNameMaxLength })
    }

    func testToolRouteSnapshotsKeepIndependentRoutesForSameFunctionName() throws {
        let server = makeServer(id: "abcdefgh-server")
        let sharedPrefix = String(repeating: "p", count: 80)
        let toolA = makeTool(name: "\(sharedPrefix)-alpha", description: "alpha")
        let toolB = makeTool(name: "\(sharedPrefix)-beta", description: "beta")

        let first = MCPHub.buildToolDefinitionsAndRoutes(from: [(server: server, tools: [toolA])])
        let second = MCPHub.buildToolDefinitionsAndRoutes(from: [(server: server, tools: [toolB])])

        let firstFunctionName = try XCTUnwrap(first.definitions.first?.name)
        let secondFunctionName = try XCTUnwrap(second.definitions.first?.name)
        XCTAssertEqual(firstFunctionName, secondFunctionName)

        XCTAssertEqual(first.routes.routeInfo(for: firstFunctionName)?.toolName, toolA.name)
        XCTAssertEqual(second.routes.routeInfo(for: secondFunctionName)?.toolName, toolB.name)
        XCTAssertNotEqual(
            first.routes.routeInfo(for: firstFunctionName)?.toolName,
            second.routes.routeInfo(for: firstFunctionName)?.toolName
        )
    }

    func testBuildToolDefinitionsAndRoutesSkipsDisabledTools() {
        let server = makeServer(id: "server-1", disabledTools: ["blocked"])
        let allowed = makeTool(name: "allowed", description: "allowed tool")
        let blocked = makeTool(name: "blocked", description: "blocked tool")

        let built = MCPHub.buildToolDefinitionsAndRoutes(from: [(server: server, tools: [allowed, blocked])])
        let expectedName = MCPHub.makeFunctionName(serverID: server.id, toolName: allowed.name)

        XCTAssertEqual(built.definitions.count, 1)
        XCTAssertEqual(built.definitions.first?.id, "server-1:allowed")
        XCTAssertEqual(built.definitions.first?.name, expectedName)
        XCTAssertEqual(built.routes.routeInfo(for: expectedName)?.toolName, "allowed")
    }
}

private func makeServer(id: String, disabledTools: Set<String> = []) -> MCPServerConfig {
    MCPServerConfig(
        id: id,
        name: "Server \(id)",
        isEnabled: true,
        runToolsAutomatically: true,
        lifecycle: .persistent,
        transport: .stdio(MCPStdioTransportConfig(command: "mock-mcp-server")),
        disabledTools: disabledTools
    )
}

private func makeTool(name: String, description: String) -> MCPToolInfo {
    MCPToolInfo(
        name: name,
        description: description,
        inputSchema: ParameterSchema(properties: [:])
    )
}
