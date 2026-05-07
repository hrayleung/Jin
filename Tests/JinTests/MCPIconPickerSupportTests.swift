import XCTest
@testable import Jin

final class MCPIconPickerSupportTests: XCTestCase {
    private let icons = [
        MCPIcon(id: "mcp", lightResourceName: "mcp_light", darkResourceName: "mcp_dark"),
        MCPIcon(id: "exa", lightResourceName: "exa_light", darkResourceName: "exa_dark"),
        MCPIcon(id: "github", lightResourceName: "github_light", darkResourceName: "github_dark")
    ]

    func testNormalizedCustomIconIDTrimsAndTreatsDefaultAsNil() {
        XCTAssertNil(MCPIconPickerSupport.normalizedCustomIconID(nil, defaultIconID: "mcp"))
        XCTAssertNil(MCPIconPickerSupport.normalizedCustomIconID("  ", defaultIconID: "mcp"))
        XCTAssertNil(MCPIconPickerSupport.normalizedCustomIconID(" MCP ", defaultIconID: "mcp"))
        XCTAssertEqual(MCPIconPickerSupport.normalizedCustomIconID(" exa ", defaultIconID: "mcp"), "exa")
    }

    func testActiveIconAndDisplayLabelPreferCustomSelectionOrDefault() {
        XCTAssertEqual(
            MCPIconPickerSupport.activeIconID(selectedIconID: "  ", defaultIconID: "mcp"),
            "mcp"
        )
        XCTAssertEqual(
            MCPIconPickerSupport.activeIconID(selectedIconID: " github ", defaultIconID: "mcp"),
            "github"
        )
        XCTAssertEqual(
            MCPIconPickerSupport.displayLabel(selectedIconID: " MCP ", defaultIconID: "mcp"),
            "Default"
        )
        XCTAssertEqual(
            MCPIconPickerSupport.displayLabel(selectedIconID: " github ", defaultIconID: "mcp"),
            "github"
        )
    }

    func testFilteredIconsExcludesDefaultAndSearchesCaseInsensitively() {
        XCTAssertEqual(
            MCPIconPickerSupport.selectableIcons(from: icons, defaultIconID: "MCP").map(\.id),
            ["exa", "github"]
        )
        XCTAssertEqual(
            MCPIconPickerSupport.filteredIcons(
                from: icons,
                searchText: " GIT ",
                defaultIconID: "mcp"
            ).map(\.id),
            ["github"]
        )
        XCTAssertTrue(
            MCPIconPickerSupport.filteredIcons(
                from: icons,
                searchText: "mcp",
                defaultIconID: "mcp"
            ).isEmpty
        )
    }

    func testSelectionHelpersCompareCaseInsensitively() {
        XCTAssertTrue(MCPIconPickerSupport.isDefaultSelected(nil, defaultIconID: "mcp"))
        XCTAssertTrue(MCPIconPickerSupport.isDefaultSelected(" MCP ", defaultIconID: "mcp"))
        XCTAssertFalse(MCPIconPickerSupport.isDefaultSelected("exa", defaultIconID: "mcp"))
        XCTAssertTrue(
            MCPIconPickerSupport.isSelected(
                icon: icons[1],
                selectedIconID: " EXA ",
                defaultIconID: "mcp"
            )
        )
        XCTAssertFalse(
            MCPIconPickerSupport.isSelected(
                icon: icons[2],
                selectedIconID: "exa",
                defaultIconID: "mcp"
            )
        )
    }
}
