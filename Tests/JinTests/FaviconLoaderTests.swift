import XCTest
import AppKit
import Kingfisher
@testable import Jin

private actor DownloadCounter {
    private(set) var count = 0

    func record() -> Int {
        count += 1
        return count
    }

    func value() -> Int {
        count
    }
}

private enum StubbedRetrieverError: Error {
    case failed
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

private final class MockURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let mimeType: String?
        let data: Data
    }

    private static let lock = NSLock()
    private static var stubs: [String: Stub] = [:]
    private static var requestedURLs: [String] = []

    static var recordedURLs: [String] {
        lock.withLock { requestedURLs }
    }

    static func setStub(_ stub: Stub, for url: URL) {
        lock.withLock {
            stubs[url.absoluteString] = stub
        }
    }

    static func reset() {
        lock.withLock {
            stubs.removeAll()
            requestedURLs.removeAll()
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let stub = Self.lock.withLock { () -> Stub? in
            Self.requestedURLs.append(url.absoluteString)
            return Self.stubs[url.absoluteString]
        }

        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        var headers: [String: String] = [:]
        if let mimeType = stub.mimeType {
            headers["Content-Type"] = mimeType
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: headers.isEmpty ? nil : headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !stub.data.isEmpty {
            client?.urlProtocol(self, didLoad: stub.data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class FaviconLoaderTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testConcurrentRequestsForSameHostCoalesce() async {
        let counter = DownloadCounter()

        let loader = FaviconLoader(
            failureCache: FaviconFailureCache(ttl: 3600),
            imageRetriever: { _ in
                _ = await counter.record()
                try? await Task.sleep(nanoseconds: 200_000_000)
                return Self.sampleImage()
            }
        )

        async let result1 = loader.favicon(for: "dedup-test.example.com")
        async let result2 = loader.favicon(for: "dedup-test.example.com")

        let (image1, image2) = await (result1, result2)
        XCTAssertNotNil(image1)
        XCTAssertNotNil(image2)
        let downloadCount = await counter.value()
        XCTAssertEqual(downloadCount, 1)
    }

    func testDifferentHostsAreNotCoalesced() async {
        let counter = DownloadCounter()

        let loader = FaviconLoader(
            failureCache: FaviconFailureCache(ttl: 3600),
            imageRetriever: { _ in
                _ = await counter.record()
                return Self.sampleImage()
            }
        )

        let image1 = await loader.favicon(for: "host-a.test")
        let image2 = await loader.favicon(for: "host-b.test")

        XCTAssertNotNil(image1)
        XCTAssertNotNil(image2)
        let downloadCount = await counter.value()
        XCTAssertEqual(downloadCount, 2)
    }

    func testFailedHostIsShortCircuitedWithinTTL() async {
        let counter = DownloadCounter()

        let loader = FaviconLoader(
            failureCache: FaviconFailureCache(ttl: 3600),
            imageRetriever: { _ in
                _ = await counter.record()
                throw StubbedRetrieverError.failed
            }
        )

        let firstResult = await loader.favicon(for: "fail-test.example.com")
        XCTAssertNil(firstResult)
        let countAfterFirstAttempt = await counter.value()
        XCTAssertEqual(countAfterFirstAttempt, 1)

        let secondResult = await loader.favicon(for: "fail-test.example.com")
        XCTAssertNil(secondResult)
        let countAfterSecondAttempt = await counter.value()
        XCTAssertEqual(countAfterSecondAttempt, 1)
    }

    func testFailedHostRetriesAfterTTLExpires() async {
        let counter = DownloadCounter()

        let loader = FaviconLoader(
            failureCache: FaviconFailureCache(ttl: 0),
            imageRetriever: { _ in
                _ = await counter.record()
                throw StubbedRetrieverError.failed
            }
        )

        let _ = await loader.favicon(for: "retry-test.example.com")
        let countAfterFirstAttempt = await counter.value()

        let _ = await loader.favicon(for: "retry-test.example.com")
        let countAfterSecondAttempt = await counter.value()

        XCTAssertEqual(countAfterFirstAttempt, 1)
        XCTAssertEqual(countAfterSecondAttempt, 2)
    }

    func testCancellationDoesNotPoisonFailureCache() async {
        let counter = DownloadCounter()

        let loader = FaviconLoader(
            failureCache: FaviconFailureCache(ttl: 3600),
            imageRetriever: { _ in
                let attempt = await counter.record()
                if attempt == 1 {
                    throw CancellationError()
                }
                return Self.sampleImage()
            }
        )

        let cancelledResult = await loader.favicon(for: "cancel-test.example.com")
        XCTAssertNil(cancelledResult)

        let successfulResult = await loader.favicon(for: "cancel-test.example.com")
        XCTAssertNotNil(successfulResult)
        let downloadCount = await counter.value()
        XCTAssertEqual(downloadCount, 2)
    }

    func testKingfisherPipelineFallsBackAndCachesSuccessfulResult() async {
        let loader = makeKingfisherBackedLoader()
        guard let resolved = FaviconSourceResolver.sources(for: "api.example.com") else {
            XCTFail("Expected resolved sources")
            return
        }

        let allSources = [resolved.primary] + resolved.alternatives
        let expectedURLs = Array(allSources.prefix(3)).compactMap { $0.url?.absoluteString }
        XCTAssertEqual(expectedURLs.count, 3)

        MockURLProtocol.setStub(.init(statusCode: 404, mimeType: nil, data: Data()), for: allSources[0].url!)
        MockURLProtocol.setStub(
            .init(statusCode: 200, mimeType: "text/html", data: Data("<html>not-an-image</html>".utf8)),
            for: allSources[1].url!
        )
        MockURLProtocol.setStub(
            .init(statusCode: 200, mimeType: "image/png", data: Self.samplePNGData()),
            for: allSources[2].url!
        )

        let firstImage = await loader.favicon(for: "api.example.com")
        XCTAssertNotNil(firstImage)
        XCTAssertEqual(MockURLProtocol.recordedURLs, expectedURLs)

        let secondImage = await loader.favicon(for: "api.example.com")
        XCTAssertNotNil(secondImage)
        XCTAssertEqual(MockURLProtocol.recordedURLs, expectedURLs)
    }

    func testKingfisherPipelineExhaustsFallbacksThenFailureCacheShortCircuits() async {
        let loader = makeKingfisherBackedLoader(ttl: 3600)
        guard let resolved = FaviconSourceResolver.sources(for: "fail-pipeline.example.com") else {
            XCTFail("Expected resolved sources")
            return
        }

        let allSources = [resolved.primary] + resolved.alternatives
        for source in allSources {
            MockURLProtocol.setStub(
                .init(statusCode: 404, mimeType: nil, data: Data()),
                for: source.url!
            )
        }

        let firstResult = await loader.favicon(for: "fail-pipeline.example.com")
        XCTAssertNil(firstResult)
        XCTAssertEqual(MockURLProtocol.recordedURLs.count, allSources.count)

        let secondResult = await loader.favicon(for: "fail-pipeline.example.com")
        XCTAssertNil(secondResult)
        XCTAssertEqual(MockURLProtocol.recordedURLs.count, allSources.count)
    }

    private func makeKingfisherBackedLoader(ttl: TimeInterval = 3600) -> FaviconLoader {
        let cache = ImageCache(name: UUID().uuidString)
        let downloader = ImageDownloader(name: UUID().uuidString)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        downloader.sessionConfiguration = configuration
        downloader.downloadTimeout = FaviconSourceResolver.Configuration.requestTimeout

        addTeardownBlock {
            cache.clearMemoryCache()
            cache.clearDiskCache()
        }

        return FaviconLoader(
            failureCache: FaviconFailureCache(ttl: ttl),
            imageRetriever: { resolved in
                try await FaviconLoader.retrieveImageWithKingfisher(
                    resolved: resolved,
                    cache: cache,
                    downloader: downloader
                )
            }
        )
    }

    private static func sampleImage() -> NSImage {
        NSImage(size: NSSize(width: 1, height: 1))
    }

    private static func samplePNGData() -> Data {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmap.setColor(NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.8, alpha: 1), atX: 0, y: 0)
        return bitmap.representation(using: .png, properties: [:])!
    }
}
