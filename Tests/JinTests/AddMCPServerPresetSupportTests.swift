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

    func testExaLocalPresetReplacesIdentityAndKeepsExistingAPIKey() {
        let draft = AddMCPServerPresetSupport.applyingPreset(
            .exaLocal,
            to: self.draft(
                id: "custom",
                name: "Custom",
                envPairs: [EnvironmentVariablePair(key: "EXA_API_KEY", value: "secret")]
            )
        )

        XCTAssertEqual(draft.id, "exa")
        XCTAssertEqual(draft.name, "Exa")
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

    func testTinyFishPresetFillsOfficialHTTPEndpointAndIcon() {
        let draft = AddMCPServerPresetSupport.applyingPreset(.tinyfish, to: self.draft(id: "", name: ""))

        XCTAssertEqual(draft.id, "tinyfish")
        XCTAssertEqual(draft.name, "TinyFish")
        XCTAssertEqual(draft.iconID, "tinyfish")
        XCTAssertEqual(draft.transportKind, .http)
        XCTAssertEqual(draft.endpoint, "https://agent.tinyfish.ai/mcp")
        XCTAssertEqual(draft.httpAuthentication, .oauth)
    }

    func testGitHubPresetUsesOfficialRemoteEndpointAndPersonalAccessToken() {
        let draft = AddMCPServerPresetSupport.applyingPreset(.github, to: self.draft(id: "", name: ""))

        XCTAssertEqual(draft.id, "github")
        XCTAssertEqual(draft.iconID, "github")
        XCTAssertEqual(draft.transportKind, .http)
        XCTAssertEqual(draft.endpoint, "https://api.githubcopilot.com/mcp/")
        XCTAssertEqual(draft.httpAuthentication, .bearerToken(""))
    }

    func testSwitchingFromGitHubToTinyFishReplacesIdentityAndEndpoint() {
        let github = AddMCPServerPresetSupport.applyingPreset(.github, to: .blank)
        let tinyfish = AddMCPServerPresetSupport.applyingPreset(.tinyfish, to: github)

        XCTAssertEqual(tinyfish.id, "tinyfish")
        XCTAssertEqual(tinyfish.name, "TinyFish")
        XCTAssertEqual(tinyfish.iconID, "tinyfish")
        XCTAssertEqual(tinyfish.endpoint, "https://agent.tinyfish.ai/mcp")
        XCTAssertEqual(tinyfish.httpAuthentication, .oauth)
    }

    func testTavilyPresetUsesCanonicalResourceEndpoint() {
        let draft = AddMCPServerPresetSupport.applyingPreset(.tavily, to: .blank)
        XCTAssertEqual(draft.endpoint, "https://mcp.tavily.com/mcp")
        XCTAssertEqual(draft.httpAuthentication, .oauth)
    }

    func testContext7PresetUsesOfficialHeader() {
        let draft = AddMCPServerPresetSupport.applyingPreset(.context7, to: self.draft(id: "", name: ""))

        XCTAssertEqual(draft.endpoint, "https://mcp.context7.com/mcp")
        XCTAssertEqual(
            draft.httpAuthentication,
            .header(MCPHeader(name: "CONTEXT7_API_KEY", value: "", isSensitive: true))
        )
    }

    func testPlaywrightPresetUsesOfficialLocalPackage() {
        let draft = AddMCPServerPresetSupport.applyingPreset(.playwright, to: self.draft(id: "", name: ""))

        XCTAssertEqual(draft.transportKind, .stdio)
        XCTAssertEqual(draft.command, "npx")
        XCTAssertEqual(draft.args, "-y @playwright/mcp@latest")
        XCTAssertEqual(draft.iconID, "playwright")
    }

    func testFilesystemPresetIncludesAllowedPath() {
        let draft = AddMCPServerPresetSupport.applyingPreset(.filesystem, to: self.draft(id: "", name: ""))

        XCTAssertEqual(draft.command, "npx")
        XCTAssertTrue(draft.args.contains("@modelcontextprotocol/server-filesystem"))
        XCTAssertEqual(
            AddMCPServerPresetSupport.filesystemPath(from: draft.args),
            AddMCPServerPresetSupport.defaultFilesystemPath()
        )
    }

    func testApplyingOAuthCredentialKeepsOAuthKind() {
        let seeded = AddMCPServerPresetSupport.applyingPreset(.linear, to: draft(id: "", name: ""))
        let updated = AddMCPServerPresetSupport.applyingCredential("", for: .linear, to: seeded)

        XCTAssertEqual(updated.httpAuthentication, .oauth)
    }

    func testReplacingFilesystemPathKeepsPackageArgs() {
        let updated = AddMCPServerPresetSupport.replacingFilesystemPath(
            in: "-y @modelcontextprotocol/server-filesystem /tmp/old",
            with: "/tmp/allowed"
        )

        XCTAssertEqual(updated, "-y @modelcontextprotocol/server-filesystem /tmp/allowed")
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
