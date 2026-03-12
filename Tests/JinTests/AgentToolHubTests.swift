import XCTest
@testable import Jin

final class AgentToolHubTests: XCTestCase {

    private func makeControls(enabled: Bool = true, tools: AgentEnabledTools = AgentEnabledTools()) -> GenerationControls {
        var agentMode = AgentModeControls()
        agentMode.enabled = enabled
        agentMode.enabledTools = tools
        return GenerationControls(agentMode: agentMode)
    }

    // MARK: - Tool definitions when disabled

    func testToolDefinitionsWhenDisabled() async {
        let controls = makeControls(enabled: false)
        let result = await AgentToolHub.shared.toolDefinitions(for: controls)
        XCTAssertTrue(result.definitions.isEmpty)
    }

    // MARK: - Tool definitions when enabled

    func testToolDefinitionsWhenEnabled() async {
        let controls = makeControls()
        let result = await AgentToolHub.shared.toolDefinitions(for: controls)
        // All 6 tools: shell_execute, file_read, file_write, file_edit, glob_search, grep_search
        XCTAssertEqual(result.definitions.count, 6)
    }

    // MARK: - Per-tool toggles

    func testToolDefinitionsRespectsDisabledShell() async {
        var tools = AgentEnabledTools()
        tools.shellExecute = false
        let result = await AgentToolHub.shared.toolDefinitions(for: makeControls(tools: tools))
        XCTAssertEqual(result.definitions.count, 5)
        let names = result.definitions.map(\.name)
        XCTAssertFalse(names.contains(where: { $0.contains("shell") }))
    }

    func testToolDefinitionsRespectsDisabledFileRead() async {
        var tools = AgentEnabledTools()
        tools.fileRead = false
        let result = await AgentToolHub.shared.toolDefinitions(for: makeControls(tools: tools))
        XCTAssertEqual(result.definitions.count, 5)
        let names = result.definitions.map(\.name)
        XCTAssertFalse(names.contains(where: { $0.contains("file_read") }))
    }

    func testToolDefinitionsRespectsDisabledFileWrite() async {
        var tools = AgentEnabledTools()
        tools.fileWrite = false
        let result = await AgentToolHub.shared.toolDefinitions(for: makeControls(tools: tools))
        XCTAssertEqual(result.definitions.count, 5)
        let names = result.definitions.map(\.name)
        XCTAssertFalse(names.contains(where: { $0.contains("file_write") }))
    }

    func testToolDefinitionsRespectsDisabledFileEdit() async {
        var tools = AgentEnabledTools()
        tools.fileEdit = false
        let result = await AgentToolHub.shared.toolDefinitions(for: makeControls(tools: tools))
        XCTAssertEqual(result.definitions.count, 5)
        let names = result.definitions.map(\.name)
        XCTAssertFalse(names.contains(where: { $0.contains("file_edit") }))
    }

    func testToolDefinitionsRespectsDisabledGlobSearch() async {
        var tools = AgentEnabledTools()
        tools.globSearch = false
        let result = await AgentToolHub.shared.toolDefinitions(for: makeControls(tools: tools))
        XCTAssertEqual(result.definitions.count, 5)
        let names = result.definitions.map(\.name)
        XCTAssertFalse(names.contains(where: { $0.contains("glob") }))
    }

    func testToolDefinitionsRespectsDisabledGrepSearch() async {
        var tools = AgentEnabledTools()
        tools.grepSearch = false
        let result = await AgentToolHub.shared.toolDefinitions(for: makeControls(tools: tools))
        XCTAssertEqual(result.definitions.count, 5)
        let names = result.definitions.map(\.name)
        XCTAssertFalse(names.contains(where: { $0.contains("grep") }))
    }

    func testToolDefinitionsAllDisabledReturnsEmpty() async {
        let tools = AgentEnabledTools(
            shellExecute: false,
            fileRead: false,
            fileWrite: false,
            fileEdit: false,
            globSearch: false,
            grepSearch: false
        )
        let result = await AgentToolHub.shared.toolDefinitions(for: makeControls(tools: tools))
        XCTAssertTrue(result.definitions.isEmpty)
    }

    // MARK: - Function name prefix

    func testFunctionNamePrefix() async {
        let result = await AgentToolHub.shared.toolDefinitions(for: makeControls())
        for definition in result.definitions {
            XCTAssertTrue(
                definition.name.hasPrefix("agent__"),
                "Expected '\(definition.name)' to start with 'agent__'"
            )
        }
    }

    // MARK: - isAgentFunctionName

    func testIsAgentFunctionName() {
        XCTAssertTrue(AgentToolHub.isAgentFunctionName("agent__shell_execute"))
        XCTAssertTrue(AgentToolHub.isAgentFunctionName("agent__file_read"))
        XCTAssertFalse(AgentToolHub.isAgentFunctionName("mcp__shell_execute"))
        XCTAssertFalse(AgentToolHub.isAgentFunctionName("shell_execute"))
    }

    // MARK: - Tool definitions have descriptions and parameters

    func testToolDefinitionsHaveDescriptions() async {
        let result = await AgentToolHub.shared.toolDefinitions(for: makeControls())
        for definition in result.definitions {
            XCTAssertFalse(
                definition.description.isEmpty,
                "Expected '\(definition.name)' to have a non-empty description"
            )
        }
    }

    func testToolDefinitionsHaveParameters() async {
        let result = await AgentToolHub.shared.toolDefinitions(for: makeControls())
        for definition in result.definitions {
            XCTAssertFalse(
                definition.parameters.properties.isEmpty,
                "Expected '\(definition.name)' to have parameters"
            )
        }
    }

    // MARK: - Routes snapshot

    func testRoutesContainAllDefinitions() async {
        let result = await AgentToolHub.shared.toolDefinitions(for: makeControls())
        for definition in result.definitions {
            XCTAssertTrue(
                result.routes.contains(functionName: definition.name),
                "Routes should contain '\(definition.name)'"
            )
        }
    }

    func testRoutesDoNotContainNonAgentNames() async {
        let result = await AgentToolHub.shared.toolDefinitions(for: makeControls())
        XCTAssertFalse(result.routes.contains(functionName: "mcp__some_tool"))
        XCTAssertFalse(result.routes.contains(functionName: "builtin__web_search"))
    }
}
