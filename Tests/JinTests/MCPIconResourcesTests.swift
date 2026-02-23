import XCTest
@testable import Jin

final class MCPIconResourcesTests: XCTestCase {
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
