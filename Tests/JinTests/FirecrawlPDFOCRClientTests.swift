import Foundation
import XCTest
@testable import Jin

final class FirecrawlPDFOCRClientTests: XCTestCase {
    override func tearDown() {
        FirecrawlMockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testFirecrawlScrapePDFBuildsExpectedRequest() async throws {
        let (configuration, protocolType) = makeFirecrawlMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let client = FirecrawlPDFOCRClient(
            apiKey: "test-key",
            networkManager: networkManager
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.firecrawl.dev/v2/scrape")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["url"] as? String, "https://files.example.com/doc.pdf")
            XCTAssertEqual(json["formats"] as? [String], ["markdown"])
            XCTAssertEqual(json["storeInCache"] as? Bool, false)

            let parsers = try XCTUnwrap(json["parsers"] as? [[String: Any]])
            XCTAssertEqual(parsers.count, 1)
            XCTAssertEqual(parsers[0]["type"] as? String, "pdf")
            XCTAssertEqual(parsers[0]["mode"] as? String, "ocr")

            let response: [String: Any] = [
                "success": true,
                "data": [
                    "markdown": "# Parsed"
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let markdown = try await client.scrapePDF(
            at: URL(string: "https://files.example.com/doc.pdf")!,
            mode: .ocr
        )

        XCTAssertEqual(markdown, "# Parsed")
    }

    func testFirecrawlScrapePDFPropagatesSelectedParserMode() async throws {
        let (configuration, protocolType) = makeFirecrawlMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let client = FirecrawlPDFOCRClient(
            apiKey: "test-key",
            networkManager: networkManager
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let parsers = try XCTUnwrap(json["parsers"] as? [[String: Any]])
            XCTAssertEqual(parsers[0]["mode"] as? String, "fast")

            let response: [String: Any] = [
                "success": true,
                "data": [
                    "markdown": "ok"
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        _ = try await client.scrapePDF(
            at: URL(string: "https://files.example.com/doc.pdf")!,
            mode: .fast
        )
    }

    func testFirecrawlScrapePDFThrowsWhenMarkdownMissing() async throws {
        let (configuration, protocolType) = makeFirecrawlMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let client = FirecrawlPDFOCRClient(
            apiKey: "test-key",
            networkManager: networkManager
        )

        protocolType.requestHandler = { request in
            let response: [String: Any] = [
                "success": true,
                "data": [:]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        do {
            _ = try await client.scrapePDF(
                at: URL(string: "https://files.example.com/doc.pdf")!,
                mode: .auto
            )
            XCTFail("Expected Firecrawl scrape to fail when markdown is missing")
        } catch let LLMError.decodingError(message) {
            XCTAssertTrue(message.contains("did not contain markdown"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPreparedContentForPDFFirecrawlRequiresAPIKey() async throws {
        let attachment = try makeDraftAttachment()
        defer { try? FileManager.default.removeItem(at: attachment.fileURL) }

        do {
            _ = try await ChatMessagePreparationSupport.preparedContentForPDF(
                attachment,
                profile: makeFirecrawlProfile(parserMode: .ocr),
                requestedMode: .firecrawlOCR,
                totalPDFCount: 1,
                pdfOrdinal: 1,
                mistralClient: nil,
                mineruClient: nil,
                deepSeekClient: nil,
                openRouterClient: nil,
                firecrawlClient: nil,
                r2Uploader: nil,
                onStatusUpdate: { _ in }
            )
            XCTFail("Expected Firecrawl OCR to require an API key")
        } catch let error as PDFProcessingError {
            XCTAssertEqual(error.localizedDescription, PDFProcessingError.firecrawlAPIKeyMissing.localizedDescription)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPreparedContentForPDFFirecrawlFailsWithoutR2Configuration() async throws {
        let attachment = try makeDraftAttachment()
        defer { try? FileManager.default.removeItem(at: attachment.fileURL) }

        let defaults = makeIsolatedUserDefaults().defaults
        let uploader = CloudflareR2Uploader(defaults: defaults)
        let firecrawlClient = FirecrawlPDFOCRClient(apiKey: "test-key")

        do {
            _ = try await ChatMessagePreparationSupport.preparedContentForPDF(
                attachment,
                profile: makeFirecrawlProfile(parserMode: .ocr),
                requestedMode: .firecrawlOCR,
                totalPDFCount: 1,
                pdfOrdinal: 1,
                mistralClient: nil,
                mineruClient: nil,
                deepSeekClient: nil,
                openRouterClient: nil,
                firecrawlClient: firecrawlClient,
                r2Uploader: uploader,
                onStatusUpdate: { _ in }
            )
            XCTFail("Expected missing R2 configuration to fail")
        } catch let error as CloudflareR2UploaderError {
            XCTAssertTrue(error.localizedDescription.contains("Missing Cloudflare R2 settings"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPreparedContentForPDFFirecrawlUploadsLocalPDFAndFormatsOutput() async throws {
        let (configuration, protocolType) = makeFirecrawlMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        seedCloudflareR2Defaults(defaults)

        let uploader = CloudflareR2Uploader(networkManager: networkManager, defaults: defaults)
        let firecrawlClient = FirecrawlPDFOCRClient(apiKey: "test-key", networkManager: networkManager)
        let attachment = try makeDraftAttachment()
        defer { try? FileManager.default.removeItem(at: attachment.fileURL) }

        var sawUpload = false
        var sawValidation = false
        var sawFirecrawl = false
        let deleteExpectation = expectation(description: "Deletes uploaded PDF from R2")

        protocolType.requestHandler = { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            switch (url.host, request.httpMethod) {
            case ("test-account.r2.cloudflarestorage.com", "PUT"):
                sawUpload = true
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/pdf")
                XCTAssertEqual(requestBodyData(request), Data("PDF".utf8))
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data()
                )

            case ("pub.example.com", "GET"):
                sawValidation = true
                XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-0")
                return (
                    HTTPURLResponse(
                        url: url,
                        statusCode: 206,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/pdf"]
                    )!,
                    Data("%PDF".utf8)
                )

            case ("test-account.r2.cloudflarestorage.com", "DELETE"):
                sawUpload = true
                deleteExpectation.fulfill()
                return (
                    HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil)!,
                    Data()
                )

            case ("api.firecrawl.dev", "POST"):
                sawFirecrawl = true
                let body = try XCTUnwrap(requestBodyData(request))
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                let parsers = try XCTUnwrap(json["parsers"] as? [[String: Any]])
                XCTAssertEqual(parsers[0]["mode"] as? String, "auto")

                let markdown = String(repeating: "A", count: AttachmentConstants.maxPDFExtractedCharacters + 128)
                let response: [String: Any] = [
                    "success": true,
                    "data": [
                        "markdown": markdown
                    ]
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data
                )

            default:
                XCTFail("Unexpected request: \(url.absoluteString)")
                let data = try JSONSerialization.data(withJSONObject: [:])
                return (
                    HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                    data
                )
            }
        }

        let prepared = try await ChatMessagePreparationSupport.preparedContentForPDF(
            attachment,
            profile: makeFirecrawlProfile(parserMode: .auto),
            requestedMode: .firecrawlOCR,
            totalPDFCount: 1,
            pdfOrdinal: 1,
            mistralClient: nil,
            mineruClient: nil,
            deepSeekClient: nil,
            openRouterClient: nil,
            firecrawlClient: firecrawlClient,
            r2Uploader: uploader,
            onStatusUpdate: { _ in }
        )

        XCTAssertTrue(sawUpload)
        XCTAssertTrue(sawValidation)
        XCTAssertTrue(sawFirecrawl)
        XCTAssertTrue(prepared.additionalParts.isEmpty)
        XCTAssertTrue(prepared.extractedText?.hasPrefix("Firecrawl OCR (Auto Markdown): a.pdf") == true)
        XCTAssertTrue(prepared.extractedText?.hasSuffix("[Truncated]") == true)
        await fulfillment(of: [deleteExpectation], timeout: 1.0)
    }

    func testResolveExtensionCredentialStatusRequiresFirecrawlKeyAndValidR2Config() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppPreferences.setPluginEnabled(true, for: "firecrawl_ocr", defaults: defaults)
        defaults.set("test-key", forKey: AppPreferenceKeys.pluginWebSearchFirecrawlAPIKey)

        var status = ChatConversationStateSupport.resolveExtensionCredentialStatus(defaults: defaults)
        XCTAssertFalse(status.firecrawlOCRConfigured)
        XCTAssertTrue(status.firecrawlOCRPluginEnabled)

        seedCloudflareR2Defaults(defaults)
        status = ChatConversationStateSupport.resolveExtensionCredentialStatus(defaults: defaults)
        XCTAssertTrue(status.firecrawlOCRConfigured)

        AppPreferences.setPluginEnabled(false, for: "firecrawl_ocr", defaults: defaults)
        status = ChatConversationStateSupport.resolveExtensionCredentialStatus(defaults: defaults)
        XCTAssertFalse(status.firecrawlOCRPluginEnabled)
        XCTAssertTrue(status.firecrawlOCRConfigured)
    }
}

private final class FirecrawlMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
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

private func makeFirecrawlMockedSessionConfiguration() -> (URLSessionConfiguration, FirecrawlMockURLProtocol.Type) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FirecrawlMockURLProtocol.self]
    return (configuration, FirecrawlMockURLProtocol.self)
}

private func requestBodyData(_ request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else { return nil }

    stream.open()
    defer { stream.close() }

    let chunkSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
    defer { buffer.deallocate() }

    var data = Data()
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: chunkSize)
        if read < 0 {
            return nil
        }
        if read == 0 {
            break
        }
        data.append(buffer, count: read)
    }
    return data
}

private func makeDraftAttachment() throws -> DraftAttachment {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("jin-firecrawl-\(UUID().uuidString).pdf")
    try Data("PDF".utf8).write(to: url, options: .atomic)
    return DraftAttachment(
        id: UUID(),
        filename: "a.pdf",
        mimeType: "application/pdf",
        fileURL: url,
        extractedText: nil
    )
}

private func makeFirecrawlProfile(parserMode: FirecrawlPDFParserMode) -> ChatMessagePreparationSupport.MessagePreparationProfile {
    ChatMessagePreparationSupport.MessagePreparationProfile(
        threadID: UUID(),
        modelName: "Test Model",
        supportsVideoGenerationControl: false,
        supportsVideoInput: false,
        supportsMediaGenerationControl: false,
        supportsNativePDF: false,
        supportsVision: false,
        pdfProcessingMode: .firecrawlOCR,
        firecrawlPDFParserMode: parserMode
    )
}

private func makeIsolatedUserDefaults() -> (defaults: UserDefaults, suiteName: String) {
    let suiteName = "jin.tests.firecrawl.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}

private func seedCloudflareR2Defaults(_ defaults: UserDefaults) {
    defaults.set("test-account", forKey: AppPreferenceKeys.cloudflareR2AccountID)
    defaults.set("test-access-key", forKey: AppPreferenceKeys.cloudflareR2AccessKeyID)
    defaults.set("test-secret-key", forKey: AppPreferenceKeys.cloudflareR2SecretAccessKey)
    defaults.set("test-bucket", forKey: AppPreferenceKeys.cloudflareR2Bucket)
    defaults.set("https://pub.example.com", forKey: AppPreferenceKeys.cloudflareR2PublicBaseURL)
    defaults.set("jin-tests", forKey: AppPreferenceKeys.cloudflareR2KeyPrefix)
}
