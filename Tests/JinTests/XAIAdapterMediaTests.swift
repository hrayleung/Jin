import Foundation
import XCTest
@testable import Jin

final class XAIAdapterMediaTests: XCTestCase {
    func testXAIImageGenerationBuildsRequestAndReturnsImageURL() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/images/generations")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "grok-imagine-image")
            XCTAssertEqual(root["prompt"] as? String, "A watercolor skyline")
            XCTAssertEqual(root["n"] as? Int, 2)
            XCTAssertEqual(root["aspect_ratio"] as? String, "1:1")
            XCTAssertEqual(root["response_format"] as? String, "url")
            XCTAssertEqual(root["user"] as? String, "tester")
            XCTAssertEqual(root["extra_flag"] as? Bool, true)

            let response: [String: Any] = [
                "id": "img_1",
                "data": [
                    [
                        "url": "https://cdn.example.com/generated.png",
                        "mime_type": "image/png"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.text("A watercolor skyline")])
            ],
            modelID: "grok-imagine-image",
            controls: GenerationControls(
                xaiImageGeneration: XAIImageGenerationControls(
                    count: 2,
                    aspectRatio: .ratio1x1,
                    responseFormat: .url,
                    user: "tester"
                ),
                providerSpecific: ["extra_flag": AnyCodable(true)]
            ),
            tools: [],
            streaming: true
        )

        var messageStarted = false
        var generatedImages: [ImageContent] = []

        for try await event in stream {
            switch event {
            case .messageStart(let id):
                messageStarted = true
                XCTAssertEqual(id, "img_1")
            case .contentDelta(.image(let image)):
                generatedImages.append(image)
            default:
                break
            }
        }

        XCTAssertTrue(messageStarted)
        XCTAssertEqual(generatedImages.count, 1)
        XCTAssertEqual(generatedImages[0].mimeType, "image/png")
        XCTAssertEqual(generatedImages[0].url?.absoluteString, "https://cdn.example.com/generated.png")
    }

    func testXAIImageGenerationParsesBase64ImageResponse() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        let expected = Data([0x89, 0x50, 0x4e, 0x47])

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/images/generations")

            let response: [String: Any] = [
                "id": "img_2",
                "data": [
                    [
                        "b64_json": expected.base64EncodedString(),
                        "mime_type": "image/png"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("draw")])],
            modelID: "grok-imagine-image",
            controls: GenerationControls(
                xaiImageGeneration: XAIImageGenerationControls(responseFormat: .b64JSON)
            ),
            tools: [],
            streaming: false
        )

        var images: [ImageContent] = []
        for try await event in stream {
            if case .contentDelta(.image(let image)) = event {
                images.append(image)
            }
        }

        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].mimeType, "image/png")
        XCTAssertEqual(images[0].data, expected)
    }

    func testXAIImageEditUsesEditsEndpointWhenInputImageProvided() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/images/edits")
            XCTAssertEqual(request.httpMethod, "POST")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "grok-imagine-image")
            XCTAssertEqual(root["prompt"] as? String, "Make this dreamy")
            XCTAssertEqual(root["aspect_ratio"] as? String, "16:9")
            XCTAssertEqual(root["response_format"] as? String, "url")
            XCTAssertNotNil(root["image_url"] as? String)

            let response: [String: Any] = [
                "request_id": "img_edit_1",
                "images": [
                    [
                        "url": "https://cdn.example.com/edited.png",
                        "mime_type": "image/png"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [
                    .text("Make this dreamy"),
                    .image(ImageContent(mimeType: "image/png", data: Data([0x01, 0x02]), url: nil))
                ])
            ],
            modelID: "grok-imagine-image",
            controls: GenerationControls(
                xaiImageGeneration: XAIImageGenerationControls(aspectRatio: .ratio16x9)
            ),
            tools: [],
            streaming: true
        )

        var messageID: String?
        var imageURL: URL?

        for try await event in stream {
            switch event {
            case .messageStart(let id):
                messageID = id
            case .contentDelta(.image(let image)):
                imageURL = image.url
            default:
                break
            }
        }

        XCTAssertEqual(messageID, "img_edit_1")
        XCTAssertEqual(imageURL?.absoluteString, "https://cdn.example.com/edited.png")
    }

    func testXAIVideoModelIDFallsBackToResponsesAPI() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/responses")

            let response: [String: Any] = [
                "id": "resp_1",
                "output": [
                    [
                        "type": "message",
                        "content": [
                            [
                                "type": "output_text",
                                "text": "Video generation is unavailable for xAI in Jin."
                            ]
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("make a short video")])],
            modelID: "grok-imagine-video",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var collectedText = ""
        for try await event in stream {
            if case .contentDelta(.text(let delta)) = event {
                collectedText.append(delta)
            }
        }

        XCTAssertTrue(collectedText.contains("unavailable"))
    }

    func testXAIModelFetchMapsImageCapabilities() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models")
            XCTAssertEqual(request.httpMethod, "GET")

            let response: [String: Any] = [
                "data": [
                    [
                        "id": "grok-4-1-fast",
                        "input_modalities": ["text", "image"],
                        "output_modalities": ["text"],
                        "context_window": 200000
                    ],
                    [
                        "id": "grok-imagine-image",
                        "input_modalities": ["text"],
                        "output_modalities": ["image"]
                    ],
                    [
                        "id": "grok-imagine-video",
                        "input_modalities": ["text", "image"],
                        "output_modalities": ["video"]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()

        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        let chat = try XCTUnwrap(byID["grok-4-1-fast"])
        XCTAssertTrue(chat.capabilities.contains(.streaming))
        XCTAssertTrue(chat.capabilities.contains(.toolCalling))
        XCTAssertTrue(chat.capabilities.contains(.vision))
        XCTAssertTrue(chat.capabilities.contains(.reasoning))
        XCTAssertTrue(chat.capabilities.contains(.nativePDF))
        XCTAssertEqual(chat.contextWindow, 200000)

        let image = try XCTUnwrap(byID["grok-imagine-image"])
        XCTAssertTrue(image.capabilities.contains(.imageGeneration))
        XCTAssertFalse(image.capabilities.contains(.toolCalling))

        XCTAssertNil(byID["grok-imagine-video"])
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

private func makeMockedURLSession() -> (URLSession, MockURLProtocol.Type) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return (URLSession(configuration: config), MockURLProtocol.self)
}

private func requestBodyData(_ request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else { return nil }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 16 * 1024
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: bufferSize)
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
