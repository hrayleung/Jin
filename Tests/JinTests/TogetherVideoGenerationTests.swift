import XCTest
@testable import Jin

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

    var data = Data()
    let bufferSize = 16 * 1_024
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: bufferSize)
        guard read > 0 else { break }
        data.append(buffer, count: read)
    }

    return data
}

final class TogetherVideoGenerationTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testSeedance25IsFullySupportedOnTogether() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "ByteDance/Seedance-2.5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "bytedance/seedance-2.5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "ByteDance/Seedance-2.0"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .together, modelID: "ByteDance/Seedance-2.5-preview"))
    }

    func testSeedance25CatalogCarriesVideoGenerationMetadata() {
        for modelID in ["ByteDance/Seedance-2.5", "ByteDance/Seedance-2.0"] {
            let model = ModelCatalog.modelInfo(for: modelID, provider: .together)
            let resolved = ModelSettingsResolver.resolve(model: model, providerType: .together)
            XCTAssertEqual(resolved.modelType, .video, modelID)
            XCTAssertTrue(resolved.capabilities.contains(.videoGeneration), modelID)
            XCTAssertFalse(resolved.capabilities.contains(.streaming), modelID)
            XCTAssertEqual(resolved.contextWindow, 32_768, modelID)
            XCTAssertNil(resolved.reasoningConfig, modelID)
        }
    }

    func testSeedance25ModelSupportMatchesTogetherDocs() {
        let modelID = "ByteDance/Seedance-2.5"
        XCTAssertEqual(TogetherVideoModelSupport.supportedDurations(for: modelID), Array(4...30))
        XCTAssertEqual(
            TogetherVideoModelSupport.supportedResolutions(for: modelID),
            [.res480p, .res720p]
        )
        XCTAssertEqual(
            TogetherVideoModelSupport.supportedAspectRatios(for: modelID),
            [.ratio1x1, .ratio16x9, .ratio9x16, .ratio4x3, .ratio3x4, .ratio21x9]
        )
        XCTAssertTrue(TogetherVideoModelSupport.supportsAudio(for: modelID))
        XCTAssertTrue(TogetherVideoModelSupport.isVideoGenerationModelID(modelID))
    }

    func testSeedance20ModelSupportMatchesTogetherQuickstart() {
        let modelID = "ByteDance/Seedance-2.0"
        XCTAssertEqual(TogetherVideoModelSupport.supportedDurations(for: modelID), Array(4...15))
        XCTAssertEqual(
            TogetherVideoModelSupport.supportedResolutions(for: modelID),
            [.res480p, .res720p, .res1080p, .res4k]
        )
    }

    func testGenerationControlsRoundTripIncludesTogetherVideoControls() throws {
        let controls = GenerationControls(
            togetherVideoGeneration: TogetherVideoGenerationControls(
                durationSeconds: 24,
                aspectRatio: .ratio16x9,
                resolution: .res720p,
                imageInputMode: .frameImages,
                generateAudio: true,
                seed: 11
            )
        )

        let encoded = try JSONEncoder().encode(controls)
        let decoded = try JSONDecoder().decode(GenerationControls.self, from: encoded)

        XCTAssertEqual(decoded.togetherVideoGeneration?.durationSeconds, 24)
        XCTAssertEqual(decoded.togetherVideoGeneration?.aspectRatio, .ratio16x9)
        XCTAssertEqual(decoded.togetherVideoGeneration?.resolution, .res720p)
        XCTAssertEqual(decoded.togetherVideoGeneration?.imageInputMode, .frameImages)
        XCTAssertEqual(decoded.togetherVideoGeneration?.generateAudio, true)
        XCTAssertEqual(decoded.togetherVideoGeneration?.seed, 11)
    }

    func testTogetherVideoBaseURLMapsV1ChatBaseToV2() async {
        let adapter = TogetherAdapter(
            providerConfig: ProviderConfig(
                id: "tg",
                name: "Together",
                type: .together,
                baseURL: "https://api.together.xyz/v1"
            ),
            apiKey: "test-key",
            networkManager: NetworkManager(configuration: .ephemeral)
        )
        let url = await adapter.videoBaseURL
        XCTAssertEqual(url, "https://api.together.xyz/v2")
    }

    func testTogetherVideoGenerationBuildsSeedance25RequestBody() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "tg",
            name: "Together",
            type: .together,
            apiKey: "ignored",
            baseURL: "https://api.together.xyz/v1",
            models: [
                ModelCatalog.modelInfo(for: "ByteDance/Seedance-2.5", provider: .together)
            ]
        )

        let imageURL = URL(fileURLWithPath: "/tmp/together-seedance-first.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        var requestCount = 0
        protocolType.requestHandler = { request in
            requestCount += 1

            if requestCount == 1 {
                XCTAssertEqual(request.url?.absoluteString, "https://api.together.xyz/v2/videos")
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

                let body = try XCTUnwrap(requestBodyData(request))
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                let root = try XCTUnwrap(json)

                XCTAssertEqual(root["model"] as? String, "ByteDance/Seedance-2.5")
                XCTAssertEqual(root["prompt"] as? String, "A coastal storytelling shot")
                // Together sends duration as string seconds.
                XCTAssertEqual(root["seconds"] as? String, "30")
                XCTAssertEqual(root["ratio"] as? String, "16:9")
                XCTAssertEqual(root["resolution"] as? String, "720p")
                XCTAssertEqual(root["seed"] as? Int, 9)

                let settings = try XCTUnwrap(root["settings"] as? [String: Any])
                XCTAssertEqual(settings["audio"] as? Bool, true)

                let media = try XCTUnwrap(root["media"] as? [String: Any])
                let frames = try XCTUnwrap(media["frame_images"] as? [[String: Any]])
                XCTAssertEqual(frames.count, 1)
                XCTAssertEqual(frames[0]["frame"] as? String, "first")
                XCTAssertTrue((frames[0]["input_image"] as? String)?.hasPrefix("data:image/png;base64,") == true)

                let response: [String: Any] = [
                    "id": "videojob_tg_25",
                    "status": "in_progress",
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }

            let response: [String: Any] = [
                "id": "videojob_tg_25",
                "status": "failed",
                "error": ["message": "stop after together seedance request inspection"],
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = TogetherAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [
                Message(
                    role: .user,
                    content: [
                        .image(ImageContent(mimeType: "image/png", data: nil, url: imageURL)),
                        .text("A coastal storytelling shot"),
                    ]
                )
            ],
            modelID: "ByteDance/Seedance-2.5",
            controls: GenerationControls(
                togetherVideoGeneration: TogetherVideoGenerationControls(
                    durationSeconds: 30,
                    aspectRatio: .ratio16x9,
                    resolution: .res720p,
                    imageInputMode: .frameImages,
                    generateAudio: true,
                    seed: 9
                )
            ),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        do {
            for try await event in stream {
                events.append(event)
            }
        } catch let error as LLMError {
            guard case .providerError(let code, let message) = error else {
                return XCTFail("Expected provider error, got \(error)")
            }
            XCTAssertEqual(code, "video_generation_failed")
            XCTAssertEqual(message, "stop after together seedance request inspection")
        }

        guard case .messageStart(let id)? = events.first else {
            return XCTFail("Expected messageStart")
        }
        XCTAssertEqual(id, "videojob_tg_25")
    }

    func testTogetherVideoGenerationDropsUnsupportedSeedance25Controls() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "tg",
            name: "Together",
            type: .together,
            apiKey: "ignored",
            baseURL: "https://api.together.xyz/v1",
            models: [
                ModelCatalog.modelInfo(for: "ByteDance/Seedance-2.5", provider: .together)
            ]
        )

        var requestCount = 0
        protocolType.requestHandler = { request in
            requestCount += 1
            if requestCount == 1 {
                let body = try XCTUnwrap(requestBodyData(request))
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                let root = try XCTUnwrap(json)

                // 1080p and duration 31 are unsupported for 2.5 → dropped.
                XCTAssertNil(root["resolution"])
                XCTAssertNil(root["seconds"])
                XCTAssertEqual(root["ratio"] as? String, "9:16")

                let response: [String: Any] = [
                    "id": "videojob_tg_sanitized",
                    "status": "in_progress",
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }

            let response: [String: Any] = [
                "id": "videojob_tg_sanitized",
                "status": "failed",
                "error": ["message": "stop after sanitization"],
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = TogetherAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("Portrait shot")])],
            modelID: "ByteDance/Seedance-2.5",
            controls: GenerationControls(
                togetherVideoGeneration: TogetherVideoGenerationControls(
                    durationSeconds: 31,
                    aspectRatio: .ratio9x16,
                    resolution: .res1080p
                )
            ),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        do {
            for try await event in stream {
                events.append(event)
            }
        } catch let error as LLMError {
            guard case .providerError(let code, _) = error else {
                return XCTFail("Expected provider error, got \(error)")
            }
            XCTAssertEqual(code, "video_generation_failed")
        }

        guard case .messageStart(let id)? = events.first else {
            return XCTFail("Expected messageStart")
        }
        XCTAssertEqual(id, "videojob_tg_sanitized")
    }

    func testTogetherVideoGenerationPollsUntilDoneAndDownloadsVideoURL() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "tg",
            name: "Together",
            type: .together,
            apiKey: "ignored",
            baseURL: "https://api.together.xyz/v1",
            models: [
                ModelCatalog.modelInfo(for: "ByteDance/Seedance-2.5", provider: .together)
            ]
        )

        let sampleVideo = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70])
        var requestCount = 0
        protocolType.requestHandler = { request in
            requestCount += 1
            let url = try XCTUnwrap(request.url?.absoluteString)

            if requestCount == 1 {
                XCTAssertEqual(url, "https://api.together.xyz/v2/videos")
                let response: [String: Any] = ["id": "videojob_done", "status": "in_progress"]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }

            if url == "https://api.together.xyz/v2/videos/videojob_done" {
                let response: [String: Any] = [
                    "id": "videojob_done",
                    "status": "completed",
                    "outputs": [
                        "cost": 12,
                        "video_url": "https://cdn.example.com/together/seedance25.mp4",
                    ],
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }

            if url == "https://cdn.example.com/together/seedance25.mp4" {
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "video/mp4"]
                    )!,
                    sampleVideo
                )
            }

            XCTFail("Unexpected URL: \(url)")
            throw URLError(.badURL)
        }

        let adapter = TogetherAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("Done path")])],
            modelID: "ByteDance/Seedance-2.5",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var sawVideo = false
        for try await event in stream {
            if case .contentDelta(.video(let video)) = event {
                sawVideo = true
                XCTAssertEqual(video.mimeType, "video/mp4")
                XCTAssertNotNil(video.url)
            }
        }
        XCTAssertTrue(sawVideo)
    }

    func testTogetherVideoHelpersSupportArrayOutputsAndTopLevelDetail() async {
        let adapter = TogetherAdapter(
            providerConfig: ProviderConfig(id: "tg", name: "Together", type: .together),
            apiKey: "key",
            networkManager: NetworkManager(configuration: .ephemeral)
        )

        let jsonArrayOutputs: [String: Any] = [
            "outputs": [["video_url": "https://cdn.example.com/array_out.mp4"]]
        ]
        let url1 = await adapter.extractVideoURL(from: jsonArrayOutputs)
        XCTAssertEqual(url1, "https://cdn.example.com/array_out.mp4")

        let jsonStringArrayOutputs: [String: Any] = [
            "outputs": ["https://cdn.example.com/str_out.mp4"]
        ]
        let url2 = await adapter.extractVideoURL(from: jsonStringArrayOutputs)
        XCTAssertEqual(url2, "https://cdn.example.com/str_out.mp4")

        let jsonJobId: [String: Any] = ["job_id": "job_999"]
        let jobID = await adapter.extractVideoJobID(from: jsonJobId)
        XCTAssertEqual(jobID, "job_999")

        let jsonTopLevelDetail: [String: Any] = ["detail": "Rate limit exceeded"]
        let errorMsg = await adapter.videoFailureMessage(from: jsonTopLevelDetail)
        XCTAssertEqual(errorMsg, "Rate limit exceeded")
    }
}
