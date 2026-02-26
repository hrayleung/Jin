import XCTest
@testable import Jin

final class WebsiteFaviconRepositoryTests: XCTestCase {
    func testNormalizedHostParsesURLAndRawHost() {
        XCTAssertEqual(
            WebsiteFaviconRepository.normalizedHost(from: " https://WWW.Example.com/path?q=1 "),
            "www.example.com"
        )
        XCTAssertEqual(
            WebsiteFaviconRepository.normalizedHost(from: "news.ycombinator.com"),
            "news.ycombinator.com"
        )
        XCTAssertNil(WebsiteFaviconRepository.normalizedHost(from: ""))
        XCTAssertNil(WebsiteFaviconRepository.normalizedHost(from: "   "))
    }

    func testHostCandidatesIncludeApexFallback() {
        XCTAssertEqual(
            WebsiteFaviconRepository.hostCandidates(for: "edition.cnn.com"),
            ["edition.cnn.com", "cnn.com"]
        )
        XCTAssertEqual(
            WebsiteFaviconRepository.hostCandidates(for: "news.bbc.co.uk"),
            ["news.bbc.co.uk", "bbc.co.uk"]
        )
        XCTAssertEqual(
            WebsiteFaviconRepository.hostCandidates(for: "reuters.com"),
            ["reuters.com"]
        )
    }

    func testRequestURLsIncludeDuckDuckGoAndGoogleVariants() {
        let urls = WebsiteFaviconRepository.requestURLs(for: "example.com").map(\.absoluteString)

        XCTAssertEqual(urls.count, 3)
        XCTAssertEqual(urls[0], "https://icons.duckduckgo.com/ip3/example.com.ico")
        XCTAssertTrue(urls[1].contains("https://www.google.com/s2/favicons"))
        XCTAssertTrue(urls[1].contains("domain=example.com"))
        XCTAssertTrue(urls[2].contains("https://www.google.com/s2/favicons"))
        XCTAssertTrue(urls[2].contains("domain_url=https://example.com"))
    }
}
