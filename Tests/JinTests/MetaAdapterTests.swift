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

final class MetaAdapterTests: XCTestCase {

    // MARK: - Catalog

    func testMetaCatalogSeedsMuseSparkSeriesWithDocsVerifiedMetadata() {
        let seeded = ModelCatalog.seededModels(for: .meta)
        XCTAssertEqual(
            seeded.map(\.id),
            ["muse-spark-1.2", "muse-spark-1.1", "muse-spark-1.2-contributor"]
        )

        for id in ["muse-spark-1.2", "muse-spark-1.1", "muse-spark-1.2-contributor"] {
            let model = ModelCatalog.modelInfo(for: id, provider: .meta)
            XCTAssertEqual(model.contextWindow, 1_048_576, id)
            XCTAssertEqual(model.maxOutputTokens, 131_072, id)
            XCTAssertTrue(model.capabilities.contains(.streaming), id)
            XCTAssertTrue(model.capabilities.contains(.toolCalling), id)
            XCTAssertTrue(model.capabilities.contains(.vision), id)
            XCTAssertTrue(model.capabilities.contains(.videoInput), id)
            XCTAssertTrue(model.capabilities.contains(.nativePDF), id)
            XCTAssertTrue(model.capabilities.contains(.reasoning), id)
            XCTAssertTrue(model.capabilities.contains(.promptCaching), id)
            XCTAssertEqual(model.reasoningConfig?.type, .effort, id)
            XCTAssertEqual(model.reasoningConfig?.defaultEffort, .medium, id)
            XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .meta, modelID: id), id)
        }

        XCTAssertEqual(ModelCatalog.modelInfo(for: "muse-spark-1.2", provider: .meta).name, "Muse Spark 1.2")
        XCTAssertEqual(
            ModelCatalog.modelInfo(for: "muse-spark-1.2-contributor", provider: .meta).name,
            "Muse Spark 1.2 Contributor"
        )
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .meta, modelID: "muse-spark-1.2-custom"))
    }

    func testGatewayCatalogsIncludeMuseSparkSeries() {
        let vercelIDs = ["meta/muse-spark-1.2", "meta/muse-spark-1.1", "meta/muse-spark-1.2-contributor"]
        for id in vercelIDs {
            let model = ModelCatalog.modelInfo(for: id, provider: .vercelAIGateway)
            XCTAssertEqual(model.contextWindow, 1_048_576, id)
            XCTAssertTrue(model.capabilities.contains(.reasoning), id)
            XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: id), id)
        }

        for id in ["meta/muse-spark-1.2", "meta/muse-spark-1.1"] {
            let model = ModelCatalog.modelInfo(for: id, provider: .openrouter)
            XCTAssertEqual(model.contextWindow, 1_048_576, id)
            XCTAssertTrue(model.capabilities.contains(.reasoning), id)
            XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: id), id)
        }
    }

    func testMetaProviderTypeDefaults() {
        XCTAssertEqual(ProviderType.meta.displayName, "Meta")
        XCTAssertEqual(ProviderType.meta.defaultBaseURL, "https://api.meta.ai/v1")
        XCTAssertTrue(ProviderType.meta.supportsNativePromptCaching)
        XCTAssertTrue(ProviderType.meta.supportsNativePDFUpload)
    }

    func testMetaEffortMenuIsMinimalThroughXHigh() {
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .meta, modelID: "muse-spark-1.2"),
            [.minimal, .low, .medium, .high, .xhigh]
        )
    }

    func testMuseSparkReasoningCannotBeDisabled() {
        for id in ["muse-spark-1.2", "muse-spark-1.1", "muse-spark-1.2-contributor"] {
            XCTAssertFalse(ModelSettingsResolver.defaultReasoningCanDisable(for: .meta, modelID: id), id)
        }
        XCTAssertFalse(
            ModelSettingsResolver.defaultReasoningCanDisable(for: .openrouter, modelID: "meta/muse-spark-1.2")
        )
        XCTAssertFalse(
            ModelSettingsResolver.defaultReasoningCanDisable(
                for: .vercelAIGateway,
                modelID: "meta/muse-spark-1.2-contributor"
            )
        )
    }

    func testMetaWebSearchSupportedForMuseSpark() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .meta, modelID: "muse-spark-1.2"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .meta, modelID: "muse-spark-1.1"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .meta, modelID: "other-model"))
    }

    func testMetaPreferredModelIsMuseSpark12() {
        let models = [
            ModelInfo(id: "muse-spark-1.1", name: "Muse Spark 1.1", contextWindow: 1_048_576),
            ModelInfo(id: "muse-spark-1.2-contributor", name: "Contributor", contextWindow: 1_048_576),
            ModelInfo(id: "muse-spark-1.2", name: "Muse Spark 1.2", contextWindow: 1_048_576),
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
            "muse-spark-1.2"
        )
    }

    // MARK: - Request shape (Responses API)

    func testMetaAdapterBuildsResponsesRequestWithReasoningEffortAndWebSearch() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "meta",
            name: "Meta",
            type: .meta,
            apiKey: "ignored",
            models: [ModelCatalog.modelInfo(for: "muse-spark-1.2", provider: .meta)]
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.meta.ai/v1/responses")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "muse-spark-1.2")
            XCTAssertEqual(root["stream"] as? Bool, false)
            XCTAssertEqual(root["max_output_tokens"] as? Int, 4_096)
            XCTAssertEqual(root["temperature"] as? Double, 0.8)
            XCTAssertNil(root["top_p"])
            XCTAssertNil(root["max_tokens"])
            XCTAssertNil(root["reasoning_effort"])

            let reasoning = try XCTUnwrap(root["reasoning"] as? [String: Any])
            XCTAssertEqual(reasoning["effort"] as? String, "minimal")

            let tools = try XCTUnwrap(root["tools"] as? [[String: Any]])
            XCTAssertTrue(tools.contains(where: { ($0["type"] as? String) == "web_search" }))

            let input = try XCTUnwrap(root["input"] as? [[String: Any]])
            XCTAssertFalse(input.isEmpty)

            let response: [String: Any] = [
                "id": "resp_meta_muse_spark",
                "status": "completed",
                "output": [
                    [
                        "type": "message",
                        "role": "assistant",
                        "content": [
                            ["type": "output_text", "text": "OK"]
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = MetaAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "muse-spark-1.2",
            controls: GenerationControls(
                temperature: 0.8,
                maxTokens: 4_096,
                topP: 0.9,
                reasoning: ReasoningControls(enabled: true, effort: .minimal),
                webSearch: WebSearchControls(enabled: true)
            ),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertGreaterThanOrEqual(events.count, 2)
        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "resp_meta_muse_spark")
        XCTAssertTrue(events.contains(where: {
            if case .contentDelta(.text("OK")) = $0 { return true }
            return false
        }))
        guard case .messageEnd = events.last else { return XCTFail("Expected messageEnd") }
    }

    func testMetaAdapterOmitsReasoningWhenDisabledAndClampsMaxToXHigh() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "meta",
            name: "Meta",
            type: .meta,
            apiKey: "ignored",
            models: [ModelCatalog.modelInfo(for: "muse-spark-1.2", provider: .meta)]
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertNil(root["reasoning"])
            XCTAssertNil(root["reasoning_effort"])

            let response: [String: Any] = [
                "id": "resp_meta_disabled",
                "status": "completed",
                "output": [
                    [
                        "type": "message",
                        "role": "assistant",
                        "content": [["type": "output_text", "text": "OK"]]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = MetaAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let disabledStream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "muse-spark-1.2",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: false)),
            tools: [],
            streaming: false
        )
        for try await _ in disabledStream {}

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            let reasoning = try XCTUnwrap(root["reasoning"] as? [String: Any])
            XCTAssertEqual(reasoning["effort"] as? String, "xhigh")

            let response: [String: Any] = [
                "id": "resp_meta_max",
                "status": "completed",
                "output": [
                    [
                        "type": "message",
                        "role": "assistant",
                        "content": [["type": "output_text", "text": "OK"]]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let maxStream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "muse-spark-1.2",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .max)),
            tools: [],
            streaming: false
        )
        for try await _ in maxStream {}
    }

    func testMetaAdapterTranslatesImagePDFAndVideoOnResponsesInput() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "meta",
            name: "Meta",
            type: .meta,
            apiKey: "ignored",
            models: [ModelCatalog.modelInfo(for: "muse-spark-1.2", provider: .meta)]
        )

        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let pdfData = Data("%PDF-1.4 sample".utf8)
        let videoData = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70])

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            let input = try XCTUnwrap(root["input"] as? [[String: Any]])
            let user = try XCTUnwrap(input.first)
            let content = try XCTUnwrap(user["content"] as? [[String: Any]])

            XCTAssertTrue(content.contains(where: { ($0["type"] as? String) == "input_text" }))
            XCTAssertTrue(content.contains(where: { ($0["type"] as? String) == "input_image" }))
            XCTAssertTrue(content.contains(where: { ($0["type"] as? String) == "input_file" }))
            XCTAssertTrue(content.contains(where: { ($0["type"] as? String) == "input_video" }))

            let response: [String: Any] = [
                "id": "resp_meta_media",
                "status": "completed",
                "output": [
                    [
                        "type": "message",
                        "role": "assistant",
                        "content": [["type": "output_text", "text": "seen"]]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = MetaAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [
                    .text("describe"),
                    .image(ImageContent(mimeType: "image/png", data: imageData)),
                    .file(FileContent(mimeType: "application/pdf", filename: "doc.pdf", data: pdfData)),
                    .video(VideoContent(mimeType: "video/mp4", data: videoData))
                ])
            ],
            modelID: "muse-spark-1.2",
            controls: GenerationControls(
                reasoning: ReasoningControls(enabled: true, effort: .medium),
                pdfProcessingMode: .native
            ),
            tools: [],
            streaming: false
        )
        for try await _ in stream {}
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
                    ["id": "muse-spark-1.2"],
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

        let museSpark = try XCTUnwrap(byID["muse-spark-1.2"])
        XCTAssertEqual(museSpark.name, "Muse Spark 1.2")
        XCTAssertEqual(museSpark.contextWindow, 1_048_576)
        XCTAssertEqual(museSpark.maxOutputTokens, 131_072)
        XCTAssertTrue(museSpark.capabilities.contains(.videoInput))
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

    func testMuseSparkReasoningReplayAcceptsMetaAndOpenCodeGoProviders() {
        XCTAssertTrue(MetaResponsesInputSupport.isMuseSparkReasoningReplayProvider(ProviderType.meta.rawValue))
        XCTAssertTrue(MetaResponsesInputSupport.isMuseSparkReasoningReplayProvider(ProviderType.opencodeGo.rawValue))
        XCTAssertFalse(MetaResponsesInputSupport.isMuseSparkReasoningReplayProvider(ProviderType.anthropic.rawValue))
        XCTAssertFalse(MetaResponsesInputSupport.isMuseSparkReasoningReplayProvider(nil))
        XCTAssertFalse(MetaResponsesInputSupport.isMuseSparkReasoningReplayProvider(""))
    }

    func testMetaPromptCacheRetentionMapping() {
        XCTAssertNil(MetaResponsesRequestSupport.metaPromptCacheRetention(for: .providerDefault))
        XCTAssertEqual(MetaResponsesRequestSupport.metaPromptCacheRetention(for: .minutes5), "in_memory")
        XCTAssertEqual(MetaResponsesRequestSupport.metaPromptCacheRetention(for: .hour1), "24h")
        XCTAssertEqual(MetaResponsesRequestSupport.metaPromptCacheRetention(for: .customSeconds(120)), "in_memory")
        XCTAssertEqual(MetaResponsesRequestSupport.metaPromptCacheRetention(for: .customSeconds(7_200)), "24h")
    }

    // MARK: - Encrypted reasoning continuity

    func testMetaResponsesRequestRequestsEncryptedReasoningAndDisablesStore() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let providerConfig = ProviderConfig(
            id: "meta",
            name: "Meta",
            type: .meta,
            models: [ModelCatalog.modelInfo(for: "muse-spark-1.2", provider: .meta)]
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(root["store"] as? Bool, false)
            let include = try XCTUnwrap(root["include"] as? [String])
            XCTAssertTrue(include.contains("reasoning.encrypted_content"))
            XCTAssertNil(root["previous_response_id"])

            let response: [String: Any] = [
                "id": "resp_enc",
                "status": "completed",
                "output": [
                    [
                        "id": "rs_1",
                        "type": "reasoning",
                        "encrypted_content": "cipher_payload",
                        "summary": [["type": "summary_text", "text": "plan"]]
                    ],
                    [
                        "type": "message",
                        "role": "assistant",
                        "content": [["type": "output_text", "text": "done"]]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = MetaAdapter(providerConfig: providerConfig, apiKey: "k", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "muse-spark-1.2",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .medium)),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream { events.append(event) }

        XCTAssertTrue(events.contains(where: {
            if case .thinkingDelta(.redacted(let data, let id)) = $0 {
                return data == "cipher_payload" && id == "rs_1"
            }
            return false
        }))
        XCTAssertTrue(events.contains(where: {
            if case .thinkingDelta(.thinking(let text, _)) = $0 { return text == "plan" }
            return false
        }))
        XCTAssertTrue(events.contains(where: {
            if case .contentDelta(.text("done")) = $0 { return true }
            return false
        }))
    }

    func testMetaReplaysEncryptedReasoningBeforeAssistantAndTools() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let providerConfig = ProviderConfig(
            id: "meta",
            name: "Meta",
            type: .meta,
            models: [ModelCatalog.modelInfo(for: "muse-spark-1.2", provider: .meta)]
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let input = try XCTUnwrap(root["input"] as? [[String: Any]])

            // Expected order for tool-loop turn:
            // user → reasoning → assistant text → function_call → function_call_output
            XCTAssertEqual(input.count, 5)
            XCTAssertEqual(input[0]["role"] as? String, "user")
            XCTAssertEqual(input[1]["type"] as? String, "reasoning")
            XCTAssertEqual(input[1]["encrypted_content"] as? String, "enc_tool_loop")
            XCTAssertEqual(input[1]["id"] as? String, "rs_tool")
            let summary = try XCTUnwrap(input[1]["summary"] as? [Any])
            XCTAssertTrue(summary.isEmpty)
            XCTAssertEqual(input[2]["role"] as? String, "assistant")
            XCTAssertEqual(input[3]["type"] as? String, "function_call")
            XCTAssertEqual(input[4]["type"] as? String, "function_call_output")

            // No foreign Anthropic redacted blob.
            let reasoningItems = input.filter { ($0["type"] as? String) == "reasoning" }
            XCTAssertEqual(reasoningItems.count, 1)

            let response: [String: Any] = [
                "id": "resp_replay",
                "status": "completed",
                "output": [
                    [
                        "type": "message",
                        "role": "assistant",
                        "content": [["type": "output_text", "text": "ok"]]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = MetaAdapter(providerConfig: providerConfig, apiKey: "k", networkManager: networkManager)
        let priorAssistant = Message(
            role: .assistant,
            content: [
                .redactedThinking(RedactedThinkingBlock(
                    data: "enc_tool_loop",
                    provider: ProviderType.meta.rawValue,
                    id: "rs_tool"
                )),
                // Foreign redacted must not be replayed.
                .redactedThinking(RedactedThinkingBlock(
                    data: "anthropic-blob",
                    provider: ProviderType.anthropic.rawValue
                )),
                .text("calling tool")
            ],
            toolCalls: [
                ToolCall(id: "call_1", name: "lookup", arguments: ["q": AnyCodable("x")])
            ]
        )
        let toolResult = Message(
            role: .tool,
            content: [.text("result")],
            toolResults: [
                ToolResult(toolCallID: "call_1", toolName: "lookup", content: "result")
            ]
        )

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.text("go")]),
                priorAssistant,
                toolResult
            ],
            modelID: "muse-spark-1.2",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .high)),
            tools: [],
            streaming: false
        )
        for try await _ in stream {}
    }

    func testMetaInsertsEmptyAssistantAfterReasoningOnlyTurn() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let providerConfig = ProviderConfig(
            id: "meta",
            name: "Meta",
            type: .meta,
            models: [ModelCatalog.modelInfo(for: "muse-spark-1.2", provider: .meta)]
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let input = try XCTUnwrap(root["input"] as? [[String: Any]])

            // user → reasoning → empty assistant → user
            XCTAssertEqual(input.count, 4)
            XCTAssertEqual(input[1]["type"] as? String, "reasoning")
            XCTAssertEqual(input[2]["role"] as? String, "assistant")
            let content = try XCTUnwrap(input[2]["content"] as? [[String: Any]])
            XCTAssertEqual(content.first?["type"] as? String, "output_text")
            XCTAssertEqual(content.first?["text"] as? String, "")
            XCTAssertEqual(input[3]["role"] as? String, "user")

            let response: [String: Any] = [
                "id": "resp_empty_follow",
                "status": "completed",
                "output": [
                    [
                        "type": "message",
                        "role": "assistant",
                        "content": [["type": "output_text", "text": "ok"]]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = MetaAdapter(providerConfig: providerConfig, apiKey: "k", networkManager: networkManager)
        let reasoningOnly = Message(
            role: .assistant,
            content: [
                .redactedThinking(RedactedThinkingBlock(
                    data: "enc_only",
                    provider: ProviderType.meta.rawValue,
                    id: "rs_only"
                ))
            ]
        )
        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.text("a")]),
                reasoningOnly,
                Message(role: .user, content: [.text("b")])
            ],
            modelID: "muse-spark-1.2",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .low)),
            tools: [],
            streaming: false
        )
        for try await _ in stream {}
    }

    func testContentPartRoundTripsMetaRedactedThinkingID() throws {
        let original = ContentPart.redactedThinking(
            RedactedThinkingBlock(data: "cipher", provider: "meta", id: "rs_roundtrip")
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ContentPart.self, from: data)
        guard case .redactedThinking(let block) = decoded else {
            return XCTFail("Expected redactedThinking")
        }
        XCTAssertEqual(block.data, "cipher")
        XCTAssertEqual(block.provider, "meta")
        XCTAssertEqual(block.id, "rs_roundtrip")
    }
}
