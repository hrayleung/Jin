import XCTest
@testable import Jin

/// A turn already in flight holds a `ToolRouteSnapshot` captured before the user
/// deleted a server. Without a tombstone, its next tool call finds no cached client
/// and spawns the deleted server's process again — re-creating the very leak
/// `shutdown(serverID:)` exists to close.
final class MCPHubShutdownTests: XCTestCase {
    private func makeServer(id: String) -> MCPServerConfig {
        MCPServerConfig(
            id: id,
            name: "Server \(id)",
            isEnabled: true,
            runToolsAutomatically: true,
            lifecycle: .persistent,
            // Deliberately unlaunchable: if the guard ever regresses, this surfaces as a
            // process-launch error instead of silently passing.
            transport: .stdio(MCPStdioTransportConfig(command: "jin-tests-nonexistent-binary"))
        )
    }

    private func makeRoutes(server: MCPServerConfig, toolName: String) -> (ToolRouteSnapshot, String) {
        let tool = MCPToolInfo(
            name: toolName,
            description: "",
            inputSchema: ParameterSchema(properties: [:], required: [])
        )
        let built = MCPHub.buildToolDefinitionsAndRoutes(from: [(server: server, tools: [tool])])
        return (built.routes, MCPHub.makeFunctionName(serverID: server.id, toolName: toolName))
    }

    func testStaleRouteCannotResurrectAShutDownServer() async throws {
        let server = makeServer(id: "shutdown-\(UUID().uuidString)")
        let (routes, functionName) = makeRoutes(server: server, toolName: "probe")

        await MCPHub.shared.shutdown(serverID: server.id)

        do {
            _ = try await MCPHub.shared.executeTool(
                functionName: functionName,
                arguments: [:],
                routes: routes
            )
            XCTFail("A route captured before the delete must not restart the server")
        } catch let error as MCPHubError {
            guard case .serverNotConnected(let id) = error else {
                return XCTFail("Expected serverNotConnected, got \(error)")
            }
            XCTAssertEqual(id, server.id)
        }
    }

    func testShuttingDownAServerThatWasNeverStartedIsHarmless() async {
        // No client exists yet, so this must not trap or spawn anything.
        await MCPHub.shared.shutdown(serverID: "never-started-\(UUID().uuidString)")
    }

    func testReconfiguringAServerClearsItsTombstone() async throws {
        let server = makeServer(id: "revived-\(UUID().uuidString)")
        let (routes, functionName) = makeRoutes(server: server, toolName: "probe")

        await MCPHub.shared.shutdown(serverID: server.id)

        // Listing tools comes from the live configuration, so seeing the ID again means
        // the server exists — deleting and re-adding the same ID must keep working.
        _ = try? await MCPHub.shared.listTools(for: server)

        do {
            _ = try await MCPHub.shared.executeTool(
                functionName: functionName,
                arguments: [:],
                routes: routes
            )
            XCTFail("Expected the unlaunchable command to fail")
        } catch let error as MCPHubError {
            XCTFail("Tombstone should have been cleared, but got \(error)")
        } catch {
            // Any other error means we got past the guard and actually tried to connect,
            // which is the point of this test.
        }
    }

    func testUnknownFunctionNameStillReportsUnknownTool() async {
        let server = makeServer(id: "unknown-\(UUID().uuidString)")
        let (routes, _) = makeRoutes(server: server, toolName: "probe")

        do {
            _ = try await MCPHub.shared.executeTool(
                functionName: "not-a-real-function",
                arguments: [:],
                routes: routes
            )
            XCTFail("Expected unknownTool")
        } catch let error as MCPHubError {
            guard case .unknownTool = error else {
                return XCTFail("Expected unknownTool, got \(error)")
            }
        } catch {
            XCTFail("Expected MCPHubError, got \(error)")
        }
    }
}
