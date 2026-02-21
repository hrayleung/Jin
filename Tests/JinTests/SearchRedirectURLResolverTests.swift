import XCTest
import Foundation
@testable import Jin

final class SearchRedirectURLResolverTests: XCTestCase {
    func testResolveRedirectFromQueryParametersWithoutNetwork() async {
        let rawURL = "https://vertexaisearch.cloud.google.com/search?q=test&url=https%3A%2F%2Fexample.com%2Ffinal"
        let expected = "https://example.com/final"

        let (session, protocolType) = makeMockedURLSession()
        protocolType.requestHandler = { _ in
            XCTFail("Query redirect should be resolved locally without network")
            throw URLError(.badURL)
        }

        let resolver = SearchRedirectURLResolver(session: session)
        let resolved = await resolver.resolveIfNeeded(rawURL: rawURL)

        XCTAssertEqual(resolved, expected)
        protocolType.requestHandler = nil
    }

    func testResolveRedirectUsesCachedResolvedURLAcrossInit() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "search-redirect-cache-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        let cacheURL = cacheDir.appendingPathComponent("cache.json")

        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let now = Date()
        let rawURL = "https://vertexaisearch.cloud.google.com/search?q=cache"
        let resolvedURL = "https://example.com/cached-final"

        let payload: [String: Any] = [
            "version": 1,
            "entries": [
                rawURL: [
                    "resolvedURL": resolvedURL,
                    "resolvedAt": now.timeIntervalSince1970
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: cacheURL)

        let (session, protocolType) = makeMockedURLSession()
        protocolType.requestHandler = { _ in
            XCTFail("Cached redirect should be used without issuing network request")
            throw URLError(.badURL)
        }

        let resolver = SearchRedirectURLResolver(
            cacheFileURL: cacheURL,
            session: session,
            now: { now }
        )

        let resolved = await resolver.resolveIfNeeded(rawURL: rawURL)
        XCTAssertEqual(resolved, resolvedURL)

        protocolType.requestHandler = nil
    }

    func testResolveRedirectRequeriesWhenCacheExpired() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "search-redirect-cache-tests-expired-\(UUID().uuidString)",
            isDirectory: true
        )
        let cacheURL = cacheDir.appendingPathComponent("cache.json")

        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let now = Date()
        let staleDate = now.addingTimeInterval(-8 * 24 * 60 * 60)
        let rawURL = "https://vertexaisearch.cloud.google.com/search?q=expired"
        let resolvedURL = "https://example.com/expired-final"
        let payload: [String: Any] = [
            "version": 1,
            "entries": [
                rawURL: [
                    "resolvedURL": resolvedURL,
                    "resolvedAt": staleDate.timeIntervalSince1970
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: cacheURL)

        let htmlResponse = ""
        let (session, protocolType) = makeMockedURLSession()
        protocolType.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(htmlResponse.utf8))
        }

        let resolver = SearchRedirectURLResolver(
            cacheFileURL: cacheURL,
            session: session,
            now: { now }
        )

        let resolved = await resolver.resolveIfNeeded(rawURL: rawURL)
        XCTAssertNil(resolved)
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
