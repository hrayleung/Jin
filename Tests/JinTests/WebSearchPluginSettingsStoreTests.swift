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

    func testLoadCarriesNewExaPreferences() {
        defaults.set("research paper", forKey: AppPreferenceKeys.pluginWebSearchExaCategory)
        defaults.set("DE", forKey: AppPreferenceKeys.pluginWebSearchExaUserLocation)
        defaults.set(true, forKey: AppPreferenceKeys.pluginWebSearchExaModeration)

        let settings = WebSearchPluginSettingsStore.load(defaults: defaults)

        XCTAssertEqual(settings.exaCategory, "research paper")
        XCTAssertEqual(settings.exaUserLocation, "DE")
        XCTAssertTrue(settings.exaModeration)
    }

    func testLoadFirecrawlCountryIsIndependentFromBraveCountry() {
        defaults.set("US", forKey: AppPreferenceKeys.pluginWebSearchBraveCountry)
        defaults.set("DE", forKey: AppPreferenceKeys.pluginWebSearchFirecrawlCountry)

        let settings = WebSearchPluginSettingsStore.load(defaults: defaults)

        XCTAssertEqual(settings.braveCountry, "US")
        XCTAssertEqual(settings.firecrawlCountry, "DE")
    }

    func testLoadFirecrawlSourcesDecodesJSONArray() throws {
        let raw = WebSearchPluginSettingsStore.encodeFirecrawlSources([.web, .news])
        defaults.set(raw, forKey: AppPreferenceKeys.pluginWebSearchFirecrawlSources)

        let settings = WebSearchPluginSettingsStore.load(defaults: defaults)

        XCTAssertEqual(settings.firecrawlSources, [.web, .news])
    }

    func testLoadFirecrawlSourcesDefaultsToEmptyForGarbage() {
        defaults.set("not-json", forKey: AppPreferenceKeys.pluginWebSearchFirecrawlSources)

        let settings = WebSearchPluginSettingsStore.load(defaults: defaults)

        XCTAssertEqual(settings.firecrawlSources, [])
    }

    func testFirecrawlSourceSelectionDefaultsToWebForEmptyOrInvalidStorage() {
        XCTAssertEqual(WebSearchPluginSettingsStore.firecrawlSourceSelection(from: ""), [.web])
        XCTAssertEqual(WebSearchPluginSettingsStore.firecrawlSourceSelection(from: "not-json"), [.web])
        XCTAssertEqual(WebSearchPluginSettingsStore.firecrawlSourceSelection(from: "[]"), [.web])
    }

    func testFirecrawlSourceSelectionUsesDecodedSourcesWhenPresent() {
        let raw = WebSearchPluginSettingsStore.encodeFirecrawlSources([.news, .images])

        XCTAssertEqual(WebSearchPluginSettingsStore.firecrawlSourceSelection(from: raw), [.news, .images])
    }

    func testLoadCarriesNewTavilyPreferences() {
        defaults.set("DE", forKey: AppPreferenceKeys.pluginWebSearchTavilyCountry)
        defaults.set(true, forKey: AppPreferenceKeys.pluginWebSearchTavilyAutoParameters)

        let settings = WebSearchPluginSettingsStore.load(defaults: defaults)

        XCTAssertEqual(settings.tavilyCountry, "DE")
        XCTAssertTrue(settings.tavilyAutoParameters)
    }

    func testLoadCarriesNewPerplexityPreferences() {
        defaults.set("DE", forKey: AppPreferenceKeys.pluginWebSearchPerplexityCountry)
        defaults.set("en", forKey: AppPreferenceKeys.pluginWebSearchPerplexityLanguage)

        let settings = WebSearchPluginSettingsStore.load(defaults: defaults)

        XCTAssertEqual(settings.perplexityCountry, "DE")
        XCTAssertEqual(settings.perplexityLanguage, "en")
    }

    func testLoadCarriesNewJinaPreferences() {
        defaults.set("DE", forKey: AppPreferenceKeys.pluginWebSearchJinaCountry)
        defaults.set("de-DE", forKey: AppPreferenceKeys.pluginWebSearchJinaLocale)

        let settings = WebSearchPluginSettingsStore.load(defaults: defaults)

        XCTAssertEqual(settings.jinaCountry, "DE")
        XCTAssertEqual(settings.jinaLocale, "de-DE")
    }
}
