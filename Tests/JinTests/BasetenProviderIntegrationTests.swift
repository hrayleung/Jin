import XCTest
@testable import Jin

final class BasetenProviderIntegrationTests: XCTestCase {

    func testProviderTypeDefaults() {
        XCTAssertEqual(ProviderType.baseten.displayName, "Baseten")
        XCTAssertEqual(ProviderType.baseten.defaultBaseURL, "https://inference.baseten.co/v1")
        XCTAssertEqual(LobeProviderIconCatalog.defaultIconID(for: .baseten), "Baseten")
    }

    func testSeededModelsMatchOfficialCatalog() {
        let seeded = ModelCatalog.seededModels(for: .baseten)
        XCTAssertEqual(seeded.count, 13)
        XCTAssertEqual(seeded.first?.id, "moonshotai/Kimi-K3")

        let expectedIDs = [
            "moonshotai/Kimi-K3",
            "moonshotai/Kimi-K2.7-Code",
            "moonshotai/Kimi-K2.6",
            "thinkingmachines/inkling",
            "thinkingmachines/inkling-small",
            "deepseek-ai/DeepSeek-V4-Pro",
            "deepseek-ai/DeepSeek-V4-Pro-0813",
            "deepseek-ai/DeepSeek-V4-Flash-0731",
            "zai-org/GLM-5.2",
            "zai-org/GLM-5.2-Fast",
            "zai-org/GLM-4.7",
            "nvidia/NVIDIA-Nemotron-3-Ultra-550B-A55B",
            "openai/gpt-oss-120b",
        ]
        XCTAssertEqual(seeded.map(\.id), expectedIDs)

        for id in expectedIDs {
            XCTAssertTrue(ModelCatalog.isFullySupported(modelID: id, provider: .baseten), id)
        }
    }

    func testMercury2AndSID1CatalogSupport() {
        let mercury = ModelCatalog.modelInfo(for: "inception/mercury-2", provider: .baseten)
        XCTAssertEqual(mercury.name, "Mercury 2")
        XCTAssertEqual(mercury.contextWindow, 128_000)
        XCTAssertEqual(mercury.maxOutputTokens, 50_000)
        XCTAssertTrue(mercury.capabilities.contains(.toolCalling))
        XCTAssertTrue(mercury.capabilities.contains(.reasoning))
        XCTAssertFalse(mercury.capabilities.contains(.vision))
        XCTAssertEqual(mercury.reasoningConfig?.type, .effort)
        XCTAssertEqual(mercury.reasoningConfig?.defaultEffort, .high)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "inception/mercury-2", provider: .baseten))
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(
                for: .baseten,
                modelID: "inception/mercury-2"
            ),
            [.none, .low, .medium, .high]
        )
        // Catalog-only — not first-launch seeded.
        XCTAssertFalse(ModelCatalog.seededModels(for: .baseten).contains(where: { $0.id == "inception/mercury-2" }))

        let sid = ModelCatalog.modelInfo(for: "sid/sid-1", provider: .baseten)
        XCTAssertEqual(sid.name, "SID-1")
        XCTAssertEqual(sid.contextWindow, 128_000)
        XCTAssertTrue(sid.capabilities.contains(.streaming))
        XCTAssertTrue(sid.capabilities.contains(.toolCalling))
        XCTAssertFalse(sid.capabilities.contains(.vision))
        XCTAssertFalse(sid.capabilities.contains(.reasoning))
        XCTAssertNil(sid.reasoningConfig)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "sid/sid-1", provider: .baseten))
        XCTAssertFalse(ModelCatalog.seededModels(for: .baseten).contains(where: { $0.id == "sid/sid-1" }))
    }

    func testKimiK3CatalogMetadata() {
        let info = ModelCatalog.modelInfo(for: "moonshotai/Kimi-K3", provider: .baseten)
        XCTAssertEqual(info.name, "Kimi K3")
        XCTAssertEqual(info.contextWindow, 1_048_576)
        XCTAssertEqual(info.maxOutputTokens, 262_144)
        XCTAssertTrue(info.capabilities.contains(.vision))
        XCTAssertTrue(info.capabilities.contains(.reasoning))
        XCTAssertTrue(info.capabilities.contains(.promptCaching))
        XCTAssertEqual(info.reasoningConfig?.type, .effort)
        XCTAssertEqual(info.reasoningConfig?.defaultEffort, .max)

        let efforts = ModelCapabilityRegistry.supportedReasoningEfforts(
            for: .baseten,
            modelID: "moonshotai/Kimi-K3"
        )
        XCTAssertEqual(efforts, [.none, .low, .high, .max])
    }

    func testInklingVisionAudioAndEffortBand() {
        let info = ModelCatalog.modelInfo(for: "thinkingmachines/inkling", provider: .baseten)
        XCTAssertTrue(info.capabilities.contains(.vision))
        XCTAssertTrue(info.capabilities.contains(.audio))
        XCTAssertEqual(info.maxOutputTokens, 32_768)

        let efforts = ModelCapabilityRegistry.supportedReasoningEfforts(
            for: .baseten,
            modelID: "thinkingmachines/inkling"
        )
        XCTAssertEqual(efforts, [.none, .minimal, .low, .medium, .high, .xhigh, .max])
    }

    func testToggleOnlyModelsHaveVisionOnlyOnKimiLine() {
        let k26 = ModelCatalog.modelInfo(for: "moonshotai/Kimi-K2.6", provider: .baseten)
        XCTAssertEqual(k26.reasoningConfig?.type, .toggle)
        XCTAssertTrue(k26.capabilities.contains(.vision))

        let glm47 = ModelCatalog.modelInfo(for: "zai-org/GLM-4.7", provider: .baseten)
        XCTAssertEqual(glm47.reasoningConfig?.type, .toggle)
        XCTAssertFalse(glm47.capabilities.contains(.vision))
    }

    func testSeedConfigAndAdapterBaseURL() async {
        let config = DefaultProviderSeeds.baseten
        XCTAssertEqual(config.type, .baseten)
        XCTAssertEqual(config.baseURL, "https://inference.baseten.co/v1")
        XCTAssertEqual(config.models.first?.id, "moonshotai/Kimi-K3")
        XCTAssertEqual(config.models.count, 13)

        let adapter = BasetenAdapter(providerConfig: config, apiKey: "test-key")
        let baseURL = await adapter.baseURL
        XCTAssertEqual(baseURL, "https://inference.baseten.co/v1")
    }

    func testPreferredModelIsKimiK3() {
        let models = ModelCatalog.seededModels(for: .baseten)
        for preferredID in ChatModelSelectionSupport.preferredBasetenModelOrder {
            if models.contains(where: { $0.id == preferredID }) {
                XCTAssertEqual(preferredID, "moonshotai/Kimi-K3")
                return
            }
        }
        XCTFail("Expected Kimi K3 in preferred Baseten order")
    }

    func testMaxEffortAllowlistsAreProviderScoped() {
        // Baseten-only IDs must not enable max effort on other providers.
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(
                for: .baseten,
                modelID: "thinkingmachines/inkling"
            )
        )
        XCTAssertFalse(
            ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(
                for: .together,
                modelID: "thinkingmachines/inkling"
            )
        )
        XCTAssertFalse(
            ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(
                for: .together,
                modelID: "deepseek-ai/DeepSeek-V4-Pro"
            )
        )
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(
                for: .together,
                modelID: "moonshotai/Kimi-K3"
            )
        )
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(
                for: .baseten,
                modelID: "moonshotai/Kimi-K3"
            )
        )
    }

    func testKimiK3HostedCatalogsOnExistingProviders() {
        let together = ModelCatalog.modelInfo(for: "moonshotai/Kimi-K3", provider: .together)
        XCTAssertEqual(together.contextWindow, 1_048_576)
        XCTAssertEqual(together.maxOutputTokens, 131_072)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "moonshotai/Kimi-K3", provider: .together))
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .together, modelID: "moonshotai/Kimi-K3"),
            [.low, .high, .max]
        )

        let deepInfra = ModelCatalog.modelInfo(for: "moonshotai/Kimi-K3", provider: .deepinfra)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "moonshotai/Kimi-K3", provider: .deepinfra))
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .deepinfra, modelID: "moonshotai/Kimi-K3"),
            [.low, .high, .max]
        )

        let fireworks = ModelCatalog.modelInfo(
            for: "accounts/fireworks/models/kimi-k3",
            provider: .fireworks
        )
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "accounts/fireworks/models/kimi-k3", provider: .fireworks))
        XCTAssertEqual(fireworks.contextWindow, 1_048_576)

        let vercelFast = ModelCatalog.modelInfo(for: "moonshotai/kimi-k3-fast", provider: .vercelAIGateway)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "moonshotai/kimi-k3-fast", provider: .vercelAIGateway))
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(
                for: .vercelAIGateway,
                modelID: "moonshotai/kimi-k3-fast"
            ),
            [.low, .high, .max]
        )

        let cloudflare = ModelCatalog.modelInfo(for: "moonshotai/kimi-k3", provider: .cloudflareAIGateway)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "moonshotai/kimi-k3", provider: .cloudflareAIGateway))
        XCTAssertEqual(cloudflare.contextWindow, 1_048_576)
        XCTAssertNil(cloudflare.reasoningConfig)
    }

    func testKimiK3RequestSendsReasoningEffortMax() async throws {
        let (configuration, protocolType) = basetenMakeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let providerConfig = ProviderConfig(
            id: "baseten",
            name: "Baseten",
            type: .baseten,
            apiKey: "ignored",
            baseURL: "https://inference.baseten.co/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://inference.baseten.co/v1/chat/completions")
            let body = try XCTUnwrap(basetenRequestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "moonshotai/Kimi-K3")
            XCTAssertEqual(root["reasoning_effort"] as? String, "max")
            XCTAssertNil(root["chat_template_args"])
            XCTAssertNil(root["chat_template_kwargs"])

            let response: [String: Any] = [
                "id": "cmpl_bt_k3",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK",
                            "reasoning_content": "think"
                        ],
                        "finish_reason": "stop"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = BasetenAdapter(
            providerConfig: providerConfig,
            apiKey: "test-key",
            networkManager: networkManager
        )
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "moonshotai/Kimi-K3",
            controls: GenerationControls(
                reasoning: ReasoningControls(enabled: true, effort: .max)
            ),
            tools: [],
            streaming: false
        )

        var sawThinking = false
        for try await event in stream {
            if case .thinkingDelta = event {
                sawThinking = true
            }
        }
        XCTAssertTrue(sawThinking)
    }

    func testKimiK26ToggleUsesChatTemplateArgs() async throws {
        let (configuration, protocolType) = basetenMakeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let providerConfig = ProviderConfig(
            id: "baseten",
            name: "Baseten",
            type: .baseten,
            apiKey: "ignored",
            baseURL: "https://inference.baseten.co/v1"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(basetenRequestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "moonshotai/Kimi-K2.6")
            let args = try XCTUnwrap(root["chat_template_args"] as? [String: Any])
            XCTAssertEqual(args["enable_thinking"] as? Bool, true)
            XCTAssertNil(root["reasoning_effort"])

            let response: [String: Any] = [
                "id": "cmpl_bt_k26",
                "choices": [
                    [
                        "message": ["role": "assistant", "content": "OK"],
                        "finish_reason": "stop"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = BasetenAdapter(
            providerConfig: providerConfig,
            apiKey: "test-key",
            networkManager: networkManager
        )
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "moonshotai/Kimi-K2.6",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true)),
            tools: [],
            streaming: false
        )
        for try await _ in stream {}
    }

    func testInklingDisableUsesReasoningEffortNone() async throws {
        let (configuration, protocolType) = basetenMakeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let providerConfig = ProviderConfig(
            id: "baseten",
            name: "Baseten",
            type: .baseten,
            apiKey: "ignored",
            baseURL: "https://inference.baseten.co/v1"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(basetenRequestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "thinkingmachines/inkling")
            XCTAssertEqual(root["reasoning_effort"] as? String, "none")
            XCTAssertNil(root["chat_template_args"])

            let response: [String: Any] = [
                "id": "cmpl_bt_ink",
                "choices": [
                    [
                        "message": ["role": "assistant", "content": "OK"],
                        "finish_reason": "stop"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = BasetenAdapter(
            providerConfig: providerConfig,
            apiKey: "test-key",
            networkManager: networkManager
        )
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "thinkingmachines/inkling",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: false)),
            tools: [],
            streaming: false
        )
        for try await _ in stream {}
    }

    func testTogetherKimiK3SendsMaxReasoningEffort() async throws {
        let (configuration, protocolType) = basetenMakeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let providerConfig = ProviderConfig(
            id: "together",
            name: "Together AI",
            type: .together,
            apiKey: "ignored",
            baseURL: "https://api.together.xyz/v1",
            models: [
                ModelInfo(
                    id: "moonshotai/Kimi-K3",
                    name: "Kimi K3",
                    capabilities: [.streaming, .toolCalling, .vision, .reasoning],
                    contextWindow: 1_048_576,
                    maxOutputTokens: 131_072,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .max)
                )
            ]
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(basetenRequestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "moonshotai/Kimi-K3")
            XCTAssertEqual(root["reasoning_effort"] as? String, "max")

            let response: [String: Any] = [
                "id": "cmpl_tg_k3",
                "choices": [
                    [
                        "message": ["role": "assistant", "content": "OK"],
                        "finish_reason": "stop"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = TogetherAdapter(
            providerConfig: providerConfig,
            apiKey: "test-key",
            networkManager: networkManager
        )
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "moonshotai/Kimi-K3",
            controls: GenerationControls(
                reasoning: ReasoningControls(enabled: true, effort: .max)
            ),
            tools: [],
            streaming: false
        )
        for try await _ in stream {}
    }

    // MARK: - DeepSeek V4 Pro 0813 / V4 Flash 0731 / Inkling Small / GLM 5.2 Fast fix

    func testDeepSeekV4Pro0813CatalogAndEffort() {
        let info = ModelCatalog.modelInfo(for: "deepseek-ai/DeepSeek-V4-Pro-0813", provider: .baseten)
        XCTAssertEqual(info.name, "DeepSeek V4 Pro 0813")
        XCTAssertEqual(info.contextWindow, 1_048_576)
        XCTAssertEqual(info.maxOutputTokens, 262_144)
        XCTAssertTrue(info.capabilities.contains(.toolCalling))
        XCTAssertTrue(info.capabilities.contains(.reasoning))
        XCTAssertFalse(info.capabilities.contains(.vision))
        XCTAssertEqual(info.reasoningConfig?.type, .effort)
        XCTAssertEqual(info.reasoningConfig?.defaultEffort, .medium)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "deepseek-ai/DeepSeek-V4-Pro-0813", provider: .baseten))

        let efforts = ModelCapabilityRegistry.supportedReasoningEfforts(
            for: .baseten,
            modelID: "deepseek-ai/DeepSeek-V4-Pro-0813"
        )
        XCTAssertEqual(efforts, [.none, .low, .high, .max])
    }

    func testDeepSeekV4FlashCatalogAndEffort() {
        let info = ModelCatalog.modelInfo(for: "deepseek-ai/DeepSeek-V4-Flash-0731", provider: .baseten)
        XCTAssertEqual(info.name, "DeepSeek V4 Flash")
        XCTAssertEqual(info.contextWindow, 1_048_576)
        XCTAssertEqual(info.maxOutputTokens, 384_000)
        XCTAssertTrue(info.capabilities.contains(.toolCalling))
        XCTAssertTrue(info.capabilities.contains(.reasoning))
        XCTAssertFalse(info.capabilities.contains(.vision))
        XCTAssertEqual(info.reasoningConfig?.type, .effort)
        XCTAssertEqual(info.reasoningConfig?.defaultEffort, .high)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "deepseek-ai/DeepSeek-V4-Flash-0731", provider: .baseten))

        let efforts = ModelCapabilityRegistry.supportedReasoningEfforts(
            for: .baseten,
            modelID: "deepseek-ai/DeepSeek-V4-Flash-0731"
        )
        XCTAssertEqual(efforts, [.none, .minimal, .low, .medium, .high, .xhigh, .max])
    }

    func testInklingSmallCatalogAndEffort() {
        let info = ModelCatalog.modelInfo(for: "thinkingmachines/inkling-small", provider: .baseten)
        XCTAssertEqual(info.name, "Inkling Small")
        XCTAssertEqual(info.contextWindow, 1_048_576)
        XCTAssertEqual(info.maxOutputTokens, 32_768)
        XCTAssertTrue(info.capabilities.contains(.vision))
        XCTAssertTrue(info.capabilities.contains(.audio))
        XCTAssertTrue(info.capabilities.contains(.reasoning))
        XCTAssertEqual(info.reasoningConfig?.type, .effort)
        XCTAssertEqual(info.reasoningConfig?.defaultEffort, .high)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "thinkingmachines/inkling-small", provider: .baseten))

        let efforts = ModelCapabilityRegistry.supportedReasoningEfforts(
            for: .baseten,
            modelID: "thinkingmachines/inkling-small"
        )
        XCTAssertEqual(efforts, [.none, .minimal, .low, .medium, .high, .xhigh, .max])
    }

    func testGLM52FastContextWindowCorrected() {
        let info = ModelCatalog.modelInfo(for: "zai-org/GLM-5.2-Fast", provider: .baseten)
        XCTAssertEqual(info.contextWindow, 1_048_576)
    }

    func testNewModelsMaxEffortProviderScoped() {
        // V4 Pro 0813 and V4 Flash should support max effort on Baseten.
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(
                for: .baseten,
                modelID: "deepseek-ai/DeepSeek-V4-Pro-0813"
            )
        )
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(
                for: .baseten,
                modelID: "deepseek-ai/DeepSeek-V4-Flash-0731"
            )
        )
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(
                for: .baseten,
                modelID: "thinkingmachines/inkling-small"
            )
        )
        // Must not bleed to other providers.
        XCTAssertFalse(
            ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(
                for: .together,
                modelID: "deepseek-ai/DeepSeek-V4-Pro-0813"
            )
        )
        XCTAssertFalse(
            ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(
                for: .together,
                modelID: "thinkingmachines/inkling-small"
            )
        )
    }
}

// MARK: - Local mock helpers (file-private to avoid colliding with other suites)

private final class BasetenMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = BasetenMockURLProtocol.requestHandler else {
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

private func basetenMakeMockedSessionConfiguration() -> (URLSessionConfiguration, BasetenMockURLProtocol.Type) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [BasetenMockURLProtocol.self]
    BasetenMockURLProtocol.requestHandler = nil
    return (config, BasetenMockURLProtocol.self)
}

private func basetenRequestBodyData(_ request: URLRequest) -> Data? {
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
        if read < 0 { return nil }
        if read == 0 { break }
        data.append(buffer, count: read)
    }
    return data
}
