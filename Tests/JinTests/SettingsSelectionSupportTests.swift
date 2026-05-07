import XCTest
@testable import Jin

final class SettingsSelectionSupportTests: XCTestCase {
    func testNilSectionDefaultsToProvidersAndSelectsFirstProvider() {
        let selection = SettingsSelectionSupport.validatedSelection(
            SettingsSelectionSupport.Selection(
                section: nil,
                providerID: nil,
                serverID: "server-a",
                pluginID: "plugin-a",
                generalCategory: .data
            ),
            providerIDs: ["provider-a", "provider-b"],
            serverIDs: ["server-a"],
            pluginIDs: ["plugin-a"]
        )

        XCTAssertEqual(selection.section, .providers)
        XCTAssertEqual(selection.providerID, "provider-a")
        XCTAssertNil(selection.serverID)
        XCTAssertNil(selection.pluginID)
        XCTAssertNil(selection.generalCategory)
    }

    func testProviderSelectionIsPreservedWhenVisible() {
        let selection = SettingsSelectionSupport.validatedSelection(
            SettingsSelectionSupport.Selection(
                section: .providers,
                providerID: "provider-b"
            ),
            providerIDs: ["provider-a", "provider-b"],
            serverIDs: [],
            pluginIDs: []
        )

        XCTAssertEqual(selection.providerID, "provider-b")
    }

    func testProviderSelectionFallsBackToFirstVisibleProvider() {
        let selection = SettingsSelectionSupport.validatedSelection(
            SettingsSelectionSupport.Selection(
                section: .providers,
                providerID: "missing"
            ),
            providerIDs: ["provider-a", "provider-b"],
            serverIDs: [],
            pluginIDs: []
        )

        XCTAssertEqual(selection.providerID, "provider-a")
    }

    func testProviderSelectionClearsWhenNoProvidersAreVisible() {
        let selection = SettingsSelectionSupport.validatedSelection(
            SettingsSelectionSupport.Selection(
                section: .providers,
                providerID: "provider-a"
            ),
            providerIDs: [],
            serverIDs: [],
            pluginIDs: []
        )

        XCTAssertNil(selection.providerID)
    }

    func testMCPServerSelectionIsValidatedAgainstVisibleServers() {
        let selection = SettingsSelectionSupport.validatedSelection(
            SettingsSelectionSupport.Selection(
                section: .mcpServers,
                providerID: "provider-a",
                serverID: "missing",
                pluginID: "plugin-a",
                generalCategory: .data
            ),
            providerIDs: ["provider-a"],
            serverIDs: ["server-a", "server-b"],
            pluginIDs: ["plugin-a"]
        )

        XCTAssertEqual(selection.section, .mcpServers)
        XCTAssertNil(selection.providerID)
        XCTAssertEqual(selection.serverID, "server-a")
        XCTAssertNil(selection.pluginID)
        XCTAssertNil(selection.generalCategory)
    }

    func testPluginSelectionIsValidatedAgainstVisiblePlugins() {
        let selection = SettingsSelectionSupport.validatedSelection(
            SettingsSelectionSupport.Selection(
                section: .plugins,
                pluginID: "plugin-b"
            ),
            providerIDs: [],
            serverIDs: [],
            pluginIDs: ["plugin-a", "plugin-b"]
        )

        XCTAssertEqual(selection.pluginID, "plugin-b")
    }

    func testGeneralSelectionDefaultsCategoryAndClearsOtherSelections() {
        let selection = SettingsSelectionSupport.validatedSelection(
            SettingsSelectionSupport.Selection(
                section: .general,
                providerID: "provider-a",
                serverID: "server-a",
                pluginID: "plugin-a",
                generalCategory: nil
            ),
            providerIDs: ["provider-a"],
            serverIDs: ["server-a"],
            pluginIDs: ["plugin-a"]
        )

        XCTAssertEqual(selection.section, .general)
        XCTAssertNil(selection.providerID)
        XCTAssertNil(selection.serverID)
        XCTAssertNil(selection.pluginID)
        XCTAssertEqual(selection.generalCategory, .appearance)
    }
}
