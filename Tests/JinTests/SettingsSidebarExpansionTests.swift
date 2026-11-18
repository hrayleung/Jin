import XCTest

final class SettingsSidebarExpansionTests: XCTestCase {
    /// Every collapsible sidebar group shares one policy: expanded on first
    /// run, then whatever the user last left. Arbitrary per-group `@State`
    /// defaults must not come back — they reset on every window open and made
    /// the sidebar look randomly half-collapsed.
    func testCollapsibleGroupsPersistExpansionWithExpandedDefaults() throws {
        let sidebar = try sourceFile("Sources/UI/SettingsSidebarColumn.swift")

        XCTAssertFalse(
            sidebar.contains("Expanded = false"),
            "Collapsible groups must default to expanded"
        )
        for key in [
            "settingsSidebarProvidersExpanded",
            "settingsSidebarMCPServersExpanded",
            "settingsSidebarPluginsExpanded",
        ] {
            XCTAssertTrue(
                sidebar.contains("@AppStorage(AppPreferenceKeys.\(key))"),
                "Missing persisted expansion binding for \(key)"
            )
        }
        let expandedDeclarations = sidebar.components(separatedBy: .newlines)
            .filter { $0.contains("private var") && $0.contains("Expanded = true") }
        XCTAssertEqual(
            expandedDeclarations.count,
            3,
            "Expected exactly three expanded-by-default groups"
        )
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        try String(contentsOfFile: relativePath, encoding: .utf8)
    }
}
