import XCTest
@testable import Jin

final class MCPIconResourcesTests: XCTestCase {
    func testBundledCatalogIsNotTheThreeIconFallback() {
        let ids = Set(MCPIconCatalog.all.map(\.id))
        let required = [
            "mcp", "tinyfish", "exa", "tavily", "firecrawl",
            "playwright", "github", "notion", "linear", "context7"
        ]

        XCTAssertGreaterThan(
            MCPIconCatalog.all.count,
            20,
            "Catalog collapsed to fallback (\(MCPIconCatalog.all.map(\.id).joined(separator: ", "))). SwiftPM flattens mcpIcons/ into the bundle root."
        )
        for id in required {
            XCTAssertTrue(ids.contains(id), "Missing bundled MCP icon \(id)")
        }
    }

    func testBundledMCPIconsIncludeAllCatalogEntries() {
        var missing: [String] = []

        for icon in MCPIconCatalog.all {
            if icon.localPNGImage(useDarkMode: false) == nil {
                missing.append("light:\(icon.id)")
            }
            if icon.localPNGImage(useDarkMode: true) == nil {
                missing.append("dark:\(icon.id)")
            }
        }

        XCTAssertTrue(missing.isEmpty, "Missing bundled MCP icons: \(missing.joined(separator: ", "))")
    }

    func testIconsFromMixedBundleKeepMCPSuffixNamesAndDropProviderPrefixes() {
        let urls = [
            URL(fileURLWithPath: "/tmp/tinyfish_light.png"),
            URL(fileURLWithPath: "/tmp/tinyfish_dark.png"),
            URL(fileURLWithPath: "/tmp/tavily_light.png"),
            URL(fileURLWithPath: "/tmp/tavily_dark.png"),
            URL(fileURLWithPath: "/tmp/light_openai.png"),
            URL(fileURLWithPath: "/tmp/dark_openai.png"),
            URL(fileURLWithPath: "/tmp/github_light.png"),
            URL(fileURLWithPath: "/tmp/github_dark.png")
        ]

        XCTAssertEqual(
            MCPIconCatalog.icons(fromPNGURLs: urls).map(\.id),
            ["mcp", "github", "tavily", "tinyfish"]
        )
    }

    func testResolvedIconIDFallsBackToDefault() {
        XCTAssertEqual(MCPIconCatalog.resolvedIconID(for: nil), MCPIconCatalog.defaultIconID)
        XCTAssertEqual(MCPIconCatalog.resolvedIconID(for: "  "), MCPIconCatalog.defaultIconID)
        XCTAssertEqual(MCPIconCatalog.resolvedIconID(for: "unknown"), MCPIconCatalog.defaultIconID)
    }

    func testServerEntityResolvedIconIDPrefersKnownSelection() {
        let entity = MCPServerConfigEntity(
            id: "exa",
            name: "Exa",
            iconID: "exa",
            transportKindRaw: MCPTransportKind.stdio.rawValue,
            transportData: Data(),
            lifecycleRaw: MCPLifecyclePolicy.persistent.rawValue,
            isEnabled: true,
            runToolsAutomatically: true,
            isLongRunning: true
        )

        XCTAssertEqual(entity.resolvedMCPIconID, "exa")

        entity.iconID = "missing"
        XCTAssertEqual(entity.resolvedMCPIconID, MCPIconCatalog.defaultIconID)
    }
}
