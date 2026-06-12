import Foundation
import XCTest
@testable import Jin

private final class AttachmentImportPipelineMockURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let headers: [String: String]
        let data: Data
    }

    private static let lock = NSLock()
    private static var stubs: [String: Stub] = [:]
    private static var requestCounts: [String: Int] = [:]

    static func setStub(_ stub: Stub, for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        stubs[url.absoluteString] = stub
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        stubs.removeAll()
        requestCounts.removeAll()
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

        let stub = Self.lock.withLock { Self.stubs[url.absoluteString] }
        Self.lock.withLock {
            Self.requestCounts[url.absoluteString, default: 0] += 1
        }

        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func requestCount(for url: URL) -> Int {
        lock.withLock { requestCounts[url.absoluteString, default: 0] }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

final class AttachmentImportPipelineMediaPersistenceTests: XCTestCase {
    override func tearDown() {
        AttachmentImportPipelineMockURLProtocol.reset()
        super.tearDown()
    }

    func testPersistImagesToDiskLeavesExternalReferenceRemoteImageUntouched() async {
        let remoteURL = URL(string: "https://example.com/reference.png")!
        let parts: [ContentPart] = [
            .image(ImageContent(
                mimeType: "image/png",
                data: nil,
                url: remoteURL,
                assetDisposition: .externalReference
            ))
        ]

        let persisted = await AttachmentImportPipeline.persistImagesToDisk(parts, dataProvider: makeDataProvider())

        guard case .image(let image) = persisted[0] else {
            return XCTFail("Expected image content")
        }
        XCTAssertEqual(image.assetDisposition, MediaAssetDisposition.externalReference)
        XCTAssertEqual(image.url, remoteURL)
    }

    func testPersistImagesToDiskLocalizesManagedRemoteImage() async throws {
        let remoteURL = URL(string: "https://example.com/generated.png")!
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        AttachmentImportPipelineMockURLProtocol.setStub(
            .init(statusCode: 200, headers: ["Content-Type": "image/png"], data: imageData),
            for: remoteURL
        )

        let parts: [ContentPart] = [
            .image(ImageContent(
                mimeType: "image/png",
                data: nil,
                url: remoteURL,
                assetDisposition: .managed
            ))
        ]

        let persisted = await AttachmentImportPipeline.persistImagesToDisk(parts, dataProvider: makeDataProvider())

        guard case .image(let image) = persisted[0] else {
            return XCTFail("Expected image content")
        }
        XCTAssertEqual(image.assetDisposition, MediaAssetDisposition.managed)
        XCTAssertNil(image.data)
        XCTAssertNotNil(image.url)
        XCTAssertEqual(image.url?.isFileURL, true)

        if let fileURL = image.url {
            let storedData = try Data(contentsOf: fileURL)
            XCTAssertEqual(storedData, imageData)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func testPersistImagesToDiskSkipsManagedRemoteImageWhenResponseIsNotAnImage() async {
        let remoteURL = URL(string: "https://example.com/not-an-image")!
        AttachmentImportPipelineMockURLProtocol.setStub(
            .init(statusCode: 200, headers: ["Content-Type": "text/html"], data: Data("<html></html>".utf8)),
            for: remoteURL
        )

        let original = ImageContent(
            mimeType: "image/png",
            data: nil,
            url: remoteURL,
            assetDisposition: .managed
        )
        let persisted = await AttachmentImportPipeline.persistImagesToDisk([.image(original)], dataProvider: makeDataProvider())

        guard case .image(let image) = persisted[0] else {
            return XCTFail("Expected image content")
        }
        XCTAssertEqual(image.url, remoteURL)
        XCTAssertEqual(image.assetDisposition, MediaAssetDisposition.managed)
    }

    func testPersistImagesToDiskSkipsManagedRemoteImageForLocalhostURLWithoutFetching() async {
        let remoteURL = URL(string: "http://127.0.0.1/generated.png")!
        AttachmentImportPipelineMockURLProtocol.setStub(
            .init(statusCode: 200, headers: ["Content-Type": "image/png"], data: Data([0x89, 0x50, 0x4E, 0x47])),
            for: remoteURL
        )

        let original = ImageContent(
            mimeType: "image/png",
            data: nil,
            url: remoteURL,
            assetDisposition: .managed
        )
        let persisted = await AttachmentImportPipeline.persistImagesToDisk([.image(original)], dataProvider: makeDataProvider())

        guard case .image(let image) = persisted[0] else {
            return XCTFail("Expected image content")
        }
        XCTAssertEqual(image.url, remoteURL)
        XCTAssertEqual(image.assetDisposition, MediaAssetDisposition.managed)
        XCTAssertEqual(AttachmentImportPipelineMockURLProtocol.requestCount(for: remoteURL), 0)
    }

    func testPersistImagesToDiskSkipsManagedRemoteImageWhenContentLengthExceedsLimit() async {
        let remoteURL = URL(string: "https://example.com/too-large.png")!
        AttachmentImportPipelineMockURLProtocol.setStub(
            .init(
                statusCode: 200,
                headers: [
                    "Content-Type": "image/png",
                    "Content-Length": "\(RemoteMediaURLPolicy.maximumAutomaticFetchBytes + 1)",
                ],
                data: Data([0x89, 0x50, 0x4E, 0x47])
            ),
            for: remoteURL
        )

        let original = ImageContent(
            mimeType: "image/png",
            data: nil,
            url: remoteURL,
            assetDisposition: .managed
        )
        let persisted = await AttachmentImportPipeline.persistImagesToDisk([.image(original)], dataProvider: makeDataProvider())

        guard case .image(let image) = persisted[0] else {
            return XCTFail("Expected image content")
        }
        XCTAssertEqual(image.url, remoteURL)
        XCTAssertEqual(image.assetDisposition, MediaAssetDisposition.managed)
    }

    func testRemoteMediaURLPolicyRejectsUnsafeAutomaticFetchTargets() {
        XCTAssertFalse(RemoteMediaURLPolicy.isAllowedForAutomaticFetch(URL(string: "file:///tmp/generated.png")!))
        XCTAssertFalse(RemoteMediaURLPolicy.isAllowedForAutomaticFetch(URL(string: "http://localhost/generated.png")!))
        XCTAssertFalse(RemoteMediaURLPolicy.isAllowedForAutomaticFetch(URL(string: "http://192.168.1.10/generated.png")!))
        XCTAssertFalse(RemoteMediaURLPolicy.isAllowedForAutomaticFetch(URL(string: "http://[::1]/generated.png")!))
        XCTAssertTrue(RemoteMediaURLPolicy.isAllowedForAutomaticFetch(URL(string: "https://example.com/generated.png")!))
    }

    private func makeDataProvider() -> HTTPDataProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AttachmentImportPipelineMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return { request in
            try await session.data(for: request)
        }
    }
}
