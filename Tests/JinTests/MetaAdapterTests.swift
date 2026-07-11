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
    let bufferSize = 16 * 1024
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: bufferSize)
        guard read > 0 else { break }
        data.append(buffer, count: read)
    }

    return data
}

final class MetaAdapterTests: XCTestCase {

    // MARK: - Catalog

    func testMetaCatalogSeedsMuseSparkWithDocsVerifiedMetadata() {
        let seeded = ModelCatalog.seededModels(for: .meta)
        XCTAssertEqual(seeded.map(\.id), ["muse-spark-1.1"])

        let museSpark = ModelCatalog.modelInfo(for: "muse-spark-1.1", provider: .meta)
        XCTAssertEqual(museSpark.name, "Muse Spark 1.1")
        XCTAssertEqual(museSpark.contextWindow, 1_048_576)
        XCTAssertEqual(museSpark.maxOutputTokens, 131_072)
        XCTAssertTrue(museSpark.capabilities.contains(.streaming))
        XCTAssertTrue(museSpark.capabilities.contains(.toolCalling))
        XCTAssertTrue(museSpark.capabilities.contains(.vision))
        XCTAssertTrue(museSpark.capabilities.contains(.reasoning))
        XCTAssertTrue(museSpark.capabilities.contains(.promptCaching))
        // The Chat Completions surface Jin uses has no verified video/PDF encoding.
        XCTAssertFalse(museSpark.capabilities.contains(.videoInput))
        XCTAssertFalse(museSpark.capabilities.contains(.nativePDF))
        XCTAssertEqual(museSpark.reasoningConfig?.type, .effort)
        XCTAssertEqual(museSpark.reasoningConfig?.defaultEffort, .medium)

        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .meta, modelID: "muse-spark-1.1"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .meta, modelID: "muse-spark-1.1-custom"))
    }

    func testMetaProviderTypeDefaults() {
        XCTAssertEqual(ProviderType.meta.displayName, "Meta")
        XCTAssertEqual(ProviderType.meta.defaultBaseURL, "https://api.meta.ai/v1")
        XCTAssertFalse(ProviderType.meta.supportsNativePromptCaching)
        XCTAssertFalse(ProviderType.meta.supportsNativePDFUpload)
    }

    func testMetaEffortMenuIsMinimalThroughXHigh() {
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .meta, modelID: "muse-spark-1.1"),
            [.minimal, .low, .medium, .high, .xhigh]
        )
    }

    func testMuseSparkReasoningCannotBeDisabled() {
        XCTAssertFalse(ModelSettingsResolver.defaultReasoningCanDisable(for: .meta, modelID: "muse-spark-1.1"))
    }

    func testMetaPreferredModelIsMuseSpark() {
        let models = [
            ModelInfo(id: "some-other-model", name: "Other", contextWindow: 8_192),
            ModelInfo(id: "muse-spark-1.1", name: "Muse Spark 1.1", contextWindow: 1_048_576),
        ]
        let provider = ProviderConfigEntity(
            id: "meta",
            name: "Meta",
            typeRaw: ProviderType.meta.rawValue,
            modelsData: try! JSONEncoder().encode(models)
        )
        XCTAssertEqual(
            ChatModelSelectionSupport.preferredModelID(
                in: models,
                providerID: "meta",
                providers: [provider],
                geminiPreferredModelOrder: []
            ),
            "muse-spark-1.1"
        )
    }

    // MARK: - Request shape

    func testMetaAdapterBuildsChatCompletionsRequestWithReasoningEffort() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "meta",
            name: "Meta",
            type: .meta,
            apiKey: "ignored",
            models: [ModelCatalog.modelInfo(for: "muse-spark-1.1", provider: .meta)]
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.meta.ai/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "muse-spark-1.1")
            XCTAssertEqual(root["stream"] as? Bool, false)
            XCTAssertEqual(root["reasoning_effort"] as? String, "minimal")
            // Meta documents "use temperature or top_p, not both" — temperature wins.
            XCTAssertEqual(root["temperature"] as? Double, 0.8)
            XCTAssertNil(root["top_p"])
            XCTAssertEqual(root["max_tokens"] as? Int, 4_096)
            XCTAssertNil(root["logprobs"])

            let response: [String: Any] = [
                "id": "cmpl_meta_muse_spark",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK",
                            "reasoning_content": "R"
                        ],
                        "finish_reason": "stop"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = MetaAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "muse-spark-1.1",
            controls: GenerationControls(
                temperature: 0.8,
                maxTokens: 4_096,
                topP: 0.9,
                reasoning: ReasoningControls(enabled: true, effort: .minimal)
            ),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 4)
        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "cmpl_meta_muse_spark")
        guard case .thinkingDelta(.thinking(let reasoning, _)) = events[1] else { return XCTFail("Expected thinkingDelta") }
        XCTAssertEqual(reasoning, "R")
        guard case .contentDelta(.text(let content)) = events[2] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "OK")
        guard case .messageEnd = events[3] else { return XCTFail("Expected messageEnd") }
    }

    func testMetaAdapterOmitsReasoningEffortWhenDisabledAndClampsMax() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "meta",
            name: "Meta",
            type: .meta,
            apiKey: "ignored",
            models: [ModelCatalog.modelInfo(for: "muse-spark-1.1", provider: .meta)]
        )

        // Reasoning disabled: the field must be omitted entirely — "none" returns HTTP 400.
        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertNil(root["reasoning_effort"])
            XCTAssertNil(root["reasoning"])

            let response: [String: Any] = [
                "id": "cmpl_meta_disabled",
                "choices": [["message": ["role": "assistant", "content": "OK"], "finish_reason": "stop"]]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = MetaAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let disabledStream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "muse-spark-1.1",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: false)),
            tools: [],
            streaming: false
        )
        for try await _ in disabledStream {}

        // Out-of-range efforts clamp into Meta's minimal..xhigh band ("max" is not accepted).
        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["reasoning_effort"] as? String, "xhigh")

            let response: [String: Any] = [
                "id": "cmpl_meta_max",
                "choices": [["message": ["role": "assistant", "content": "OK"], "finish_reason": "stop"]]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let maxStream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "muse-spark-1.1",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .max)),
            tools: [],
            streaming: false
        )
        for try await _ in maxStream {}
    }

    func testMetaAdapterFetchAvailableModelsUsesCatalogMetadataWhenKnown() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "meta",
            name: "Meta",
            type: .meta,
            apiKey: "ignored"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.meta.ai/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let payload: [String: Any] = [
                "data": [
                    ["id": "muse-spark-1.1"],
                    ["id": "unknown-meta-model"]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = MetaAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        let museSpark = try XCTUnwrap(byID["muse-spark-1.1"])
        XCTAssertEqual(museSpark.name, "Muse Spark 1.1")
        XCTAssertEqual(museSpark.contextWindow, 1_048_576)
        XCTAssertEqual(museSpark.maxOutputTokens, 131_072)
        XCTAssertEqual(museSpark.reasoningConfig?.defaultEffort, .medium)

        let unknown = try XCTUnwrap(byID["unknown-meta-model"])
        XCTAssertEqual(unknown.name, "unknown-meta-model")
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.reasoningConfig)
    }

    func testMetaAdapterValidateAPIKeyUsesModelsEndpoint() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "meta",
            name: "Meta",
            type: .meta,
            apiKey: "ignored"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.meta.ai/v1/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let payload: [String: Any] = ["data": [[String: Any]]()]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = MetaAdapter(providerConfig: providerConfig, apiKey: "ignored", networkManager: networkManager)
        let isValid = try await adapter.validateAPIKey("test-key")
        XCTAssertTrue(isValid)
    }
}
