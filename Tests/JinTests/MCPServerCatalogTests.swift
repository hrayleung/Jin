import XCTest
@testable import Jin

final class MCPServerCatalogTests: XCTestCase {
    func testCatalogIncludesTinyFishAndKeepsExistingPresets() {
        let presets = Set(MCPServerCatalog.items.map(\.preset))

        XCTAssertTrue(presets.contains(.tinyfish))
        XCTAssertTrue(presets.contains(.exaHTTP))
        XCTAssertTrue(presets.contains(.firecrawlLocal))
        XCTAssertTrue(presets.contains(.github))
        XCTAssertTrue(presets.contains(.context7))
        XCTAssertTrue(presets.contains(.playwright))
    }

    func testFilterByCategoryAndSearch() {
        let search = MCPServerCatalog.filtered(query: "", category: .search)
        XCTAssertEqual(Set(search.map(\.preset)), [.exaHTTP, .tavily, .exaLocal])

        let tinyfish = MCPServerCatalog.filtered(query: "tinyfish", category: .all)
        XCTAssertEqual(tinyfish.map(\.preset), [.tinyfish])

        let browser = MCPServerCatalog.filtered(query: "play", category: .browser)
        XCTAssertEqual(browser.map(\.preset), [.playwright])
    }

    func testOfficialHTTPEndpointsAreAbsoluteHTTPS() {
        for item in MCPServerCatalog.items {
            guard let draft = optionalHTTPDraft(for: item.preset) else { continue }
            let url = MCPServerFormSupport.parsedEndpoint(draft.endpoint)
            XCTAssertNotNil(url, "\(item.title) is missing a valid HTTP endpoint")
            XCTAssertEqual(url?.scheme, "https", "\(item.title) should use https")
        }
    }

    private func optionalHTTPDraft(for preset: AddMCPServerPreset) -> AddMCPServerPresetSupport.Draft? {
        let draft = AddMCPServerPresetSupport.applyingPreset(
            preset,
            to: AddMCPServerPresetSupport.Draft(
                id: "",
                name: "",
                transportKind: .stdio,
                command: "",
                args: "",
                envPairs: [],
                endpoint: "",
                headerPairs: [],
                httpAuthentication: .none
            )
        )
        return draft.transportKind == .http ? draft : nil
    }
}
