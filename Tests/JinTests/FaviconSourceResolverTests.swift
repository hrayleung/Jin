import XCTest
import Kingfisher
@testable import Jin

final class FaviconSourceResolverTests: XCTestCase {
    func testNormalizedHostParsesURLAndRawHost() {
        XCTAssertEqual(
            FaviconSourceResolver.normalizedHost(from: " https://WWW.Example.com/path?q=1 "),
            "www.example.com"
        )
        XCTAssertEqual(
            FaviconSourceResolver.normalizedHost(from: "news.ycombinator.com"),
            "news.ycombinator.com"
        )
        XCTAssertNil(FaviconSourceResolver.normalizedHost(from: ""))
        XCTAssertNil(FaviconSourceResolver.normalizedHost(from: "   "))
    }

    func testHostCandidatesIncludeApexFallback() {
        XCTAssertEqual(
            FaviconSourceResolver.hostCandidates(for: "edition.cnn.com"),
            ["edition.cnn.com", "cnn.com"]
        )
        XCTAssertEqual(
            FaviconSourceResolver.hostCandidates(for: "news.bbc.co.uk"),
            ["news.bbc.co.uk", "bbc.co.uk"]
        )
        XCTAssertEqual(
            FaviconSourceResolver.hostCandidates(for: "reuters.com"),
            ["reuters.com"]
        )
    }

    func testRequestURLsIncludeDuckDuckGoAndGoogleVariants() {
        let urls = FaviconSourceResolver.requestURLs(for: "example.com").map(\.absoluteString)

        XCTAssertEqual(urls.count, 3)
        XCTAssertEqual(urls[0], "https://icons.duckduckgo.com/ip3/example.com.ico")
        XCTAssertTrue(urls[1].contains("https://www.google.com/s2/favicons"))
        XCTAssertTrue(urls[1].contains("domain=example.com"))
        XCTAssertTrue(urls[2].contains("https://www.google.com/s2/favicons"))
        XCTAssertTrue(urls[2].contains("domain_url=https://example.com"))
    }

    func testSourcesBuildFallbackChainWithSharedHostCacheKey() {
        guard let resolved = FaviconSourceResolver.sources(for: "api.example.com") else {
            XCTFail("Expected resolved sources")
            return
        }

        XCTAssertEqual(resolved.normalizedHost, "api.example.com")
        XCTAssertEqual(resolved.cacheKey, "favicon_api.example.com")

        let allSources = [resolved.primary] + resolved.alternatives
        XCTAssertEqual(allSources.count, 6)
        XCTAssertEqual(resolved.alternatives.count, 5)

        let urls = allSources.compactMap { $0.url?.absoluteString }
        XCTAssertEqual(urls.count, 6)
        XCTAssertTrue(urls[0].contains("duckduckgo.com"))
        XCTAssertTrue(urls[0].contains("api.example.com"))
        XCTAssertTrue(urls[3].contains("duckduckgo.com"))
        XCTAssertTrue(urls[3].contains("example.com"))

        var cacheKeys: Set<String> = []
        for source in allSources {
            if case .network(let resource) = source {
                cacheKeys.insert(resource.cacheKey)
            }
        }
        XCTAssertEqual(cacheKeys, [resolved.cacheKey])
    }

    func testRequestModifierAppliesHeadersAndTimeout() {
        let request = URLRequest(url: URL(string: "https://example.com/favicon.ico")!)
        let modified = FaviconSourceResolver.requestModifier.modified(for: request)

        XCTAssertEqual(modified?.timeoutInterval, FaviconSourceResolver.Configuration.requestTimeout)
        XCTAssertEqual(modified?.value(forHTTPHeaderField: "Accept"), FaviconSourceResolver.Configuration.acceptHeader)
        XCTAssertEqual(modified?.value(forHTTPHeaderField: "User-Agent"), FaviconSourceResolver.Configuration.userAgent)
    }

    func testOptionsIncludeAlternativeSourcesAndDownloader() {
        guard let resolved = FaviconSourceResolver.sources(for: "api.example.com") else {
            XCTFail("Expected resolved sources")
            return
        }

        let cache = ImageCache(name: UUID().uuidString)
        let downloader = ImageDownloader(name: UUID().uuidString)
        let parsed = KingfisherParsedOptionsInfo(
            FaviconSourceResolver.options(for: resolved, cache: cache, downloader: downloader)
        )

        XCTAssertTrue(parsed.targetCache === cache)
        XCTAssertTrue(parsed.originalCache === cache)
        XCTAssertTrue(parsed.downloader === downloader)
        XCTAssertNotNil(parsed.requestModifier)
        XCTAssertEqual(parsed.alternativeSources?.count, resolved.alternatives.count)
    }

    // MARK: - FaviconFailureCache

    func testFailureCacheRecordsAndBlocksHost() {
        let cache = FaviconFailureCache(ttl: 3600)
        XCTAssertFalse(cache.isHostFailed("example.com"))

        cache.recordFailure(for: "example.com")
        XCTAssertTrue(cache.isHostFailed("example.com"))
        XCTAssertFalse(cache.isHostFailed("other.com"))
    }

    func testFailureCacheExpiresAfterTTL() {
        let cache = FaviconFailureCache(ttl: 0)
        cache.recordFailure(for: "example.com")
        XCTAssertFalse(cache.isHostFailed("example.com"))
    }

    func testFailureCacheIsolatesHosts() {
        let cache = FaviconFailureCache(ttl: 3600)
        cache.recordFailure(for: "bad.example.com")

        XCTAssertTrue(cache.isHostFailed("bad.example.com"))
        XCTAssertFalse(cache.isHostFailed("good.example.com"))
        XCTAssertFalse(cache.isHostFailed("example.com"))
    }
}
