import XCTest
@testable import Jin

final class MCPClientEnvironmentTests: XCTestCase {
    func testNodeLauncherWorkingDirectoryIsOutsideHome() async throws {
        let client = MCPClient(config: makeServer(id: "anysearch"))
        let workingDirectory = try await client.workingDirectoryForProcess(command: "npx")
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path

        XCTAssertFalse(workingDirectory.standardizedFileURL.path == home)
        XCTAssertFalse(workingDirectory.standardizedFileURL.path.hasPrefix(home + "/"))
        XCTAssertTrue(workingDirectory.path.contains("mcp-cwd"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workingDirectory.path))
    }

    func testNodeIsolationDoesNotExportPrefixEnvironment() async throws {
        let previousRoot = ProcessInfo.processInfo.environment["JIN_APP_SUPPORT_ROOT"]
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer {
            if let previousRoot {
                setenv("JIN_APP_SUPPORT_ROOT", previousRoot, 1)
            } else {
                unsetenv("JIN_APP_SUPPORT_ROOT")
            }
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        setenv("JIN_APP_SUPPORT_ROOT", temporaryRoot.path, 1)

        let client = MCPClient(config: makeServer(id: "anysearch"))
        let stdio = MCPStdioTransportConfig(command: "npx", args: ["-y", "mcp-remote"])
        let env = try await client.makeProcessEnvironment(stdio: stdio, command: "npx")

        XCTAssertNil(env["NPM_CONFIG_PREFIX"])
        XCTAssertNil(env["npm_config_prefix"])
        XCTAssertNotNil(env["NPM_CONFIG_USERCONFIG"])
        XCTAssertNotNil(env["NPM_CONFIG_CACHE"])
        XCTAssertNotEqual(env["HOME"], FileManager.default.homeDirectoryForCurrentUser.path)
    }

    func testNonNodeCommandsKeepDefaultWorkingDirectory() async throws {
        let client = MCPClient(config: makeServer(id: "uvx-fetch"))
        let workingDirectory = try await client.workingDirectoryForProcess(command: "uvx")
        XCTAssertEqual(
            workingDirectory.standardizedFileURL.path,
            FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        )
    }

    private func makeServer(id: String) -> MCPServerConfig {
        MCPServerConfig(
            id: id,
            name: id,
            isEnabled: true,
            runToolsAutomatically: true,
            lifecycle: .persistent,
            transport: .stdio(MCPStdioTransportConfig(command: "npx"))
        )
    }
}
