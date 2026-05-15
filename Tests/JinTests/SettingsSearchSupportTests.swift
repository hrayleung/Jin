import XCTest
@testable import Jin

final class SettingsSearchSupportTests: XCTestCase {
    func testTrimmedSearchTextTrimsWhitespaceAndNewlines() {
        XCTAssertEqual(SettingsSearchSupport.trimmedSearchText(" \n web\t "), "web")
    }

    func testTrimmedSearchTextReturnsEmptyStringForBlankSearch() {
        XCTAssertEqual(SettingsSearchSupport.trimmedSearchText(" \n\t "), "")
    }

    func testFilteredPluginsReturnsAllPluginsForBlankSearch() {
        let plugins = [
            plugin(id: "web", name: "Web Search", summary: "Built-in search tools"),
            plugin(id: "tts", name: "Text to Speech", summary: "Play replies aloud")
        ]

        XCTAssertEqual(
            SettingsSearchSupport.filteredPlugins(plugins, searchText: " \n ").map(\.id),
            ["web", "tts"]
        )
    }

    func testFilteredPluginsMatchesNameAndSummaryCaseInsensitively() {
        let plugins = [
            plugin(id: "web", name: "Web Search", summary: "Built-in search tools"),
            plugin(id: "tts", name: "Text to Speech", summary: "Play assistant replies aloud"),
            plugin(id: "ocr", name: "Mistral OCR", summary: "Extract PDF text")
        ]

        XCTAssertEqual(
            SettingsSearchSupport.filteredPlugins(plugins, searchText: " speech ").map(\.id),
            ["tts"]
        )
        XCTAssertEqual(
            SettingsSearchSupport.filteredPlugins(plugins, searchText: "PDF").map(\.id),
            ["ocr"]
        )
    }

    func testFilteredProvidersReturnsAllProvidersForBlankSearch() {
        let providers = [
            provider(id: "openai", name: "OpenAI", type: .openai),
            provider(id: "anthropic", name: "Anthropic", type: .anthropic)
        ]

        XCTAssertEqual(
            SettingsSearchSupport.filteredProviders(providers, searchText: " \n ").map(\.id),
            ["openai", "anthropic"]
        )
    }

    func testFilteredProvidersMatchesNameTypeDisplayNameAndBaseURL() {
        let providers = [
            provider(
                id: "custom",
                name: "Work Gateway",
                type: .openaiCompatible,
                baseURL: "https://llm.example.com/v1"
            ),
            provider(
                id: "deepseek",
                name: "Reasoner",
                type: .deepseek,
                baseURL: "https://api.deepseek.com"
            )
        ]

        XCTAssertEqual(
            SettingsSearchSupport.filteredProviders(providers, searchText: "work").map(\.id),
            ["custom"]
        )
        XCTAssertEqual(
            SettingsSearchSupport.filteredProviders(providers, searchText: "deepseek").map(\.id),
            ["deepseek"]
        )
        XCTAssertEqual(
            SettingsSearchSupport.filteredProviders(providers, searchText: "LLM.EXAMPLE").map(\.id),
            ["custom"]
        )
    }

    func testFilteredProvidersTrimsPaddedSearchText() {
        let providers = [
            provider(id: "openrouter", name: "OpenRouter", type: .openrouter),
            provider(id: "anthropic", name: "Anthropic", type: .anthropic)
        ]

        XCTAssertEqual(
            SettingsSearchSupport.filteredProviders(providers, searchText: " \n openrouter\t ").map(\.id),
            ["openrouter"]
        )
    }

    func testFilteredMCPServersReturnsAllServersForBlankSearch() throws {
        let servers = try [
            server(id: "filesystem", name: "Filesystem", transport: .stdio(MCPStdioTransportConfig(command: "npx"))),
            server(id: "remote", name: "Remote MCP", transport: .http(httpTransport("https://mcp.example.com")))
        ]

        XCTAssertEqual(
            SettingsSearchSupport.filteredMCPServers(servers, searchText: " \n ").map(\.id),
            ["filesystem", "remote"]
        )
    }

    func testFilteredMCPServersMatchesNameIDTransportSummaryAndKind() throws {
        let servers = try [
            server(id: "filesystem", name: "Filesystem", transport: .stdio(MCPStdioTransportConfig(command: "npx"))),
            server(id: "remote-docs", name: "Docs Server", transport: .http(httpTransport("https://mcp.example.com/sse"))),
            server(id: "shell", name: "Command Runner", transport: .stdio(MCPStdioTransportConfig(command: "uvx")))
        ]

        XCTAssertEqual(
            SettingsSearchSupport.filteredMCPServers(servers, searchText: "docs").map(\.id),
            ["remote-docs"]
        )
        XCTAssertEqual(
            SettingsSearchSupport.filteredMCPServers(servers, searchText: "remote").map(\.id),
            ["remote-docs"]
        )
        XCTAssertEqual(
            SettingsSearchSupport.filteredMCPServers(servers, searchText: "MCP.EXAMPLE").map(\.id),
            ["remote-docs"]
        )
        XCTAssertEqual(
            SettingsSearchSupport.filteredMCPServers(servers, searchText: "http").map(\.id),
            ["remote-docs"]
        )
    }

    func testFilteredMCPServersTrimsPaddedSearchText() throws {
        let servers = try [
            server(id: "filesystem", name: "Filesystem", transport: .stdio(MCPStdioTransportConfig(command: "npx"))),
            server(id: "remote", name: "Remote MCP", transport: .http(httpTransport("https://mcp.example.com")))
        ]

        XCTAssertEqual(
            SettingsSearchSupport.filteredMCPServers(servers, searchText: " \n remote\t ").map(\.id),
            ["remote"]
        )
    }

    private func plugin(
        id: String,
        name: String,
        summary: String
    ) -> SettingsView.PluginDescriptor {
        SettingsView.PluginDescriptor(
            id: id,
            name: name,
            systemImage: "gearshape",
            summary: summary
        )
    }

    private func provider(
        id: String,
        name: String,
        type: ProviderType,
        baseURL: String? = nil
    ) -> ProviderConfigEntity {
        ProviderConfigEntity(
            id: id,
            name: name,
            typeRaw: type.rawValue,
            baseURL: baseURL,
            modelsData: Data("[]".utf8)
        )
    }

    private func server(
        id: String,
        name: String,
        transport: MCPTransportConfig
    ) throws -> MCPServerConfigEntity {
        MCPServerConfigEntity(
            id: id,
            name: name,
            transportKindRaw: transport.kind.rawValue,
            transportData: try JSONEncoder().encode(transport)
        )
    }

    private func httpTransport(_ endpoint: String) -> MCPHTTPTransportConfig {
        MCPHTTPTransportConfig(
            endpoint: URL(string: endpoint)!,
            streaming: true,
            authentication: .none,
            additionalHeaders: []
        )
    }
}
