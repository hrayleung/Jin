import Foundation
import XCTest
@testable import Jin

final class OpenAIImage26RequestTests: XCTestCase {
    private let ids = ["gpt-image-2.6-flare", "gpt-image-2.6-sunburst"]

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func adapter(networkManager: NetworkManager = NetworkManager(configuration: .ephemeral)) -> OpenAIAdapter {
        OpenAIAdapter(providerConfig: ProviderConfig(id: "openai", name: "OpenAI", type: .openai,
            baseURL: "https://example.com/v1"), apiKey: "test-key", networkManager: networkManager)
    }

    private func json(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requestBodyData(request))) as? [String: Any])
    }

    func testBothModelsSendComplexityQualityAndCustomSizeToImageEndpoint() async throws {
        let adapter = adapter()
        for id in ids {
            for quality in [OpenAIImageQuality.xhigh, .max] {
                let request = try await adapter.buildImageGenerationRequest(modelID: id, prompt: "Draw a diagram", inputImages: [],
                    controls: GenerationControls(openaiImageGeneration: .init(count: 10, size: .init(rawValue: "3840x2160"),
                        quality: quality, background: .transparent, outputFormat: .webp, outputCompression: 37,
                        moderation: .low, complexity: .medium)))
                XCTAssertEqual(request.url?.path, "/v1/images/generations")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
                let body = try json(request)
                XCTAssertEqual(body["model"] as? String, id)
                XCTAssertEqual(body["n"] as? Int, 10)
                XCTAssertEqual(body["size"] as? String, "3840x2160")
                XCTAssertEqual(body["quality"] as? String, quality.rawValue)
                XCTAssertEqual(body["complexity"] as? String, "medium")
                XCTAssertEqual(body["background"] as? String, "transparent")
                XCTAssertEqual(body["output_compression"] as? Int, 37)
                XCTAssertEqual(body["moderation"] as? String, "low")
                XCTAssertNil(body["input_fidelity"])
                XCTAssertNil(body["stream"])
            }
        }
    }

    func testSVGForcesSingleOutputAndBlocksConflictingOverrides() async throws {
        let controls = GenerationControls(
            openaiImageGeneration: .init(count: 8, quality: .max, outputFormat: .svg, outputCompression: 50,
                inputFidelity: .high, complexity: .high, frameCount: 9),
            providerSpecific: ["model": AnyCodable("wrong"), "n": AnyCodable(9), "output_format": AnyCodable("jpeg"),
                "stream": AnyCodable(true), "partial_images": AnyCodable(3), "prompt_rewriter": AnyCodable(true)])
        let request = try await adapter().buildImageGenerationRequest(modelID: ids[0], prompt: "Vector logo", inputImages: [], controls: controls)
        let body = try json(request)
        XCTAssertEqual(body["model"] as? String, ids[0])
        XCTAssertEqual(body["output_format"] as? String, "svg")
        XCTAssertEqual(body["n"] as? Int, 1)
        XCTAssertEqual(body["quality"] as? String, "max")
        for key in ["stream", "partial_images", "prompt_rewriter", "output_compression", "frame_count", "input_fidelity"] {
            XCTAssertNil(body[key], key)
        }
    }

    func testGIFParametersUseAnimationRangesAndDoNotLeakToRaster() async throws {
        let request = try await adapter().buildImageGenerationRequest(modelID: ids[1], prompt: "Animate a lantern", inputImages: [],
            controls: GenerationControls(openaiImageGeneration: .init(size: .init(rawValue: "512x512"), outputFormat: .gif,
                outputCompression: 75, frameCount: 65, frameDurationMilliseconds: 155)))
        let body = try json(request)
        XCTAssertEqual(body["output_format"] as? String, "gif")
        XCTAssertEqual(body["size"] as? String, "512x512")
        XCTAssertEqual(body["frame_count"] as? Int, 64)
        XCTAssertEqual(body["frame_duration_ms"] as? Int, 160)
        XCTAssertNil(body["output_compression"])
        let raster = try await adapter().buildImageGenerationRequest(modelID: ids[1], prompt: "Draw a lantern", inputImages: [],
            controls: GenerationControls(openaiImageGeneration: .init(outputFormat: .png, frameCount: 64, frameDurationMilliseconds: 120)))
        XCTAssertNil(try json(raster)["frame_count"])
        XCTAssertNil(try json(raster)["frame_duration_ms"])
    }

    func testMarkupAndMaskAreSeparateMultipartPartsNotReferenceImages() async throws {
        let original = ImageContent(mimeType: "image/png", data: try OpenAIImage26SupportTests.png(), url: nil)
        let guide = ImageContent(mimeType: "image/png", data: try OpenAIImage26SupportTests.png(alpha: 0.2), url: nil)
        for kind in OpenAIImageEditGuidance.allCases {
            let request = try await adapter().buildImageGenerationRequest(modelID: ids[0], prompt: "Recolor the vase",
                inputImages: [original, original, guide], controls: GenerationControls(
                    openaiImageGeneration: .init(quality: .xhigh, outputFormat: .png, complexity: .low, inputMode: .edit, editGuidance: kind),
                    providerSpecific: ["prompt_rewriter": AnyCodable(true)]))
            XCTAssertEqual(request.url?.path, "/v1/images/edits")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)
            let body = String(decoding: try XCTUnwrap(requestBodyData(request)), as: UTF8.self)
            XCTAssertEqual(body.components(separatedBy: "name=\"image[]\"").count - 1, 2)
            XCTAssertTrue(body.contains("name=\"\(kind.rawValue)\"; filename=\"\(kind.rawValue).png\""))
            XCTAssertTrue(body.contains("name=\"complexity\"\r\n\r\nlow"))
            XCTAssertFalse(body.contains("name=\"prompt_rewriter\""))
        }
    }

    func testRemoteAndMixedEditsUseJSONWithoutDroppingReferences() async throws {
        let remote = ImageContent(mimeType: "image/png", data: nil, url: URL(string: "https://example.com/original.png"))
        let reference = ImageContent(mimeType: "image/png", data: try OpenAIImage26SupportTests.png(), url: nil)
        let guide = ImageContent(mimeType: "image/png", data: try OpenAIImage26SupportTests.png(alpha: 0.2), url: nil)
        let request = try await adapter().buildImageGenerationRequest(modelID: ids[1], prompt: "Change this area", inputImages: [remote, reference, guide],
            controls: GenerationControls(openaiImageGeneration: .init(editGuidance: .markup)))
        XCTAssertEqual(request.url?.path, "/v1/images/edits")
        let body = try json(request)
        let images = try XCTUnwrap(body["images"] as? [[String: String]])
        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(images[0]["image_url"], remote.url?.absoluteString)
        XCTAssertTrue(images[1]["image_url"]?.hasPrefix("data:image/png;base64,") == true)
        XCTAssertTrue((body["markup"] as? [String: String])?["image_url"]?.hasPrefix("data:image/png;base64,") == true)
        XCTAssertNil(body["image"])
    }

    func testInvalidInputCombinationsFailBeforeNetworking() async throws {
        let image = ImageContent(mimeType: "image/png", data: try OpenAIImage26SupportTests.png(), url: nil)
        let local = ImageContent(mimeType: "image/png", data: nil, url: URL(fileURLWithPath: "/etc/passwd"))
        let nonPNGGuide = ImageContent(mimeType: "image/jpeg", data: nil, url: URL(string: "https://example.com/mask.jpg"))
        let invalid: [([ImageContent], OpenAIImageGenerationControls)] = [
            ([image], .init(outputFormat: .svg)), ([image], .init(outputFormat: .gif)),
            ([image], .init(inputMode: .generate)), ([], .init(inputMode: .edit)),
            ([image], .init(editGuidance: .markup)), ([image, image], .init(editGuidance: .markup)),
            ([image, nonPNGGuide], .init(editGuidance: .mask)), ([local], .init()),
            (Array(repeating: image, count: 17), .init()), ([], .init(size: .init(rawValue: "513x512")))
        ]
        for (images, options) in invalid {
            do {
                _ = try await adapter().buildImageGenerationRequest(modelID: ids[0], prompt: "Edit", inputImages: images,
                    controls: GenerationControls(openaiImageGeneration: options))
                XCTFail("Invalid request should have failed")
            } catch { XCTAssertTrue(error is LLMError) }
        }
    }

    func testGenerationModeDoesNotAccidentallyEditPreviousImages() async throws {
        let image = ImageContent(mimeType: "image/png", data: try OpenAIImage26SupportTests.png(), url: nil)
        let messages = [Message(role: .assistant, content: [.image(image)]), Message(role: .user, content: [.text("New drawing")])]
        let adapter = adapter()
        let automatic = try await adapter.imageGenerationInputs(messages: messages, modelID: ids[0], controls: GenerationControls())
        XCTAssertEqual(automatic.count, 1)
        for options in [OpenAIImageGenerationControls(inputMode: .generate), .init(outputFormat: .svg), .init(outputFormat: .gif)] {
            let inputs = try await adapter.imageGenerationInputs(messages: messages, modelID: ids[0], controls: GenerationControls(openaiImageGeneration: options))
            XCTAssertTrue(inputs.isEmpty)
        }
        do {
            _ = try await adapter.imageGenerationInputs(messages: messages, modelID: ids[0],
                controls: GenerationControls(openaiImageGeneration: .init(editGuidance: .markup)))
            XCTFail("Guidance must use current attachments")
        } catch { XCTAssertTrue(error is LLMError) }
    }

    func testBothModelsReturnNativeFormatsAndTokenUsageThroughPublicAdapter() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let adapter = adapter(networkManager: NetworkManager(configuration: configuration))
        for id in ids {
            for (format, data) in [(OpenAIImageOutputFormat.svg, OpenAIImage26SupportTests.svg), (.gif, try OpenAIImage26SupportTests.gif())] {
                protocolType.requestHandler = { request in
                    XCTAssertEqual(request.url?.path, "/v1/images/generations")
                    let response: [String: Any] = ["data": [["b64_json": data.base64EncodedString()]], "output_format": format.rawValue,
                        "usage": ["input_tokens": 12, "output_tokens": 34, "input_tokens_details": ["cached_tokens": 5]]]
                    return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        try JSONSerialization.data(withJSONObject: response))
                }
                let stream = try await adapter.sendMessage(messages: [Message(role: .user, content: [.text("Create")])], modelID: id,
                    controls: GenerationControls(openaiImageGeneration: .init(outputFormat: format)), tools: [], streaming: true)
                var imageCount = 0
                var usage: Usage?
                for try await event in stream {
                    if case .contentDelta(.image(let image)) = event {
                        XCTAssertEqual(image.mimeType, format.mimeType)
                        XCTAssertEqual(image.data, data)
                        imageCount += 1
                    }
                    if case .messageEnd(let value) = event { usage = value }
                }
                XCTAssertEqual(imageCount, 1)
                XCTAssertEqual(usage?.inputTokens, 12)
                XCTAssertEqual(usage?.outputTokens, 34)
                XCTAssertEqual(usage?.cachedTokens, 5)
            }
        }
    }

    func testWebSocketProviderUsesExistingHTTPImageFallbackForBothModels() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let network = NetworkManager(configuration: configuration)
        let adapter = OpenAIWebSocketAdapter(providerConfig: ProviderConfig(id: "openai-ws", name: "OpenAI WebSocket",
            type: .openaiWebSocket, baseURL: "wss://example.com/v1"), apiKey: "test-key", networkManager: network)
        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.path, "/v1/images/generations")
            let response: [String: Any] = ["data": [["b64_json": OpenAIImage26SupportTests.svg.base64EncodedString()]]]
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    try JSONSerialization.data(withJSONObject: response))
        }
        for id in ids {
            let stream = try await adapter.sendMessage(messages: [Message(role: .user, content: [.text("Vector logo")])], modelID: id,
                controls: GenerationControls(openaiImageGeneration: .init(outputFormat: .svg)), tools: [], streaming: true)
            var count = 0
            for try await event in stream {
                if case .contentDelta(.image(let image)) = event {
                    XCTAssertEqual(image.mimeType, "image/svg+xml")
                    count += 1
                }
            }
            XCTAssertEqual(count, 1)
            let settings = ModelSettingsResolver.resolve(model: ModelInfo(id: id, name: id, capabilities: [], contextWindow: 128_000), providerType: .openaiWebSocket)
            XCTAssertEqual(settings.contextWindow, 0)
            XCTAssertNil(settings.maxOutputTokens)
        }
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
