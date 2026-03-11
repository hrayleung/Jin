import XCTest
import Foundation
import Alamofire
@testable import Jin

final class NetworkDebugRequestExecutorTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testDefaultSessionConfigurationUsesShortLivedSystemTimeouts() {
        let configuration = NetworkDebugRequestExecutor.makeDefaultSessionConfiguration()

        XCTAssertEqual(
            configuration.timeoutIntervalForRequest,
            URLSession.shared.configuration.timeoutIntervalForRequest
        )
        XCTAssertEqual(
            configuration.timeoutIntervalForResource,
            URLSession.shared.configuration.timeoutIntervalForResource
        )
        XCTAssertLessThan(
            configuration.timeoutIntervalForRequest,
            NetworkManager.defaultRequestTimeoutInterval
        )
    }

    func testDataReturnsHTTPErrorResponsesWithoutThrowing() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let alamofireSession = makeAlamofireSession(configuration: configuration)

        protocolType.requestHandler = { urlProtocol in
            let request = urlProtocol.request
            let client = try XCTUnwrap(urlProtocol.client)
            let response = try Self.makeResponse(url: request.url!, statusCode: 404)

            client.urlProtocol(urlProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(urlProtocol, didLoad: Data("missing".utf8))
            client.urlProtocolDidFinishLoading(urlProtocol)
        }

        let request = URLRequest(url: URL(string: "https://example.com/missing")!)
        let (data, response) = try await NetworkDebugRequestExecutor.data(
            for: request,
            mode: "test",
            alamofireSession: alamofireSession
        )

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "missing")
    }

    func testDataThrowsTransportFailureAfterPartialResponse() async {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let alamofireSession = makeAlamofireSession(configuration: configuration)

        protocolType.requestHandler = { urlProtocol in
            let request = urlProtocol.request
            let client = try XCTUnwrap(urlProtocol.client)
            let response = try Self.makeResponse(url: request.url!, statusCode: 200)

            client.urlProtocol(urlProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(urlProtocol, didLoad: Data("partial".utf8))
            client.urlProtocol(urlProtocol, didFailWithError: URLError(.networkConnectionLost))
        }

        let request = URLRequest(url: URL(string: "https://example.com/partial")!)

        do {
            _ = try await NetworkDebugRequestExecutor.data(
                for: request,
                mode: "test",
                alamofireSession: alamofireSession
            )
            XCTFail("Expected transport failure")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost)
        }
    }

    private static func makeResponse(url: URL, statusCode: Int) throws -> HTTPURLResponse {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/plain"]
        ) else {
            throw URLError(.badServerResponse)
        }

        return response
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((MockURLProtocol) throws -> Void)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        do {
            try handler(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeMockedSessionConfiguration() -> (URLSessionConfiguration, MockURLProtocol.Type) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return (configuration, MockURLProtocol.self)
}

private func makeAlamofireSession(configuration: URLSessionConfiguration) -> Session {
    let rootQueue = DispatchQueue(label: "jin.tests.network-debug-executor.root")
    let requestQueue = DispatchQueue(label: "jin.tests.network-debug-executor.request", target: rootQueue)
    let serializationQueue = DispatchQueue(label: "jin.tests.network-debug-executor.serialization", target: rootQueue)

    return Session(
        configuration: configuration,
        rootQueue: rootQueue,
        requestSetup: .lazy,
        requestQueue: requestQueue,
        serializationQueue: serializationQueue
    )
}
