import XCTest
import Foundation
@testable import Jin

final class SearchRedirectURLResolverTests: XCTestCase {
    func testResolveRedirectFromQueryParametersWithoutNetwork() async {
        let rawURL = "https://vertexaisearch.cloud.google.com/search?q=test&url=https%3A%2F%2Fexample.com%2Ffinal"
        let expected = "https://example.com/final"

        let (session, protocolType) = makeMockedDataProvider()
        protocolType.requestHandler = { _ in
            XCTFail("Query redirect should be resolved locally without network")
            throw URLError(.badURL)
        }
        defer { protocolType.requestHandler = nil }

        let resolver = SearchRedirectURLResolver(dataProvider: session)
        let resolved = await resolver.resolveIfNeeded(rawURL: rawURL)

        XCTAssertEqual(resolved, expected)
    }

    func testResolveRedirectUsesCachedResolvedURLAcrossInit() async throws {
        let cache = try makeTemporaryCacheURL(prefix: "search-redirect-cache-tests")
        defer { try? FileManager.default.removeItem(at: cache.directory) }

        let now = Date()
        let rawURL = "https://vertexaisearch.cloud.google.com/search?q=cache"
        let resolvedURL = "https://example.com/cached-final"

        try writeCachePayload(
            to: cache.fileURL,
            rawURL: rawURL,
            resolvedURL: resolvedURL,
            resolvedAt: now.timeIntervalSince1970
        )

        let (session, protocolType) = makeMockedDataProvider()
        protocolType.requestHandler = { _ in
            XCTFail("Cached redirect should be used without issuing network request")
            throw URLError(.badURL)
        }
        defer { protocolType.requestHandler = nil }

        let resolver = SearchRedirectURLResolver(
            cacheFileURL: cache.fileURL,
            dataProvider: session,
            now: { now }
        )

        let resolved = await resolver.resolveIfNeeded(rawURL: rawURL)
        XCTAssertEqual(resolved, resolvedURL)
    }

    func testResolveRedirectUsesCachedMissAcrossInit() async throws {
        let cache = try makeTemporaryCacheURL(prefix: "search-redirect-cache-miss-tests")
        defer { try? FileManager.default.removeItem(at: cache.directory) }

        let now = Date()
        let rawURL = "https://vertexaisearch.cloud.google.com/search?q=missing"

        try writeCachePayload(
            to: cache.fileURL,
            rawURL: rawURL,
            resolvedURL: nil,
            resolvedAt: now.timeIntervalSince1970
        )

        let (session, protocolType) = makeMockedDataProvider()
        protocolType.requestHandler = { _ in
            XCTFail("Cached redirect miss should be used without issuing network request")
            throw URLError(.badURL)
        }
        defer { protocolType.requestHandler = nil }

        let resolver = SearchRedirectURLResolver(
            cacheFileURL: cache.fileURL,
            dataProvider: session,
            now: { now }
        )

        let resolved = await resolver.resolveIfNeeded(rawURL: rawURL)
        XCTAssertNil(resolved)
    }

    func testResolveRedirectRequeriesWhenCacheExpired() async throws {
        let cache = try makeTemporaryCacheURL(prefix: "search-redirect-cache-tests-expired")
        defer { try? FileManager.default.removeItem(at: cache.directory) }

        let now = Date()
        let staleDate = now.addingTimeInterval(-8 * 24 * 60 * 60)
        let rawURL = "https://vertexaisearch.cloud.google.com/search?q=expired"
        let resolvedURL = "https://example.com/expired-final"
        try writeCachePayload(
            to: cache.fileURL,
            rawURL: rawURL,
            resolvedURL: resolvedURL,
            resolvedAt: staleDate.timeIntervalSince1970
        )

        let htmlResponse = ""
        let (session, protocolType) = makeMockedDataProvider()
        protocolType.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(htmlResponse.utf8))
        }
        defer { protocolType.requestHandler = nil }

        let resolver = SearchRedirectURLResolver(
            cacheFileURL: cache.fileURL,
            dataProvider: session,
            now: { now }
        )

        let resolved = await resolver.resolveIfNeeded(rawURL: rawURL)
        XCTAssertNil(resolved)
    }

    func testResolveRedirectFallsBackToRangeGetWhenHeadDoesNotRedirect() async throws {
        let cache = try makeTemporaryCacheURL(prefix: "search-redirect-probe-tests")
        defer { try? FileManager.default.removeItem(at: cache.directory) }

        let rawURL = "https://vertexaisearch.cloud.google.com/search?q=fallback-\(UUID().uuidString)"
        let finalURL = try XCTUnwrap(URL(string: "https://example.com/range-final"))
        var observedRequests: [(method: String?, rangeHeader: String?)] = []

        let (session, protocolType) = makeMockedDataProvider()
        protocolType.requestHandler = { request in
            observedRequests.append((
                method: request.httpMethod,
                rangeHeader: request.value(forHTTPHeaderField: "Range")
            ))

            let responseURL = request.httpMethod?.uppercased() == "GET"
                ? finalURL
                : request.url!
            let response = HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        defer { protocolType.requestHandler = nil }

        let resolver = SearchRedirectURLResolver(
            cacheFileURL: cache.fileURL,
            dataProvider: session
        )

        let resolved = await resolver.resolveIfNeeded(rawURL: rawURL)

        XCTAssertEqual(resolved, finalURL.absoluteString)
        XCTAssertEqual(observedRequests.map { $0.method }, ["HEAD", "GET"])
        XCTAssertNil(observedRequests.first?.rangeHeader)
        XCTAssertEqual(observedRequests.last?.rangeHeader, "bytes=0-0")
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

private func makeMockedDataProvider() -> (HTTPDataProvider, MockURLProtocol.Type) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    let provider: HTTPDataProvider = { request in
        try await session.data(for: request)
    }
    return (provider, MockURLProtocol.self)
}

private func makeTemporaryCacheURL(prefix: String) throws -> (directory: URL, fileURL: URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "\(prefix)-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return (directory, directory.appendingPathComponent("cache.json"))
}

private func writeCachePayload(
    to fileURL: URL,
    rawURL: String,
    resolvedURL: String?,
    resolvedAt: TimeInterval
) throws {
    var entry: [String: Any] = [
        "resolvedAt": resolvedAt
    ]
    entry["resolvedURL"] = resolvedURL ?? NSNull()

    let payload: [String: Any] = [
        "version": 1,
        "entries": [
            rawURL: entry
        ]
    ]
    let data = try JSONSerialization.data(withJSONObject: payload)
    try data.write(to: fileURL)
}
