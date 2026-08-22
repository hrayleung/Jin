import XCTest
@testable import Jin

/// Router (Ramp) is Responses-only and relabels every upstream model, so the things
/// worth pinning here are the ones a docs-only implementation would have got wrong:
/// the callable IDs, the enforced per-model effort bands, and the two Anthropic wire
/// constraints that only show up when Router translates onto Claude.
final class RouterProviderIntegrationTests: XCTestCase {

    func testProviderTypeDefaults() {
        XCTAssertEqual(ProviderType.router.displayName, "Ramp Router")
        XCTAssertEqual(ProviderType.router.defaultBaseURL, "https://api.router.com/v1")
        XCTAssertEqual(LobeProviderIconCatalog.defaultIconID(for: .router), "Router")
        // Router owns no cache resource and has no upload API at all.
        XCTAssertFalse(ProviderType.router.supportsNativePromptCaching)
        XCTAssertFalse(ProviderType.router.supportsNativePDFUpload)
    }

    func testRouterIsResponsesOnly() {
        // `POST /v1/chat/completions` 404s on Router — the shape must never be
        // downgraded to the chat/completions dialect.
        XCTAssertEqual(
            ModelCapabilityRegistry.requestShape(for: .router, modelID: "claude-opus-5"),
            .openAIResponses
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.requestShape(for: .router, modelID: "accounts/fireworks/models/kimi-k3"),
            .openAIResponses
        )
    }

    func testSeededModelsMatchLiveCatalog() {
        let seeded = ModelCatalog.seededModels(for: .router).map(\.id)
        XCTAssertEqual(seeded.count, 16)
        XCTAssertEqual(seeded, [
            "claude-fable-5",
            "claude-haiku-4-5",
            "claude-opus-5",
            "claude-sonnet-5",
            "gpt-5.4",
            "gpt-5.6-luna",
            "gpt-5.6-sol",
            "gpt-5.6-terra",
            "o3",
            "grok-4.6",
            "accounts/fireworks/models/deepseek-v4-pro",
            "accounts/fireworks/models/glm-5p2",
            "accounts/fireworks/models/gpt-oss-120b",
            "accounts/fireworks/models/kimi-k3",
            "accounts/fireworks/models/minimax-m3",
            "accounts/fireworks/models/qwen3p8-max",
        ])
        for id in seeded {
            XCTAssertTrue(ModelCatalog.isFullySupported(modelID: id, provider: .router), id)
        }
    }

    /// Router's published docs table lists display labels that are *not* callable.
    /// If someone ever "fixes" the catalog from that table, this fails.
    func testDocsTableLabelsAreNotTreatedAsModelIDs() {
        for label in ["opus-5", "sonnet-5", "haiku-4-5", "fable-5", "kimi-k3", "glm-5p2", "deepseek-v4-pro"] {
            XCTAssertFalse(
                ModelCatalog.isFullySupported(modelID: label, provider: .router),
                "\(label) is a display label, not a Router model ID"
            )
        }
    }

    func testCatalogMetadataMatchesLiveLimits() {
        let opus = ModelCatalog.modelInfo(for: "claude-opus-5", provider: .router)
        XCTAssertEqual(opus.name, "Claude Opus 5")
        XCTAssertEqual(opus.contextWindow, 1_000_000)
        XCTAssertEqual(opus.maxOutputTokens, 128_000)
        XCTAssertTrue(opus.capabilities.contains(.vision))
        XCTAssertTrue(opus.capabilities.contains(.reasoning))

        let kimi = ModelCatalog.modelInfo(for: "accounts/fireworks/models/kimi-k3", provider: .router)
        XCTAssertEqual(kimi.contextWindow, 1_048_576)
        XCTAssertEqual(kimi.maxOutputTokens, 1_048_576)
        XCTAssertEqual(kimi.reasoningConfig?.defaultEffort, .medium)

        // Fireworks-served DeepSeek/GLM/MiniMax are text-only on Router.
        for id in [
            "accounts/fireworks/models/deepseek-v4-pro",
            "accounts/fireworks/models/glm-5p2",
            "accounts/fireworks/models/minimax-m3",
        ] {
            XCTAssertFalse(
                ModelCatalog.modelInfo(for: id, provider: .router).capabilities.contains(.vision),
                id
            )
        }
    }

    /// Router enforces these bands — an out-of-band value is `400 Invalid reasoning
    /// effort.`, not a clamp. Every value here came off the live `/v1/models`.
    func testReasoningEffortBandsMatchLiveCatalog() {
        let expected: [String: [ReasoningEffort]] = [
            "claude-opus-5": [.none, .minimal, .low, .medium, .high, .xhigh, .max],
            "claude-sonnet-5": [.none, .minimal, .low, .medium, .high, .xhigh, .max],
            "claude-haiku-4-5": [.none, .minimal, .low, .medium, .high, .xhigh],
            "claude-fable-5": [.minimal, .low, .medium, .high, .xhigh, .max],
            "accounts/fireworks/models/kimi-k3": [.minimal, .low, .medium, .high, .xhigh, .max],
            "accounts/fireworks/models/glm-5p2": [.none, .minimal, .low, .medium, .high, .xhigh, .max],
            "accounts/fireworks/models/gpt-oss-120b": [.minimal, .low, .medium, .high, .xhigh],
            "gpt-5.6-sol": [.none, .low, .medium, .high, .xhigh, .max],
            "gpt-5.5": [.none, .low, .medium, .high, .xhigh],
            "gpt-5.5-pro": [.medium, .high, .xhigh],
            "gpt-5.1": [.none, .low, .medium, .high],
            "gpt-5-mini": [.minimal, .low, .medium, .high],
            "gpt-5-pro": [.high],
            "o3": [.low, .medium, .high],
            "grok-4.6": [.minimal, .low, .medium, .high, .xhigh],
            "grok-4.3": [.none, .minimal, .low, .medium, .high, .xhigh],
        ]
        for (modelID, efforts) in expected {
            XCTAssertEqual(
                ModelCapabilityRegistry.supportedReasoningEfforts(for: .router, modelID: modelID),
                efforts,
                modelID
            )
        }
    }

    /// `supportsOpenAIStyleMaxEffort` falls through to a generic OpenAI allowlist.
    /// Router reuses OpenAI's bare public slugs, so the `.router` arm has to be an
    /// early return — otherwise `gpt-5.5` would inherit `max` it does not accept, and
    /// Router's Kimi/GLM IDs could leak `max` onto neighbouring providers.
    func testMaxEffortAllowlistsAreProviderScoped() {
        for id in ["claude-opus-5", "claude-fable-5", "accounts/fireworks/models/kimi-k3", "gpt-5.6-sol"] {
            XCTAssertTrue(ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(for: .router, modelID: id), id)
        }
        for id in ["gpt-5.5", "gpt-5.4", "gpt-5.1", "o3", "grok-4.6", "claude-haiku-4-5"] {
            XCTAssertFalse(ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(for: .router, modelID: id), id)
            // …and the menu must clamp a stored `.max` down into the real band.
            XCTAssertNotEqual(
                ModelCapabilityRegistry.normalizedReasoningEffort(.max, for: .router, modelID: id),
                .max,
                id
            )
        }
        // Router's IDs must not grant max on other providers, and vice versa.
        for provider in [ProviderType.baseten, .modal, .together, .openai] {
            XCTAssertFalse(
                ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(
                    for: provider,
                    modelID: "accounts/fireworks/models/kimi-k3"
                ),
                "\(provider)"
            )
        }
    }

    func testReasoningCanDisableIsDerivedFromTheBand() {
        // Bands containing `none` are toggleable…
        for id in ["claude-opus-5", "claude-haiku-4-5", "gpt-5.5", "grok-4.3"] {
            XCTAssertTrue(ModelSettingsResolver.defaultReasoningCanDisable(for: .router, modelID: id), id)
        }
        // …bands without it are thinking-always-on.
        for id in ["claude-fable-5", "grok-4.6", "gpt-5-pro", "gpt-5.5-pro", "o3"] {
            XCTAssertFalse(ModelSettingsResolver.defaultReasoningCanDisable(for: .router, modelID: id), id)
        }
    }

    /// `reasoning.supported: true` with an EMPTY efforts array. Any effort value is a
    /// 400, so these must carry no reasoning config at all.
    func testAlwaysReasoningModelsWithNoEffortBandCarryNoConfig() {
        for id in ["grok-4.20-0309-reasoning", "grok-build-0.1"] {
            XCTAssertNil(ModelCatalog.modelInfo(for: id, provider: .router).reasoningConfig, id)
        }
    }

    func testServerSideToolSurfaces() {
        // Web search reaches OpenAI-served models only.
        for id in ["gpt-5.6-sol", "gpt-5.4", "o3", "gpt-4o-mini"] {
            XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .router, modelID: id), id)
        }
        for id in [
            "claude-opus-5",
            "grok-4.6",
            "accounts/fireworks/models/kimi-k3",
            "accounts/fireworks/models/gpt-oss-120b",
        ] {
            XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .router, modelID: id), id)
        }
        // Router exposes neither a code interpreter nor Maps grounding.
        for id in ["gpt-5.6-sol", "claude-opus-5", "accounts/fireworks/models/kimi-k3"] {
            XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .router, modelID: id), id)
            XCTAssertFalse(ModelCapabilityRegistry.supportsGoogleMaps(for: .router, modelID: id), id)
        }
    }

    func testSeedConfigAndAdapterBaseURL() async {
        let config = DefaultProviderSeeds.router
        XCTAssertEqual(config.id, "router")
        XCTAssertEqual(config.name, "Ramp Router")
        XCTAssertEqual(config.type, .router)
        XCTAssertEqual(config.baseURL, "https://api.router.com/v1")
        XCTAssertEqual(config.models.count, 16)
        XCTAssertTrue(DefaultProviderSeeds.allProviders().contains(where: { $0.id == "router" }))
        XCTAssertEqual(ProviderFormSupport.credentialKind(for: .router), .apiKey)

        let adapter = RouterAdapter(providerConfig: config, apiKey: "sk-routgw-test")
        let baseURL = await adapter.baseURL
        XCTAssertEqual(baseURL, "https://api.router.com/v1")
    }

    func testAdapterRestoresV1OnABareHost() async {
        // Router's routes hang off a base that already carries /v1; a user pasting the
        // bare host must still reach /v1/responses rather than 404ing on /responses.
        for host in ["https://api.router.com", "https://api.router.com/"] {
            let config = ProviderConfig(id: "router", name: "Ramp Router", type: .router, baseURL: host)
            let adapter = RouterAdapter(providerConfig: config, apiKey: "sk-routgw-test")
            let baseURL = await adapter.baseURL
            XCTAssertEqual(baseURL, "https://api.router.com/v1", host)
        }
    }

    func testPreferredModelIsOpus5() {
        let models = ModelCatalog.seededModels(for: .router)
        let provider = ProviderConfigEntity(
            id: "router",
            name: "Ramp Router",
            typeRaw: ProviderType.router.rawValue,
            modelsData: try! JSONEncoder().encode(models)
        )
        XCTAssertEqual(
            ChatModelSelectionSupport.preferredModelID(
                in: models,
                providerID: "router",
                providers: [provider],
                geminiPreferredModelOrder: []
            ),
            "claude-opus-5"
        )
    }

    // MARK: - Wire shape

    func testResponsesRequestUsesRouterEndpointAndMinimalWireShape() async throws {
        let (configuration, protocolType) = routerMakeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.router.com/v1/responses")
            let body = try XCTUnwrap(routerRequestBodyData(request))
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

            XCTAssertEqual(root["model"] as? String, "gpt-5.6-sol")
            // Responses dialect, not chat/completions.
            XCTAssertNotNil(root["input"])
            XCTAssertNil(root["messages"])
            XCTAssertEqual(root["max_output_tokens"] as? Int, 4096)
            XCTAssertNil(root["max_tokens"])
            // Nested reasoning object — never a top-level `reasoning_effort`.
            let reasoning = try XCTUnwrap(root["reasoning"] as? [String: Any])
            XCTAssertEqual(reasoning["effort"] as? String, "max")
            XCTAssertNil(root["reasoning_effort"])
            // OpenAI-platform-only fields must stay off: Router rejects unknown input
            // and reports `reasoning.summary.request_parameter_supported: false`.
            XCTAssertNil(reasoning["summary"])
            XCTAssertNil(root["service_tier"])
            XCTAssertNil(root["prompt_cache_key"])
            XCTAssertNil(root["prompt_cache_retention"])

            return (routerOKResponse(for: request), routerMinimalResponseBody())
        }

        let adapter = RouterAdapter(
            providerConfig: DefaultProviderSeeds.router,
            apiKey: "sk-routgw-test",
            networkManager: networkManager
        )
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gpt-5.6-sol",
            controls: GenerationControls(
                maxTokens: 4096,
                reasoning: ReasoningControls(enabled: true, effort: .max)
            ),
            tools: [],
            streaming: false
        )
        for try await _ in stream {}
    }

    /// Live gateway, 2026-08-22: `max_output_tokens: 400` with reasoning on returns
    /// `400 — "Anthropic requires a thinking budget of at least 1024 tokens strictly
    /// below max_output_tokens."`
    func testAnthropicRoutedModelGetsThinkingBudgetHeadroom() async throws {
        let (configuration, protocolType) = routerMakeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(routerRequestBodyData(request))
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let maxOutputTokens = try XCTUnwrap(root["max_output_tokens"] as? Int)
            XCTAssertGreaterThan(maxOutputTokens, 1024)
            XCTAssertEqual(maxOutputTokens, RouterRequestSupport.minimumMaxOutputTokensWithReasoning)
            return (routerOKResponse(for: request), routerMinimalResponseBody())
        }

        let adapter = RouterAdapter(
            providerConfig: DefaultProviderSeeds.router,
            apiKey: "sk-routgw-test",
            networkManager: networkManager
        )
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "claude-haiku-4-5",
            controls: GenerationControls(
                maxTokens: 400,
                reasoning: ReasoningControls(enabled: true, effort: .low)
            ),
            tools: [],
            streaming: false
        )
        for try await _ in stream {}
    }

    /// Live gateway, 2026-08-22: `400 — "temperature may only be set to 1 when
    /// thinking is enabled."` Jin's generic gate only strips sampling for gpt-5*.
    func testAnthropicRoutedModelOmitsTemperatureWhileThinking() async throws {
        let (configuration, protocolType) = routerMakeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(routerRequestBodyData(request))
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertNil(root["temperature"])
            XCTAssertNil(root["top_p"])
            return (routerOKResponse(for: request), routerMinimalResponseBody())
        }

        let adapter = RouterAdapter(
            providerConfig: DefaultProviderSeeds.router,
            apiKey: "sk-routgw-test",
            networkManager: networkManager
        )
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "claude-opus-5",
            controls: GenerationControls(
                temperature: 0.7,
                maxTokens: 2048,
                reasoning: ReasoningControls(enabled: true, effort: .low)
            ),
            tools: [],
            streaming: false
        )
        for try await _ in stream {}
    }

    /// The same Claude model with thinking off keeps temperature — the guard must be
    /// scoped to the reasoning case, not to the whole provider.
    func testAnthropicRoutedModelKeepsTemperatureWithoutThinking() async throws {
        let (configuration, protocolType) = routerMakeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(routerRequestBodyData(request))
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(root["temperature"] as? Double, 0.7)
            XCTAssertEqual(root["max_output_tokens"] as? Int, 400)
            return (routerOKResponse(for: request), routerMinimalResponseBody())
        }

        let adapter = RouterAdapter(
            providerConfig: DefaultProviderSeeds.router,
            apiKey: "sk-routgw-test",
            networkManager: networkManager
        )
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "claude-opus-5",
            controls: GenerationControls(
                temperature: 0.7,
                maxTokens: 400,
                reasoning: ReasoningControls(enabled: false)
            ),
            tools: [],
            streaming: false
        )
        for try await _ in stream {}
    }

    // MARK: - Model listing

    /// Router's `/v1/models` carries a rich `router` object; the adapter should trust
    /// it over the bundled snapshot so a key always sees its own catalog.
    func testFetchAvailableModelsReadsLiveRouterMetadata() async throws {
        let (configuration, protocolType) = routerMakeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.router.com/v1/models")
            let payload: [String: Any] = [
                "object": "list",
                "data": [
                    [
                        "id": "some-future-model",
                        "object": "model",
                        "owned_by": "anthropic",
                        "router": [
                            "display_name": "Some Future Model",
                            "status": "active",
                            "limits": ["context_window": 2_000_000, "max_output_tokens": 200_000],
                            "capabilities": [
                                "modalities": ["input": ["image", "text"], "output": ["text"]],
                                "tools": ["supported": true],
                                "reasoning": [
                                    "supported": true,
                                    "efforts": [["value": "low"], ["value": "high"]],
                                    "default_effort": "high"
                                ]
                            ]
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (routerOKResponse(for: request), data)
        }

        let adapter = RouterAdapter(
            providerConfig: DefaultProviderSeeds.router,
            apiKey: "sk-routgw-test",
            networkManager: networkManager
        )
        let models = try await adapter.fetchAvailableModels()
        let model = try XCTUnwrap(models.first)
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(model.id, "some-future-model")
        XCTAssertEqual(model.name, "Some Future Model")
        XCTAssertEqual(model.contextWindow, 2_000_000)
        XCTAssertEqual(model.maxOutputTokens, 200_000)
        XCTAssertTrue(model.capabilities.contains(.vision))
        XCTAssertTrue(model.capabilities.contains(.toolCalling))
        XCTAssertTrue(model.capabilities.contains(.reasoning))
        XCTAssertEqual(model.reasoningConfig?.defaultEffort, .high)
    }

    func testFetchAvailableModelsFallsBackToBundledCatalog() async throws {
        let (configuration, protocolType) = routerMakeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                Data("{}".utf8)
            )
        }

        let adapter = RouterAdapter(
            providerConfig: DefaultProviderSeeds.router,
            apiKey: "sk-routgw-test",
            networkManager: networkManager
        )
        let models = try await adapter.fetchAvailableModels()
        XCTAssertEqual(models.count, ModelCatalog.orderedRecords[.router]?.count)
        XCTAssertTrue(models.contains(where: { $0.id == "claude-opus-5" }))
    }
}

// MARK: - Local mock helpers (file-private to avoid colliding with other suites)

private final class RouterMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = RouterMockURLProtocol.requestHandler else {
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

private func routerMakeMockedSessionConfiguration() -> (URLSessionConfiguration, RouterMockURLProtocol.Type) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [RouterMockURLProtocol.self]
    RouterMockURLProtocol.requestHandler = nil
    return (config, RouterMockURLProtocol.self)
}

private func routerOKResponse(for request: URLRequest) -> HTTPURLResponse {
    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
}

/// Smallest buffered OpenAI Response object Jin's Responses decoder accepts.
private func routerMinimalResponseBody() -> Data {
    let response: [String: Any] = [
        "id": "resp_router_test",
        "object": "response",
        "status": "completed",
        "output": [
            [
                "id": "msg_router_test",
                "type": "message",
                "role": "assistant",
                "status": "completed",
                "content": [["type": "output_text", "text": "OK"]]
            ]
        ]
    ]
    return try! JSONSerialization.data(withJSONObject: response)
}

private func routerRequestBodyData(_ request: URLRequest) -> Data? {
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
