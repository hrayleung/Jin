import XCTest
@testable import Jin

final class BraveSearchAPITests: XCTestCase {
    func testMakeWebSearchURLClampsCountToMaximum() throws {
        let url = try XCTUnwrap(
            BraveSearchAPI.makeWebSearchURL(query: "test", count: 50)
        )

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []
        XCTAssertTrue(queryItems.contains(where: { $0.name == "count" && $0.value == "20" }))
    }

    func testMakeWebSearchURLClampsOffsetToMaximum() throws {
        let url = try XCTUnwrap(
            BraveSearchAPI.makeWebSearchURL(query: "test", count: 20, offset: 123)
        )

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []
        XCTAssertTrue(queryItems.contains(where: { $0.name == "offset" && $0.value == "9" }))
    }

    func testMakeWebSearchURLIncludesOptionalQueryItems() throws {
        let url = try XCTUnwrap(
            BraveSearchAPI.makeWebSearchURL(
                query: "test",
                count: 10,
                offset: 1,
                freshness: "pd",
                country: "US",
                searchLanguage: "en",
                uiLanguage: "en-US",
                safesearch: "strict",
                extraSnippets: true,
                goggles: ["g1", "g2"],
                summary: true,
                enableRichCallback: true
            )
        )

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []

        XCTAssertTrue(queryItems.contains(where: { $0.name == "q" && $0.value == "test" }))
        XCTAssertTrue(queryItems.contains(where: { $0.name == "count" && $0.value == "10" }))
        XCTAssertTrue(queryItems.contains(where: { $0.name == "offset" && $0.value == "1" }))
        XCTAssertTrue(queryItems.contains(where: { $0.name == "freshness" && $0.value == "pd" }))
        XCTAssertTrue(queryItems.contains(where: { $0.name == "country" && $0.value == "US" }))
        XCTAssertTrue(queryItems.contains(where: { $0.name == "search_lang" && $0.value == "en" }))
        XCTAssertTrue(queryItems.contains(where: { $0.name == "ui_lang" && $0.value == "en-US" }))
        XCTAssertTrue(queryItems.contains(where: { $0.name == "safesearch" && $0.value == "strict" }))
        XCTAssertTrue(queryItems.contains(where: { $0.name == "extra_snippets" && $0.value == "true" }))
        XCTAssertEqual(queryItems.filter { $0.name == "goggles" }.compactMap(\.value), ["g1", "g2"])
        XCTAssertTrue(queryItems.contains(where: { $0.name == "summary" && $0.value == "1" }))
        XCTAssertTrue(queryItems.contains(where: { $0.name == "enable_rich_callback" && $0.value == "1" }))
    }

    func testMakeWebSearchURLOmitsExtraSnippetsWhenFalse() throws {
        let url = try XCTUnwrap(
            BraveSearchAPI.makeWebSearchURL(query: "test", count: 10, extraSnippets: false)
        )

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []
        XCTAssertFalse(queryItems.contains(where: { $0.name == "extra_snippets" }))
    }

    func testMakeWebSearchURLPassesCustomDateRangeFreshnessVerbatim() throws {
        let url = try XCTUnwrap(
            BraveSearchAPI.makeWebSearchURL(
                query: "test",
                count: 10,
                freshness: "2026-01-01to2026-02-01"
            )
        )

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []
        XCTAssertTrue(queryItems.contains(where: {
            $0.name == "freshness" && $0.value == "2026-01-01to2026-02-01"
        }))
    }

    func testBraveDateRangeFreshnessProducesUTCWindow() {
        let now = ISO8601DateFormatter().date(from: "2026-05-09T12:34:56Z")!

        let value = BuiltinSearchToolHub.braveDateRangeFreshness(recencyDays: 7, now: now)

        XCTAssertEqual(value, "2026-05-02to2026-05-09")
    }
}

