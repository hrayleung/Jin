import XCTest
@testable import Jin

final class ChatAuxiliaryControlSupportTests: XCTestCase {
    func testResolvedMCPServerConfigsUsesPerMessageOverrideWhenConversationMCPDisabled() throws {
        var controls = GenerationControls()
        controls.mcpTools = MCPToolsControls(enabled: false, enabledServerIDs: nil)

        let configs = try ChatAuxiliaryControlSupport.resolvedMCPServerConfigs(
            controls: controls,
            supportsMCPToolsControl: true,
            servers: [makeServer(id: "alpha"), makeServer(id: "beta")],
            perMessageOverrideServerIDs: ["beta"]
        )

        XCTAssertEqual(configs.map(\.id), ["beta"])
    }

    func testResolvedMCPServerConfigsFiltersPerMessageOverrideToEligibleServers() throws {
        let controls = GenerationControls(mcpTools: MCPToolsControls(enabled: true, enabledServerIDs: nil))
        let servers = [
            makeServer(id: "alpha"),
            makeServer(id: "beta", isEnabled: false),
            makeServer(id: "gamma", runToolsAutomatically: false)
        ]

        let configs = try ChatAuxiliaryControlSupport.resolvedMCPServerConfigs(
            controls: controls,
            supportsMCPToolsControl: true,
            servers: servers,
            perMessageOverrideServerIDs: ["alpha", "beta", "gamma", "missing"]
        )

        XCTAssertEqual(configs.map(\.id), ["alpha"])
    }

    func testResolvedMCPServerConfigsIgnoresPerMessageOverrideWhenMCPUnsupported() throws {
        let controls = GenerationControls(mcpTools: MCPToolsControls(enabled: true, enabledServerIDs: nil))

        let configs = try ChatAuxiliaryControlSupport.resolvedMCPServerConfigs(
            controls: controls,
            supportsMCPToolsControl: false,
            servers: [makeServer(id: "alpha")],
            perMessageOverrideServerIDs: ["alpha"]
        )

        XCTAssertTrue(configs.isEmpty)
    }

    private func makeServer(
        id: String,
        isEnabled: Bool = true,
        runToolsAutomatically: Bool = true
    ) -> MCPServerConfigEntity {
        let transport: MCPTransportConfig = .stdio(
            MCPStdioTransportConfig(command: "npx", args: ["-y", "mock-mcp-server"])
        )

        return MCPServerConfigEntity(
            id: id,
            name: id.capitalized,
            transportKindRaw: transport.kind.rawValue,
            transportData: try! JSONEncoder().encode(transport),
            lifecycleRaw: MCPLifecyclePolicy.persistent.rawValue,
            isEnabled: isEnabled,
            runToolsAutomatically: runToolsAutomatically,
            isLongRunning: true
        )
    }
}
