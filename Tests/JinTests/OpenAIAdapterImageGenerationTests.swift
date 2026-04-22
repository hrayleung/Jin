import Foundation
import XCTest
@testable import Jin

final class OpenAIAdapterImageGenerationTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        MockURLProtocol.requestHandler = nil
    }

    func testOpenAIImage2ModelIDsRouteToImagesGenerationsEndpoint() async throws {
        let modelIDs = [
            "gpt-image-2",
            "gpt-image-2-2026-04-21",
        ]

        for modelID in modelIDs {
            let (configuration, protocolType) = makeMockedSessionConfiguration()
            let networkManager = NetworkManager(configuration: configuration)

            let providerConfig = ProviderConfig(
                id: "openai",
                name: "OpenAI",
                type: .openai,
                apiKey: "ignored",
                baseURL: "https://example.com"
            )

            let expected = Data("PNG".utf8)

            protocolType.requestHandler = { request in
                XCTAssertEqual(request.url?.absoluteString, "https://example.com/images/generations")
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

                let body = try XCTUnwrap(requestBodyData(request))
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                let root = try XCTUnwrap(json)

                XCTAssertEqual(root["model"] as? String, modelID)
                XCTAssertEqual(root["prompt"] as? String, "Draw a poster")
                XCTAssertEqual(root["size"] as? String, "2048x2048")
                XCTAssertEqual(root["quality"] as? String, "medium")
                XCTAssertNil(root["images"])

                let response: [String: Any] = [
                    "data": [
                        ["b64_json": expected.base64EncodedString()]
                    ]
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data
                )
            }

            let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
            let stream = try await adapter.sendMessage(
                messages: [Message(role: .user, content: [.text("Draw a poster")])],
                modelID: modelID,
                controls: GenerationControls(
                    openaiImageGeneration: OpenAIImageGenerationControls(
                        size: .size2048x2048,
                        quality: .medium
                    )
                ),
                tools: [],
                streaming: false
            )

            var imageData: Data?
            for try await event in stream {
                if case .contentDelta(.image(let image)) = event {
                    imageData = image.data
                }
            }

            XCTAssertEqual(imageData, expected)
        }
    }

    func testOpenAIImage2EditUsesMultipartEditsEndpointWithLocalImageData() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "openai",
            name: "OpenAI",
            type: .openai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        let expected = Data("WEBP".utf8)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/images/edits")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)

            let body = String(decoding: try XCTUnwrap(requestBodyData(request)), as: UTF8.self)
            XCTAssertTrue(body.contains("name=\"model\""))
            XCTAssertTrue(body.contains("gpt-image-2"))
            XCTAssertTrue(body.contains("name=\"prompt\""))
            XCTAssertTrue(body.contains("Make this cinematic"))
            XCTAssertTrue(body.contains("name=\"size\""))
            XCTAssertTrue(body.contains("2048x1152"))
            XCTAssertTrue(body.contains("name=\"quality\""))
            XCTAssertTrue(body.contains("high"))
            XCTAssertTrue(body.contains("name=\"background\""))
            XCTAssertTrue(body.contains("opaque"))
            XCTAssertTrue(body.contains("name=\"output_format\""))
            XCTAssertTrue(body.contains("webp"))
            XCTAssertTrue(body.contains("name=\"output_compression\""))
            XCTAssertTrue(body.contains("50"))
            XCTAssertTrue(body.contains("name=\"moderation\""))
            XCTAssertTrue(body.contains("low"))
            XCTAssertTrue(body.contains("name=\"image[]\""))
            XCTAssertTrue(body.contains("LOCALPNG"))
            XCTAssertFalse(body.contains("input_fidelity"))

            let response: [String: Any] = [
                "data": [
                    ["b64_json": expected.base64EncodedString()]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [
                    .text("Make this cinematic"),
                    .image(ImageContent(mimeType: "image/png", data: Data("LOCALPNG".utf8), url: nil))
                ])
            ],
            modelID: "gpt-image-2",
            controls: GenerationControls(
                openaiImageGeneration: OpenAIImageGenerationControls(
                    size: OpenAIImageSize(rawValue: "2048x1152"),
                    quality: .high,
                    background: .opaque,
                    outputFormat: .webp,
                    outputCompression: 50,
                    moderation: .low
                )
            ),
            tools: [],
            streaming: false
        )

        var imageData: Data?
        for try await event in stream {
            if case .contentDelta(.image(let image)) = event {
                imageData = image.data
            }
        }

        XCTAssertEqual(imageData, expected)
    }

    func testOpenAIImage2EditDownloadsRemoteInputImageBeforeMultipartUpload() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "openai",
            name: "OpenAI",
            type: .openai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        let remoteURL = URL(string: "https://cdn.example.com/source.png")!
        let expected = Data("PNG".utf8)

        protocolType.requestHandler = { request in
            let url = try XCTUnwrap(request.url?.absoluteString)

            switch url {
            case "https://cdn.example.com/source.png":
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("REMOTEPNG".utf8)
                )
            case "https://example.com/images/edits":
                XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
                let body = String(decoding: try XCTUnwrap(requestBodyData(request)), as: UTF8.self)
                XCTAssertTrue(body.contains("REMOTEPNG"))
                XCTAssertTrue(body.contains("source.png"))

                let response: [String: Any] = [
                    "data": [
                        ["b64_json": expected.base64EncodedString()]
                    ]
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data
                )
            default:
                XCTFail("Unexpected URL: \(url)")
                throw URLError(.badURL)
            }
        }

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [
                    .text("Restyle this"),
                    .image(ImageContent(mimeType: "image/png", data: nil, url: remoteURL))
                ])
            ],
            modelID: "gpt-image-2-2026-04-21",
            controls: GenerationControls(
                openaiImageGeneration: OpenAIImageGenerationControls(
                    quality: .medium
                )
            ),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenAILegacyImageEditStillUsesJSONRequest() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "openai",
            name: "OpenAI",
            type: .openai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        let expected = Data("PNG".utf8)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/images/edits")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "gpt-image-1")
            XCTAssertEqual(root["prompt"] as? String, "Preserve the face")
            XCTAssertEqual(root["input_fidelity"] as? String, "high")
            XCTAssertEqual(root["background"] as? String, "transparent")
            XCTAssertEqual(root["output_format"] as? String, "png")
            let images = try XCTUnwrap(root["images"] as? [[String: Any]])
            let first = try XCTUnwrap(images.first)
            let imageURL = try XCTUnwrap(first["image_url"] as? String)
            XCTAssertTrue(imageURL.contains(Data("LEGACYPNG".utf8).base64EncodedString()))

            let response: [String: Any] = [
                "data": [
                    ["b64_json": expected.base64EncodedString()]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [
                    .text("Preserve the face"),
                    .image(ImageContent(mimeType: "image/png", data: Data("LEGACYPNG".utf8), url: nil))
                ])
            ],
            modelID: "gpt-image-1",
            controls: GenerationControls(
                openaiImageGeneration: OpenAIImageGenerationControls(
                    background: .transparent,
                    outputFormat: .png,
                    inputFidelity: .high
                )
            ),
            tools: [],
            streaming: false
        )

        var imageData: Data?
        for try await event in stream {
            if case .contentDelta(.image(let image)) = event {
                imageData = image.data
            }
        }

        XCTAssertEqual(imageData, expected)
    }
}

// MARK: - URLProtocol stubbing

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

private func makeMockedSessionConfiguration() -> (URLSessionConfiguration, MockURLProtocol.Type) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return (config, MockURLProtocol.self)
}

private func requestBodyData(_ request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }

    let bufferSize = 16 * 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    var data = Data()
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: bufferSize)
        if read > 0 {
            data.append(buffer, count: read)
        } else {
            break
        }
    }
    return data
}
