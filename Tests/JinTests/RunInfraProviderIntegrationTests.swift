import XCTest
@testable import Jin

final class RunInfraProviderIntegrationTests: XCTestCase {

    func testProviderTypeDefaults() {
        XCTAssertEqual(ProviderType.runinfra.displayName, "RunInfra")
        XCTAssertEqual(ProviderType.runinfra.defaultBaseURL, "https://api.runinfra.ai/v1")
        XCTAssertEqual(LobeProviderIconCatalog.defaultIconID(for: .runinfra), "RunInfra")
        XCTAssertEqual(ProviderFormSupport.credentialKind(for: .runinfra), .apiKey)
        XCTAssertEqual(
            ModelCapabilityRegistry.requestShape(for: .runinfra, modelID: "deepseek-v4-flash"),
            .openAICompatible
        )
        XCTAssertFalse(ProviderType.runinfra.supportsNativePromptCaching)
        XCTAssertFalse(ProviderType.runinfra.supportsNativePDFUpload)
    }

    func testSeededModelsMatchOfficialCatalog() {
        let seeded = ModelCatalog.seededModels(for: .runinfra)
        let expectedIDs = [
            "deepseek-v4-flash",
            "glm-5-3-flash",
            "deepseek-v4-pro",
            "qwen3-8-27b",
            "qwen3-8-flash-next",
            "ornith-1-5-35b",
            "nemotron-3-5-lightning-30b",
            "qwen3-8-2-4t-a95b",
        ]
        XCTAssertEqual(seeded.map(\.id), expectedIDs)

        for id in expectedIDs {
            XCTAssertTrue(ModelCatalog.isFullySupported(modelID: id, provider: .runinfra), id)
            let info = ModelCatalog.modelInfo(for: id, provider: .runinfra)
            XCTAssertTrue(info.capabilities.contains(.streaming), id)
            XCTAssertTrue(info.capabilities.contains(.toolCalling), id)
            XCTAssertTrue(info.capabilities.contains(.reasoning), id)
            XCTAssertTrue(info.capabilities.contains(.promptCaching), id)
            XCTAssertEqual(info.capabilities.contains(.vision), id == "qwen3-8-27b", id)
            XCTAssertEqual(info.maxOutputTokens, 32_768, id)
            XCTAssertFalse(
                ModelCapabilityRegistry.supportsWebSearch(for: .runinfra, modelID: id),
                id
            )
        }
    }

    func testSeedConfigAndAdapterBaseURL() async {
        let config = DefaultProviderSeeds.runinfra
        XCTAssertEqual(config.type, .runinfra)
        XCTAssertEqual(config.baseURL, "https://api.runinfra.ai/v1")
        XCTAssertEqual(config.models.map(\.id).first, "deepseek-v4-flash")
        XCTAssertEqual(config.models.count, 8)
        XCTAssertTrue(DefaultProviderSeeds.allProviders().contains(where: { $0.id == "runinfra" }))

        let adapter = RunInfraAdapter(providerConfig: config, apiKey: "test-key")
        let baseURL = await adapter.baseURL
        XCTAssertEqual(baseURL, "https://api.runinfra.ai/v1")
    }

    func testPreferredModelIsDeepSeekV4Flash() {
        let models = ModelCatalog.seededModels(for: .runinfra)
        XCTAssertEqual(ChatModelSelectionSupport.preferredRunInfraModelOrder.first, "deepseek-v4-flash")
        XCTAssertEqual(models.first?.id, "deepseek-v4-flash")
    }

    func testFlashContextAndEffortBand() {
        let info = ModelCatalog.modelInfo(for: "deepseek-v4-flash", provider: .runinfra)
        XCTAssertEqual(info.name, "DeepSeek V4 Flash")
        XCTAssertEqual(info.contextWindow, 1_048_576)
        XCTAssertEqual(info.reasoningConfig?.type, .effort)
        XCTAssertEqual(info.reasoningConfig?.defaultEffort, .max)
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .runinfra, modelID: "deepseek-v4-flash"),
            [.none, .low, .medium, .max]
        )
        XCTAssertTrue(ModelSettingsResolver.defaultReasoningCanDisable(for: .runinfra, modelID: "deepseek-v4-flash"))
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(for: .runinfra, modelID: "deepseek-v4-flash")
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.high, for: .runinfra, modelID: "deepseek-v4-flash"),
            .medium
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.xhigh, for: .runinfra, modelID: "deepseek-v4-flash"),
            .max
        )
    }

    func testQwen27BEffortBand() {
        let info = ModelCatalog.modelInfo(for: "qwen3-8-27b", provider: .runinfra)
        XCTAssertEqual(info.contextWindow, 262_144)
        XCTAssertTrue(info.capabilities.contains(.vision))
        XCTAssertEqual(info.reasoningConfig?.type, .effort)
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .runinfra, modelID: "qwen3-8-27b"),
            [.none, .low, .medium, .xhigh]
        )
        XCTAssertTrue(ModelSettingsResolver.defaultReasoningCanDisable(for: .runinfra, modelID: "qwen3-8-27b"))
        let alias = ModelCatalog.modelInfo(for: "Qwen/Qwen3.8-27B", provider: .runinfra)
        XCTAssertTrue(alias.capabilities.contains(.vision))
    }

    func testQwen38FlashNextCatalogUsesExactLiveID() {
        let info = ModelCatalog.modelInfo(for: "qwen3-8-flash-next", provider: .runinfra)
        XCTAssertEqual(info.name, "Qwen3.8 Flash Next")
        XCTAssertEqual(info.contextWindow, 262_144)
        XCTAssertEqual(info.maxOutputTokens, 32_768)
        XCTAssertEqual(
            info.capabilities,
            [.streaming, .toolCalling, .reasoning, .promptCaching]
        )
        XCTAssertFalse(info.capabilities.contains(.vision))
        XCTAssertEqual(info.reasoningConfig?.type, .toggle)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "qwen3-8-flash-next", provider: .runinfra))
        XCTAssertTrue(
            ModelSettingsResolver.defaultReasoningCanDisable(for: .runinfra, modelID: "qwen3-8-flash-next")
        )
        XCTAssertFalse(
            ModelCatalog.isFullySupported(modelID: "qwen3-8-flash-next-custom", provider: .runinfra)
        )
        XCTAssertFalse(
            ModelCatalog.isFullySupported(modelID: "Qwen/Qwen3.8-Flash-Next", provider: .runinfra)
        )
    }

    func testQwen24TThinkingCannotDisable() {
        let info = ModelCatalog.modelInfo(for: "qwen3-8-2-4t-a95b", provider: .runinfra)
        XCTAssertEqual(info.reasoningConfig?.type, .effort)
        XCTAssertEqual(info.reasoningConfig?.defaultEffort, .xhigh)
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .runinfra, modelID: "qwen3-8-2-4t-a95b"),
            [.low, .medium, .xhigh]
        )
        XCTAssertFalse(
            ModelSettingsResolver.defaultReasoningCanDisable(for: .runinfra, modelID: "qwen3-8-2-4t-a95b")
        )
        XCTAssertFalse(
            ModelSettingsResolver.defaultReasoningCanDisable(
                for: .runinfra,
                modelID: "Inferact/Qwen3.8-2.4T-A95B-NVFP4"
            )
        )
    }

    func testToggleModels() {
        for id in ["deepseek-v4-pro", "nemotron-3-5-lightning-30b", "ornith-1-5-35b", "glm-5-3-flash", "qwen3-8-flash-next"] {
            let info = ModelCatalog.modelInfo(for: id, provider: .runinfra)
            XCTAssertEqual(info.reasoningConfig?.type, .toggle, id)
            XCTAssertTrue(ModelSettingsResolver.defaultReasoningCanDisable(for: .runinfra, modelID: id), id)
        }
    }

    func testHuggingFaceAliasesAreFullySupportedAndUnseeded() {
        let aliases: [(id: String, official: String, context: Int)] = [
            ("deepseek-ai/DeepSeek-V4-Flash-0731", "deepseek-v4-flash", 1_048_576),
            ("zai-org/GLM-5.3-Flash", "glm-5-3-flash", 1_048_576),
            ("deepseek-ai/DeepSeek-V4-Pro-0813", "deepseek-v4-pro", 1_048_576),
            ("Qwen/Qwen3.8-27B", "qwen3-8-27b", 262_144),
            ("ornith-ai/Ornith-1.5-35B-A3B", "ornith-1-5-35b", 262_144),
            ("nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-BF16", "nemotron-3-5-lightning-30b", 262_144),
            ("Inferact/Qwen3.8-2.4T-A95B-NVFP4", "qwen3-8-2-4t-a95b", 262_144),
        ]

        let seededIDs = Set(ModelCatalog.seededModels(for: .runinfra).map(\.id))
        for alias in aliases {
            XCTAssertTrue(ModelCatalog.isFullySupported(modelID: alias.id, provider: .runinfra), alias.id)
            XCTAssertFalse(seededIDs.contains(alias.id), alias.id)
            let info = ModelCatalog.modelInfo(for: alias.id, provider: .runinfra)
            let official = ModelCatalog.modelInfo(for: alias.official, provider: .runinfra)
            XCTAssertEqual(info.contextWindow, alias.context, alias.id)
            XCTAssertEqual(info.reasoningConfig, official.reasoningConfig, alias.id)
            XCTAssertEqual(info.capabilities, official.capabilities, alias.id)
        }
    }

    func testMaxEffortIsProviderScoped() {
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(
                for: .runinfra,
                modelID: "deepseek-v4-flash"
            )
        )
        XCTAssertFalse(
            ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(
                for: .together,
                modelID: "deepseek-v4-flash"
            )
        )
    }

    func testFlashRequestSendsReasoningEffortMaxAndOmitsReasoningObject() async throws {
        let (configuration, protocolType) = runinfraMakeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let providerConfig = DefaultProviderSeeds.runinfra

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.runinfra.ai/v1/chat/completions")
            let body = try XCTUnwrap(runinfraRequestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "deepseek-v4-flash")
            XCTAssertEqual(root["reasoning_effort"] as? String, "max")
            XCTAssertNil(root["reasoning"])
            XCTAssertEqual(root["max_tokens"] as? Int, 16_384)
            XCTAssertEqual(root["stream"] as? Bool, false)

            return try runinfraOKResponse(url: request.url!)
        }

        let adapter = RunInfraAdapter(
            providerConfig: providerConfig,
            apiKey: "test-key",
            networkManager: networkManager
        )
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "deepseek-v4-flash",
            controls: GenerationControls(
                maxTokens: 16_384,
                reasoning: ReasoningControls(enabled: true, effort: .max)
            ),
            tools: [],
            streaming: false
        )
        for try await _ in stream {}
    }

    func testFlashDisableSendsReasoningEffortNone() async throws {
        let (configuration, protocolType) = runinfraMakeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(runinfraRequestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["reasoning_effort"] as? String, "none")
            XCTAssertNil(root["reasoning"])
            return try runinfraOKResponse(url: request.url!)
        }

        let adapter = RunInfraAdapter(
            providerConfig: DefaultProviderSeeds.runinfra,
            apiKey: "test-key",
            networkManager: networkManager
        )
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "deepseek-v4-flash",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: false)),
            tools: [],
            streaming: false
        )
        for try await _ in stream {}
    }

    func testAlwaysOnQwenOmitsNoneWhenDisabled() async throws {
        let (configuration, protocolType) = runinfraMakeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(runinfraRequestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "qwen3-8-2-4t-a95b")
            XCTAssertNil(root["reasoning_effort"])
            XCTAssertNil(root["reasoning"])
            return try runinfraOKResponse(url: request.url!)
        }

        let adapter = RunInfraAdapter(
            providerConfig: DefaultProviderSeeds.runinfra,
            apiKey: "test-key",
            networkManager: networkManager
        )
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "qwen3-8-2-4t-a95b",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: false, effort: .none)),
            tools: [],
            streaming: false
        )
        for try await _ in stream {}
    }

    func testToggleOffSendsNoneAndStreamingAsksForUsage() async throws {
        let (configuration, protocolType) = runinfraMakeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(runinfraRequestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "nemotron-3-5-lightning-30b")
            XCTAssertEqual(root["reasoning_effort"] as? String, "none")
            XCTAssertEqual(root["stream"] as? Bool, true)
            let streamOptions = try XCTUnwrap(root["stream_options"] as? [String: Any])
            XCTAssertEqual(streamOptions["include_usage"] as? Bool, true)
            let sse = "data: {\"id\":\"chatcmpl-runinfra\",\"choices\":[{\"delta\":{\"content\":\"OK\"}}]}\n\ndata: [DONE]\n\n"
            let data = Data(sse.utf8)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!,
                data
            )
        }

        let adapter = RunInfraAdapter(
            providerConfig: DefaultProviderSeeds.runinfra,
            apiKey: "test-key",
            networkManager: networkManager
        )
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "nemotron-3-5-lightning-30b",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: false)),
            tools: [],
            streaming: true
        )
        for try await _ in stream {}
    }

    func testQwen27BForwardsInlineImageParts() async throws {
        let (configuration, protocolType) = runinfraMakeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(runinfraRequestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "qwen3-8-27b")
            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
            XCTAssertTrue(content.contains(where: { $0["type"] as? String == "image_url" }))
            return try runinfraOKResponse(url: request.url!)
        }

        let adapter = RunInfraAdapter(
            providerConfig: DefaultProviderSeeds.runinfra,
            apiKey: "test-key",
            networkManager: networkManager
        )
        let stream = try await adapter.sendMessage(
            messages: [
                Message(
                    role: .user,
                    content: [
                        .text("describe"),
                        .image(ImageContent(mimeType: "image/png", data: Data([0x89, 0x50]), url: nil)),
                    ]
                )
            ],
            modelID: "qwen3-8-27b",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )
        for try await _ in stream {}
    }

    func testQwen27BCapsImagesAtDocumentedPerRequestLimit() async throws {
        let (configuration, protocolType) = runinfraMakeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(runinfraRequestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
            let imageCount = content.filter { $0["type"] as? String == "image_url" }.count
            XCTAssertEqual(imageCount, RunInfraVisionSupport.maxImagesPerRequest)
            let texts = content.compactMap { $0["text"] as? String }
            XCTAssertTrue(texts.contains(where: { $0.contains("Omitted 1 extra image") }))
            return try runinfraOKResponse(url: request.url!)
        }

        let images = (0..<9).map { _ in
            ContentPart.image(ImageContent(mimeType: "image/png", data: Data([0x89, 0x50]), url: nil))
        }
        let adapter = RunInfraAdapter(
            providerConfig: DefaultProviderSeeds.runinfra,
            apiKey: "test-key",
            networkManager: networkManager
        )
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("describe")] + images)],
            modelID: "qwen3-8-27b",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )
        for try await _ in stream {}
    }

    func testQwen27BPrioritizesNewestImagesAcrossMultipleTurns() async throws {
        let (configuration, protocolType) = runinfraMakeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(runinfraRequestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 3)

            // Turn 1 (historical): 8 images attached originally, oldest 1 is omitted to reserve budget for Turn 3
            let turn1Content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
            let turn1Images = turn1Content.filter { $0["type"] as? String == "image_url" }
            XCTAssertEqual(turn1Images.count, 7)
            let turn1Texts = turn1Content.compactMap { $0["text"] as? String }
            XCTAssertTrue(turn1Texts.contains(where: { $0.contains("Omitted 1 extra image") }))

            // Turn 2 (assistant)
            XCTAssertEqual(messages[1]["role"] as? String, "assistant")

            // Turn 3 (latest turn): 1 image attached, must be preserved!
            let turn3Content = try XCTUnwrap(messages[2]["content"] as? [[String: Any]])
            let turn3Images = turn3Content.filter { $0["type"] as? String == "image_url" }
            XCTAssertEqual(turn3Images.count, 1)
            let turn3Texts = turn3Content.compactMap { $0["text"] as? String }
            XCTAssertFalse(turn3Texts.contains(where: { $0.contains("Omitted") }))

            // Total images across the request must equal exactly 8 (7 + 1)
            let totalImages = turn1Images.count + turn3Images.count
            XCTAssertEqual(totalImages, RunInfraVisionSupport.maxImagesPerRequest)

            return try runinfraOKResponse(url: request.url!)
        }

        let historicalImages = (0..<8).map { _ in
            ContentPart.image(ImageContent(mimeType: "image/png", data: Data([0x89, 0x50]), url: nil))
        }
        let latestImage = ContentPart.image(ImageContent(mimeType: "image/png", data: Data([0x89, 0x51]), url: nil))

        let adapter = RunInfraAdapter(
            providerConfig: DefaultProviderSeeds.runinfra,
            apiKey: "test-key",
            networkManager: networkManager
        )
        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.text("first turn")] + historicalImages),
                Message(role: .assistant, content: [.text("received")]),
                Message(role: .user, content: [.text("latest turn"), latestImage]),
            ],
            modelID: "qwen3-8-27b",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )
        for try await _ in stream {}
    }

    func testFlashNextOmitsImageParts() async throws {
        let (configuration, protocolType) = runinfraMakeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(runinfraRequestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "qwen3-8-flash-next")
            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            let content = try XCTUnwrap(messages.first?["content"] as? String)
            XCTAssertTrue(content.contains("Image attachment omitted"))
            return try runinfraOKResponse(url: request.url!)
        }

        let adapter = RunInfraAdapter(
            providerConfig: DefaultProviderSeeds.runinfra,
            apiKey: "test-key",
            networkManager: networkManager
        )
        let stream = try await adapter.sendMessage(
            messages: [
                Message(
                    role: .user,
                    content: [
                        .text("describe"),
                        .image(ImageContent(mimeType: "image/png", data: Data([0x89, 0x50]), url: nil)),
                    ]
                )
            ],
            modelID: "qwen3-8-flash-next",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )
        for try await _ in stream {}
    }

    func testFetchModelsOverlaysLiveContextWindow() async throws {
        let (configuration, protocolType) = runinfraMakeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.runinfra.ai/v1/models")
            let payload: [String: Any] = [
                "object": "list",
                "data": [
                    [
                        "id": "deepseek-v4-flash",
                        "object": "model",
                        "context_window": 1_048_576,
                        "context_length": 1_048_576,
                        "max_output_tokens": 1_048_576,
                    ],
                    [
                        "id": "workspace-custom-deploy",
                        "object": "model",
                        "context_window": 64_000,
                        "max_output_tokens": 8_192,
                    ],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let adapter = RunInfraAdapter(
            providerConfig: DefaultProviderSeeds.runinfra,
            apiKey: "test-key",
            networkManager: networkManager
        )
        let models = try await adapter.fetchAvailableModels()
        XCTAssertEqual(models.count, 2)

        let flash = try XCTUnwrap(models.first(where: { $0.id == "deepseek-v4-flash" }))
        XCTAssertEqual(flash.name, "DeepSeek V4 Flash")
        XCTAssertEqual(flash.contextWindow, 1_048_576)
        XCTAssertEqual(flash.maxOutputTokens, 32_768)
        XCTAssertTrue(flash.capabilities.contains(.reasoning))

        let custom = try XCTUnwrap(models.first(where: { $0.id == "workspace-custom-deploy" }))
        XCTAssertEqual(custom.contextWindow, 64_000)
        XCTAssertEqual(custom.maxOutputTokens, 8_192)
        XCTAssertEqual(custom.capabilities, [.streaming, .toolCalling])
        XCTAssertNil(custom.reasoningConfig)
    }

    func testNormalizesBareHostBaseURL() async {
        let config = ProviderConfig(
            id: "runinfra",
            name: "RunInfra",
            type: .runinfra,
            baseURL: "https://api.runinfra.ai"
        )
        let adapter = RunInfraAdapter(providerConfig: config, apiKey: "test-key")
        let baseURL = await adapter.baseURL
        XCTAssertEqual(baseURL, "https://api.runinfra.ai/v1")
    }
}

private final class RunInfraMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = RunInfraMockURLProtocol.requestHandler else {
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

private func runinfraMakeMockedSessionConfiguration() -> (URLSessionConfiguration, RunInfraMockURLProtocol.Type) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [RunInfraMockURLProtocol.self]
    RunInfraMockURLProtocol.requestHandler = nil
    return (config, RunInfraMockURLProtocol.self)
}

private func runinfraRequestBodyData(_ request: URLRequest) -> Data? {
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
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data
}

private func runinfraOKResponse(url: URL) throws -> (HTTPURLResponse, Data) {
    let response: [String: Any] = [
        "id": "chatcmpl-runinfra",
        "choices": [
            [
                "message": [
                    "role": "assistant",
                    "content": "OK",
                    "reasoning": "think",
                ],
                "finish_reason": "stop",
            ]
        ],
    ]
    let data = try JSONSerialization.data(withJSONObject: response)
    return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
}
