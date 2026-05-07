import XCTest
@testable import Jin

final class WebSearchPluginSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "WebSearchPluginSettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testLoadClampsStoredDefaultMaxResultsAndRecency() {
        defaults.set(99, forKey: AppPreferenceKeys.pluginWebSearchDefaultMaxResults)
        defaults.set(999, forKey: AppPreferenceKeys.pluginWebSearchDefaultRecencyDays)

        let settings = WebSearchPluginSettingsStore.load(defaults: defaults)

        XCTAssertEqual(settings.defaultMaxResults, 50)
        XCTAssertEqual(settings.defaultRecencyDays, 365)
    }

    func testLoadUsesDefaultMaxResultsForZeroAndNilRecencyForNonPositiveValues() {
        defaults.set(0, forKey: AppPreferenceKeys.pluginWebSearchDefaultMaxResults)
        defaults.set(0, forKey: AppPreferenceKeys.pluginWebSearchDefaultRecencyDays)

        let settings = WebSearchPluginSettingsStore.load(defaults: defaults)

        XCTAssertEqual(settings.defaultMaxResults, 8)
        XCTAssertNil(settings.defaultRecencyDays)
    }
}
