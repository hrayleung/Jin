import XCTest
import Foundation
import Alamofire
@testable import Jin

final class NetworkManagerTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.stopLoadingHandler = nil
        super.tearDown()
    }

    func testDefaultSessionConfigurationUsesLongRunningTimeouts() {
        let configuration = NetworkManager.makeDefaultSessionConfiguration()

        XCTAssertEqual(
            configuration.timeoutIntervalForRequest,
            NetworkManager.defaultRequestTimeoutInterval
        )
        XCTAssertEqual(
            configuration.timeoutIntervalForResource,
            NetworkManager.defaultResourceTimeoutInterval
        )
        XCTAssertGreaterThan(
            configuration.timeoutIntervalForRequest,
            URLSession.shared.configuration.timeoutIntervalForRequest
        )
    }

    func testSendRequestUsesMockedConfiguration() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        protocolType.requestHandler = { urlProtocol in
            let request = urlProtocol.request
            let client = try XCTUnwrap(urlProtocol.client)
            let response = try Self.makeResponse(url: request.url!, statusCode: 200)

            client.urlProtocol(urlProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(urlProtocol, didLoad: Data("ok".utf8))
            client.urlProtocolDidFinishLoading(urlProtocol)
        }

        let networkManager = NetworkManager(configuration: configuration)
        let (data, response) = try await networkManager.sendRequest(Self.makeRequest(path: "/data"))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "ok")
    }

    func testSendRequestThrowsNetworkErrorWhenTransferFailsAfterHeaders() async {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        protocolType.requestHandler = { urlProtocol in
            let request = urlProtocol.request
            let client = try XCTUnwrap(urlProtocol.client)
            let response = try Self.makeResponse(url: request.url!, statusCode: 200)

            client.urlProtocol(urlProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(urlProtocol, didLoad: Data("partial".utf8))
            client.urlProtocol(urlProtocol, didFailWithError: URLError(.networkConnectionLost))
        }

        let networkManager = NetworkManager(configuration: configuration)

        do {
            _ = try await networkManager.sendRequest(Self.makeRequest(path: "/partial"))
            XCTFail("Expected sendRequest to throw when the transfer fails after headers arrive")
        } catch let LLMError.networkError(underlying) {
            XCTAssertEqual((underlying as? URLError)?.code, .networkConnectionLost)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSendRawRequestThrowsCancellationWhenTransferIsCancelledAfterHeaders() async {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        protocolType.requestHandler = { urlProtocol in
            let request = urlProtocol.request
            let client = try XCTUnwrap(urlProtocol.client)
            let response = try Self.makeResponse(url: request.url!, statusCode: 202)

            client.urlProtocol(urlProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(urlProtocol, didLoad: Data("partial".utf8))
            client.urlProtocol(urlProtocol, didFailWithError: URLError(.cancelled))
        }

        let networkManager = NetworkManager(configuration: configuration)

        do {
            _ = try await networkManager.sendRawRequest(Self.makeRequest(path: "/cancelled"))
            XCTFail("Expected sendRawRequest to throw CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSendRawRequestReturnsHTTPErrorResponsesWithoutThrowing() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        protocolType.requestHandler = { urlProtocol in
            let request = urlProtocol.request
            let client = try XCTUnwrap(urlProtocol.client)
            let response = try Self.makeResponse(url: request.url!, statusCode: 503)

            client.urlProtocol(urlProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(urlProtocol, didLoad: Data("{\"status\":\"pending\"}".utf8))
            client.urlProtocolDidFinishLoading(urlProtocol)
        }

        let networkManager = NetworkManager(configuration: configuration)
        let (data, response) = try await networkManager.sendRawRequest(Self.makeRequest(path: "/poll"))

        XCTAssertEqual(response.statusCode, 503)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{\"status\":\"pending\"}")
    }

    func testSendRequestUploadsHTTPBodyData() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        protocolType.requestHandler = { urlProtocol in
            let request = urlProtocol.request
            let client = try XCTUnwrap(urlProtocol.client)

            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(requestBodyData(request), Data("payload".utf8))

            let response = try Self.makeResponse(url: request.url!, statusCode: 200)
            client.urlProtocol(urlProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(urlProtocol, didLoad: Data("uploaded".utf8))
            client.urlProtocolDidFinishLoading(urlProtocol)
        }

        let networkManager = NetworkManager(configuration: configuration)
        var request = Self.makeRequest(path: "/upload")
        request.httpMethod = "POST"
        request.httpBody = Data("payload".utf8)

        let (data, response) = try await networkManager.sendRequest(request)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "uploaded")
    }

    func testStreamRequestParsesChunkedResponseData() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        protocolType.requestHandler = { urlProtocol in
            let request = urlProtocol.request
            let client = try XCTUnwrap(urlProtocol.client)
            let response = try Self.makeResponse(url: request.url!, statusCode: 200)

            client.urlProtocol(urlProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(urlProtocol, didLoad: Data("first\nse".utf8))
            client.urlProtocol(urlProtocol, didLoad: Data("cond\n".utf8))
            client.urlProtocolDidFinishLoading(urlProtocol)
        }

        let networkManager = NetworkManager(configuration: configuration)
        let stream = await networkManager.streamRequest(Self.makeRequest(path: "/stream"), parser: NewlineParser())

        var lines: [String] = []
        for try await line in stream {
            lines.append(line)
        }

        XCTAssertEqual(lines, ["first", "second"])
    }

    func testStreamRequestThrowsHTTPErrorWithoutYieldingParsedEvents() async {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        protocolType.requestHandler = { urlProtocol in
            let request = urlProtocol.request
            let client = try XCTUnwrap(urlProtocol.client)
            let response = try Self.makeResponse(url: request.url!, statusCode: 401)

            client.urlProtocol(urlProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(urlProtocol, didLoad: Data("ignored\n".utf8))
            client.urlProtocolDidFinishLoading(urlProtocol)
        }

        let networkManager = NetworkManager(configuration: configuration)
        let stream = await networkManager.streamRequest(Self.makeRequest(path: "/error-stream"), parser: NewlineParser())

        var lines: [String] = []

        do {
            for try await line in stream {
                lines.append(line)
            }
            XCTFail("Expected authentication failure")
        } catch let LLMError.authenticationFailed(message) {
            XCTAssertEqual(lines, [])
            XCTAssertEqual(message, "ignored")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSessionInterceptorAppliesToDataAndStreamRequests() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let interceptor = Adapter { request, _, completion in
            var adaptedRequest = request
            adaptedRequest.setValue("applied", forHTTPHeaderField: "X-Test-Interceptor")
            completion(.success(adaptedRequest))
        }
        protocolType.requestHandler = { urlProtocol in
            let request = urlProtocol.request
            let client = try XCTUnwrap(urlProtocol.client)

            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test-Interceptor"), "applied")

            let response = try Self.makeResponse(url: request.url!, statusCode: 200)
            client.urlProtocol(urlProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)

            switch request.url?.path {
            case "/data":
                client.urlProtocol(urlProtocol, didLoad: Data("ok".utf8))
            case "/stream":
                client.urlProtocol(urlProtocol, didLoad: Data("streamed\n".utf8))
            default:
                XCTFail("Unexpected URL path: \(request.url?.path ?? "nil")")
            }

            client.urlProtocolDidFinishLoading(urlProtocol)
        }

        let networkManager = NetworkManager(configuration: configuration, interceptor: interceptor)
        let (data, response) = try await networkManager.sendRequest(Self.makeRequest(path: "/data"))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "ok")

        let stream = await networkManager.streamRequest(Self.makeRequest(path: "/stream"), parser: NewlineParser())
        var events: [String] = []

        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events, ["streamed"])
    }

    func testSendRequestSurfacesRequestAdaptationFailureAsNetworkError() async {
        let (configuration, _) = makeMockedSessionConfiguration()
        let interceptor = Adapter { _, _, completion in
            completion(.failure(NetworkManagerTestError.adaptationFailed))
        }
        let networkManager = NetworkManager(configuration: configuration, interceptor: interceptor)

        do {
            _ = try await networkManager.sendRequest(Self.makeRequest(path: "/adapt"))
            XCTFail("Expected sendRequest to surface request adaptation failure")
        } catch let LLMError.networkError(underlying) {
            XCTAssertEqual(underlying as? NetworkManagerTestError, .adaptationFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static func makeRequest(path: String) -> URLRequest {
        URLRequest(url: URL(string: "https://example.com\(path)")!)
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

private struct NewlineParser: StreamParser {
    private var buffer = Data()
    private var pendingEvents: [String] = []

    mutating func append(_ byte: UInt8) {
        if byte == UInt8(ascii: "\n") {
            guard !buffer.isEmpty else { return }
            pendingEvents.append(String(decoding: buffer, as: UTF8.self))
            buffer.removeAll(keepingCapacity: true)
            return
        }

        buffer.append(byte)
    }

    mutating func nextEvent() -> String? {
        guard !pendingEvents.isEmpty else { return nil }
        return pendingEvents.removeFirst()
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((MockURLProtocol) throws -> Void)?
    static var stopLoadingHandler: (() -> Void)?

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

    override func stopLoading() {
        Self.stopLoadingHandler?()
    }
}

private func makeMockedSessionConfiguration() -> (URLSessionConfiguration, MockURLProtocol.Type) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return (configuration, MockURLProtocol.self)
}

private func requestBodyData(_ request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else { return nil }

    stream.open()
    defer { stream.close() }

    let chunkSize = 1_024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
    defer { buffer.deallocate() }

    var data = Data()
    while stream.hasBytesAvailable {
        let readCount = stream.read(buffer, maxLength: chunkSize)
        guard readCount > 0 else { break }
        data.append(buffer, count: readCount)
    }

    return data
}

private enum NetworkManagerTestError: Error, Equatable {
    case adaptationFailed
}
