import XCTest
@testable import Jin

final class AddMCPServerPresetSupportTests: XCTestCase {
    func testCanImportJSONRequiresNonBlankText() {
        XCTAssertTrue(AddMCPServerPresetSupport.canImportJSON(" { \"mcpServers\": {} } "))
        XCTAssertFalse(AddMCPServerPresetSupport.canImportJSON(" \n\t "))
    }

    func testExaHTTPPresetFillsBlankIdentityAndAddsClientHeaderOnce() {
        let draft = AddMCPServerPresetSupport.applyingPreset(
            .exaHTTP,
            to: self.draft(
                id: " ",
                name: " ",
                headerPairs: [EnvironmentVariablePair(key: "x-client", value: "custom")],
                httpAuthentication: .bearerToken("token")
            )
        )

        XCTAssertEqual(draft.id, "exa")
        XCTAssertEqual(draft.name, "Exa")
        XCTAssertEqual(draft.transportKind, .http)
        XCTAssertEqual(draft.endpoint, "https://mcp.exa.ai/mcp")
        XCTAssertEqual(draft.headerPairs.map(\.key), ["x-client"])
        XCTAssertEqual(draft.httpAuthentication, .none)
    }

    func testExaLocalPresetPreservesExistingIdentityAndAddsAPIKeyOnce() {
        let draft = AddMCPServerPresetSupport.applyingPreset(
            .exaLocal,
            to: self.draft(
                id: "custom",
                name: "Custom",
                envPairs: [EnvironmentVariablePair(key: "EXA_API_KEY", value: "secret")]
            )
        )

        XCTAssertEqual(draft.id, "custom")
        XCTAssertEqual(draft.name, "Custom")
        XCTAssertEqual(draft.transportKind, .stdio)
        XCTAssertEqual(draft.command, "npx")
        XCTAssertEqual(draft.args, "-y exa-mcp-server")
        XCTAssertEqual(draft.envPairs.map(\.key), ["EXA_API_KEY"])
    }

    func testFirecrawlPresetFillsBlankIdentityAndAddsAPIKey() {
        let draft = AddMCPServerPresetSupport.applyingPreset(
            .firecrawlLocal,
            to: self.draft(id: "", name: "")
        )

        XCTAssertEqual(draft.id, "firecrawl")
        XCTAssertEqual(draft.name, "Firecrawl")
        XCTAssertEqual(draft.transportKind, .stdio)
        XCTAssertEqual(draft.command, "npx")
        XCTAssertEqual(draft.args, "-y firecrawl-mcp")
        XCTAssertEqual(draft.envPairs.map(\.key), ["FIRECRAWL_API_KEY"])
    }

    func testCustomPresetLeavesDraftUnchanged() {
        let original = draft(
            id: "custom",
            name: "Custom",
            transportKind: .http,
            endpoint: "https://mcp.example.com"
        )

        XCTAssertEqual(
            AddMCPServerPresetSupport.applyingPreset(.custom, to: original),
            original
        )
    }

    private func draft(
        id: String = "",
        name: String = "",
        transportKind: MCPTransportKind = .stdio,
        command: String = "",
        args: String = "",
        envPairs: [EnvironmentVariablePair] = [],
        endpoint: String = "",
        headerPairs: [EnvironmentVariablePair] = [],
        httpAuthentication: MCPHTTPAuthentication = .none
    ) -> AddMCPServerPresetSupport.Draft {
        AddMCPServerPresetSupport.Draft(
            id: id,
            name: name,
            transportKind: transportKind,
            command: command,
            args: args,
            envPairs: envPairs,
            endpoint: endpoint,
            headerPairs: headerPairs,
            httpAuthentication: httpAuthentication
        )
    }
}
