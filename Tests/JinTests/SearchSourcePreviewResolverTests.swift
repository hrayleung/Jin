import XCTest
import Foundation
@testable import Jin

final class SearchSourcePreviewResolverTests: XCTestCase {
    func testCanonicalXStatusURLIfNeededNormalizesProfileStatusURL() {
        let url = URL(string: "https://twitter.com/Interior/status/463440424141459456?s=20")!

        XCTAssertEqual(
            SearchSourcePreviewResolver.canonicalXStatusURLIfNeeded(for: url)?.absoluteString,
            "https://x.com/Interior/status/463440424141459456"
        )
    }

    func testCanonicalXStatusURLIfNeededNormalizesIWebStatusURL() {
        let url = URL(string: "https://x.com/i/web/status/463440424141459456?t=abc")!

        XCTAssertEqual(
            SearchSourcePreviewResolver.canonicalXStatusURLIfNeeded(for: url)?.absoluteString,
            "https://x.com/i/web/status/463440424141459456"
        )
    }

    func testCanonicalXStatusURLIfNeededRejectsNonStatusPath() {
        let url = URL(string: "https://x.com/explore")!
        XCTAssertNil(SearchSourcePreviewResolver.canonicalXStatusURLIfNeeded(for: url))
    }

    func testExtractXPostPreviewFromOEmbedPayloadUsesTweetHTML() throws {
        let payload: [String: Any] = [
            "html": #"<blockquote class=\"twitter-tweet\"><p lang=\"en\" dir=\"ltr\">AI &amp; ML updates from <a href=\"https://x.com\">x.com</a></p>&mdash; Team (@team)</blockquote>"#
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        XCTAssertEqual(
            SearchSourcePreviewResolver.extractXPostPreview(fromOEmbedPayload: data),
            "AI & ML updates from x.com"
        )
    }

    func testExtractXPostPreviewFromOEmbedPayloadFallsBackToTitle() throws {
        let payload: [String: Any] = [
            "title": "  Embedded preview fallback title  "
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        XCTAssertEqual(
            SearchSourcePreviewResolver.extractXPostPreview(fromOEmbedPayload: data),
            "Embedded preview fallback title"
        )
    }

    func testResolvePreviewUsesPersistentCacheWithinTTL() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "search-source-preview-cache-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        let cacheURL = cacheDir.appendingPathComponent("cache.json")

        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: cacheDir)
        }

        let payloadURL = "https://example.com/article/1"
        let now = Date()
        let payload: [String: Any] = [
            "version": 1,
            "entries": [
                payloadURL: [
                    "previewText": "Cached preview from disk",
                    "fetchedAt": now.timeIntervalSince1970
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: cacheURL)

        let resolver = SearchSourcePreviewResolver(
            cacheFileURL: cacheURL,
            now: { now }
        )

        let preview = await resolver.resolvePreviewIfNeeded(rawURL: payloadURL)
        XCTAssertEqual(preview, "Cached preview from disk")
    }

    func testResolvePreviewRefetchesWhenDiskCacheExpired() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "search-source-preview-cache-tests-expired-\(UUID().uuidString)",
            isDirectory: true
        )
        let cacheURL = cacheDir.appendingPathComponent("cache.json")

        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: cacheDir)
        }

        let payloadURL = "https://example.com/article/2"
        let now = Date()
        let staleDate = now.addingTimeInterval(-8 * 24 * 60 * 60)
        let payload: [String: Any] = [
            "version": 1,
            "entries": [
                payloadURL: [
                    "previewText": "Stale cache should expire",
                    "fetchedAt": staleDate.timeIntervalSince1970
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: cacheURL)

        let htmlResponse = """
            <html>
              <head><meta property=\"og:description\" content=\"Fresh network preview\"></head>
            </html>
            """

        let (session, protocolType) = makeMockedURLSession()
        protocolType.requestHandler = { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            XCTAssertEqual(url.absoluteString, payloadURL)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/html"]
            )!
            return (response, htmlResponse.data(using: .utf8)!)
        }

        let resolver = SearchSourcePreviewResolver(
            cacheFileURL: cacheURL,
            session: session,
            now: { now }
        )

        let preview = await resolver.resolvePreviewIfNeeded(rawURL: payloadURL)
        XCTAssertEqual(preview, "Fresh network preview")
        protocolType.requestHandler = nil
    }

    func testResolvePreviewUsesUnixEpochWhenTimestampLooksLikeEpoch() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "search-source-preview-cache-tests-epoch-\(UUID().uuidString)",
            isDirectory: true
        )
        let cacheURL = cacheDir.appendingPathComponent("cache.json")

        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: cacheDir)
        }

        let payloadURL = "https://example.com/article/3"
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let payload: [String: Any] = [
            "version": 1,
            "entries": [
                payloadURL: [
                    "previewText": "Cache data should be stale",
                    "fetchedAt": 1_230_768_000
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: cacheURL)

        let htmlResponse = """
            <html>
              <head><meta property=\"og:description\" content=\"Fresh network preview\"></head>
            </html>
            """

        let (session, protocolType) = makeMockedURLSession()
        var didHitNetwork = false
        protocolType.requestHandler = { request in
            didHitNetwork = true
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            XCTAssertEqual(url.absoluteString, payloadURL)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/html"]
            )!
            return (response, htmlResponse.data(using: .utf8)!)
        }

        let resolver = SearchSourcePreviewResolver(
            cacheFileURL: cacheURL,
            session: session,
            now: { now }
        )

        let preview = await resolver.resolvePreviewIfNeeded(rawURL: payloadURL)
        XCTAssertTrue(didHitNetwork)
        XCTAssertEqual(preview, "Fresh network preview")
        protocolType.requestHandler = nil
    }

    func testResolvePreviewRefetchesWhenCacheVersionMismatch() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "search-source-preview-cache-tests-version-\(UUID().uuidString)",
            isDirectory: true
        )
        let cacheURL = cacheDir.appendingPathComponent("cache.json")

        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: cacheDir)
        }

        let payloadURL = "https://example.com/article/4"
        let now = Date()
        let payload: [String: Any] = [
            "version": 2,
            "entries": [
                payloadURL: [
                    "previewText": "Cached with unsupported version",
                    "fetchedAt": now.timeIntervalSince1970
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: cacheURL)

        let htmlResponse = """
            <html>
              <head><meta property=\"og:description\" content=\"Versioned cache bypass\"></head>
            </html>
            """

        let (session, protocolType) = makeMockedURLSession()
        var didHitNetwork = false
        protocolType.requestHandler = { request in
            didHitNetwork = true
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            XCTAssertEqual(url.absoluteString, payloadURL)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/html"]
            )!
            return (response, htmlResponse.data(using: .utf8)!)
        }

        let resolver = SearchSourcePreviewResolver(
            cacheFileURL: cacheURL,
            session: session,
            now: { now }
        )

        let preview = await resolver.resolvePreviewIfNeeded(rawURL: payloadURL)
        XCTAssertTrue(didHitNetwork)
        XCTAssertEqual(preview, "Versioned cache bypass")
        protocolType.requestHandler = nil
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeMockedURLSession() -> (URLSession, MockURLProtocol.Type) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return (URLSession(configuration: config), MockURLProtocol.self)
}
