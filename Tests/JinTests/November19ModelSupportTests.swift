import XCTest
@testable import Jin

final class November19ModelSupportTests: XCTestCase {
    private struct ExpectedModel {
        let provider: ProviderType
        let id: String
        let context: Int
        let output: Int?
        let vision: Bool
        let seeded: Bool
        let efforts: [ReasoningEffort]?
        let canDisable: Bool
        let reasoningType: ReasoningConfigType?

        init(
            _ provider: ProviderType, _ id: String, _ context: Int, _ output: Int?,
            vision: Bool, seeded: Bool, efforts: [ReasoningEffort]? = nil,
            canDisable: Bool = true, toggle: Bool = false
        ) {
            self.provider = provider
            self.id = id
            self.context = context
            self.output = output
            self.vision = vision
            self.seeded = seeded
            self.efforts = efforts
            self.canDisable = canDisable
            self.reasoningType = toggle ? .toggle : (efforts == nil ? nil : .effort)
        }
    }

    private let gatewayModels: [ExpectedModel] = [
        .init(.vercelAIGateway, "google/gemini-4-neon", 1_000_000, 1_000_000,
              vision: true, seeded: false, efforts: [.low, .medium, .high, .xhigh], canDisable: false),
        .init(.openrouter, "google/gemini-4-neon", 1_048_576, 943_718,
              vision: true, seeded: false, efforts: [.low, .medium, .high, .xhigh], canDisable: false),
        .init(.deepinfra, "Qwen/Qwen4-Max", 1_000_000, nil,
              vision: true, seeded: false, toggle: true),
        .init(.together, "Qwen/Qwen4-Max", 1_000_000, nil,
              vision: true, seeded: true),
        .init(.opencodeGo, "hy4-flash-free", 1_048_576, 65_536,
              vision: true, seeded: true, efforts: [.none, .high], canDisable: true),
        .init(.opencodeGo, "qwen4-max", 1_000_000, 262_144,
              vision: true, seeded: true, efforts: [.none, .low, .high, .xhigh], canDisable: true),
        .init(.router, "gpt-6.2-astra", 1_050_000, 128_000,
              vision: true, seeded: false, efforts: [.low, .medium, .high, .xhigh, .max], canDisable: false),
        .init(.router, "gpt-6.2-sol", 1_050_000, 128_000,
              vision: true, seeded: false, efforts: [.low, .medium, .high, .xhigh, .max], canDisable: false),
        .init(.router, "gemini-4-neon", 1_000_000, 65_536,
              vision: true, seeded: false, efforts: [.low, .medium, .high], canDisable: false),
        .init(.databricks, "system.ai.gpt-6-2-astra", 1_050_000, 128_000,
              vision: true, seeded: true, efforts: [.low, .medium, .high, .xhigh, .max], canDisable: false),
        .init(.databricks, "system.ai.gpt-6-2-sol", 1_050_000, 128_000,
              vision: true, seeded: true, efforts: [.low, .medium, .high, .xhigh, .max], canDisable: false),
    ]

    func testGatewayCatalogAndLegacyModelsResolveExactHostMetadata() throws {
        for expected in gatewayModels {
            let provider = expected.provider
            let id = expected.id
            let context = "\(provider): \(id)"
            let added = ModelCatalog.modelInfo(for: id, provider: provider)
            XCTAssertTrue(JinModelSupport.isFullySupported(providerType: provider, modelID: id), context)
            XCTAssertEqual(added.contextWindow, expected.context, context)
            XCTAssertEqual(added.maxOutputTokens, expected.output, context)
            XCTAssertTrue(added.capabilities.contains(.streaming), context)
            XCTAssertEqual(added.capabilities.contains(.vision), expected.vision, context)
            XCTAssertFalse(added.capabilities.contains(.nativePDF), context)

            let legacy = ModelInfo(id: id, name: "Saved model", capabilities: [.streaming],
                                   contextWindow: 128_000, maxOutputTokens: 4_096)
            let resolved = ModelSettingsResolver.resolve(model: legacy, providerType: provider)
            XCTAssertEqual(resolved.contextWindow, expected.context, context)
            XCTAssertEqual(resolved.maxOutputTokens, expected.output ?? legacy.maxOutputTokens, context)
            XCTAssertEqual(resolved.capabilities, added.capabilities, context)
            XCTAssertEqual(resolved.reasoningConfig?.type, expected.reasoningType, context)
            XCTAssertEqual(resolved.reasoningConfig?.supportedEfforts, expected.efforts, context)
            XCTAssertEqual(resolved.reasoningCanDisable, expected.canDisable, context)
            XCTAssertEqual(ModelCatalog.seededModels(for: provider).contains { $0.id == id }, expected.seeded, context)
            XCTAssertFalse(JinModelSupport.isFullySupported(providerType: provider, modelID: id + "-custom"), context)
        }
    }

    func testNativeGPT62ResponsesAndWebSocketRequests() async throws {
        let http = OpenAIAdapter(providerConfig: config(.openai), apiKey: "test-key")
        let websocket = OpenAIWebSocketAdapter(providerConfig: config(.openaiWebSocket), apiKey: "test-key")
        let messages = [
            Message(role: .system, content: [.text("Answer in English.")]),
            Message(role: .user, content: [.text("Hello")]),
        ]
        let controls = GenerationControls(
            temperature: 0.2, topP: 0.5,
            reasoning: .init(enabled: true, effort: .max, mode: .pro),
            textVerbosity: .high,
            webSearch: .init(enabled: true),
            openAIServiceTier: .ultrafast,
            contextCache: .init(mode: .implicit, ttl: .customSeconds(43_200), cacheKey: "prefix"),
            codeExecution: .init(enabled: true),
            providerSpecific: ["prompt_cache_retention": AnyCodable("24h")]
        )

        for id in ["gpt-6.2-astra", "gpt-6.2-sol"] {
            let request = try await http.buildRequest(
                messages: messages, modelID: id, controls: controls, tools: [], streaming: true
            )
            let webSocketBody = try await websocket.buildResponsePayload(
                messages: messages, modelID: id, controls: controls, tools: [], previousResponseID: nil
            )
            for body in [try json(request), webSocketBody] {
                let items = try XCTUnwrap(body["input"] as? [[String: Any]])
                XCTAssertEqual(items.first?["role"] as? String, "developer")
                XCTAssertEqual(body["service_tier"] as? String, "ultrafast")
                XCTAssertEqual(body["prompt_cache_key"] as? String, "prefix")
                XCTAssertEqual((body["prompt_cache_options"] as? [String: String])?["ttl"], "12h")
                XCTAssertNil(body["prompt_cache_retention"])
                XCTAssertNil(body["temperature"])
                XCTAssertNil(body["top_p"])
                XCTAssertEqual((body["reasoning"] as? [String: String])?["effort"], "max")
                XCTAssertEqual((body["reasoning"] as? [String: String])?["mode"], "pro")
                XCTAssertEqual((body["text"] as? [String: String])?["verbosity"], "high")
                let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
                XCTAssertEqual(tools.compactMap { $0["type"] as? String }, ["web_search", "code_interpreter"])
            }
            XCTAssertEqual(OpenAIServiceTier.available(for: id, providerType: .openai),
                           [.defaultTier, .priority, .ultrafast])
            XCTAssertNil(OpenAIServiceTier.selected(in: .init(openAIServiceTier: .flex),
                                                    modelID: id, providerType: .openai))
            XCTAssertEqual(OpenAIServiceTier.available(for: "openai/" + id, providerType: .vercelAIGateway),
                           [.ultrafast])
            XCTAssertTrue(OpenAIServiceTier.available(for: "openai/" + id + "-fast",
                                                      providerType: .vercelAIGateway).isEmpty)
        }
    }

    func testNeonUsesForegroundLimitAndNativeThinkingLevel() async throws {
        let id = "gemini-4-neon"
        for provider: ProviderType in [.gemini, .vertexai] {
            let legacy = ModelInfo(id: id, name: "Neon", contextWindow: 128_000)
            let model = ModelSettingsResolver.resolve(model: legacy, providerType: provider)
            XCTAssertEqual(model.contextWindow, 1_048_576)
            XCTAssertEqual(model.maxOutputTokens, 65_536)
            XCTAssertEqual(model.reasoningConfig?.supportedEfforts, [.low, .medium, .high, .xhigh])
            XCTAssertFalse(model.reasoningCanDisable)
            XCTAssertTrue(model.supportsWebSearch)
            XCTAssertTrue(model.capabilities.isSuperset(of: [.vision, .audio, .videoInput, .nativePDF, .codeExecution]))
            XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: provider, modelID: id))
            XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: provider, modelID: id))
            XCTAssertTrue(ModelCatalog.seededModels(for: provider).contains { $0.id == id })
            XCTAssertEqual(GeminiModelConstants.mapEffortToThinkingLevel(.xhigh, for: provider, modelID: id), "XHIGH")
        }

        let adapter = GeminiAdapter(providerConfig: config(.gemini), apiKey: "test-key")
        let request = try await adapter.buildRequest(
            messages: [Message(role: .system, content: [.text("Be brief.")])],
            modelID: id,
            controls: .init(
                temperature: 0.5, topP: 0.6, reasoning: .init(enabled: true, effort: .xhigh),
                contextCache: .init(mode: .explicit, cachedContentName: "cachedContents/saved")
            ),
            tools: [], streaming: true
        )
        let body = try json(request)
        let generation = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        XCTAssertEqual((generation["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String, "XHIGH")
        XCTAssertNil(generation["temperature"])
        XCTAssertNil(generation["topP"])
        XCTAssertNil(body["cachedContent"])
        XCTAssertNotNil(body["systemInstruction"])
    }

    func testOpenCodeGoRoutesQwen4AndHy4FlashThroughTheirPublishedProtocols() async throws {
        XCTAssertTrue(OpenCodeGoAdapter.usesAnthropicMessagesEndpoint("qwen4-max"))
        XCTAssertFalse(OpenCodeGoAdapter.usesAnthropicMessagesEndpoint("qwen4-max-custom"))
        let messages = AnthropicAdapter(providerConfig: config(.opencodeGo), apiKey: "test-key")
        let chat = OpenCodeGoAdapter(providerConfig: config(.opencodeGo), apiKey: "test-key")
        let controls = GenerationControls(reasoning: .init(enabled: true, effort: .xhigh))
        let qwen = try await messages.buildRequest(
            messages: [], modelID: "qwen4-max", controls: controls, tools: [], streaming: true
        )
        let qwenBody = try json(qwen)
        XCTAssertEqual(qwen.url?.path, "/inference/go/anthropic/v1/messages")
        XCTAssertEqual((qwenBody["output_config"] as? [String: String])?["effort"], "xhigh")
        XCTAssertNil(qwenBody["reasoning_effort"])

        let off = GenerationControls(reasoning: .init(enabled: false))
        let hy4 = try await chat.buildOpenAIRequest(
            messages: [], modelID: "hy4-flash-free", controls: off, tools: [], streaming: true
        )
        XCTAssertEqual(hy4.url?.path, "/inference/go/openai/v1/chat/completions")
        XCTAssertEqual(try json(hy4)["reasoning_effort"] as? String, "none")
    }

    func testDeepInfraQwen4MaxUsesBooleanReasoningControl() async throws {
        let adapter = OpenAICompatibleAdapter(providerConfig: config(.deepinfra), apiKey: "test-key")
        for enabled in [true, false] {
            let request = try await adapter.buildRequest(
                messages: [], modelID: "Qwen/Qwen4-Max", controls: .init(reasoning: .init(enabled: enabled)),
                tools: [], streaming: true
            )
            let body = try json(request)
            XCTAssertEqual(body["reasoning"] as? [String: Bool], ["enabled": enabled])
            XCTAssertNil(body["reasoning_effort"])
        }
    }

    func testSelectingAutoClearsLegacyServiceTier() {
        let legacy = GenerationControls(providerSpecific: ["service_tier": AnyCodable("ultrafast")])
        XCTAssertEqual(OpenAIServiceTier.selected(in: legacy, modelID: "gpt-6.2-astra", providerType: .openai), .ultrafast)
        let automatic = ChatAuxiliaryControlSupport.setOpenAIServiceTier(nil, controls: legacy)
        XCTAssertNil(OpenAIServiceTier.selected(in: automatic, modelID: "gpt-6.2-astra", providerType: .openai))
    }

    func testGPT62CacheLifetimesRoundTripThroughTheEditor() throws {
        let enabled = ContextCacheControls(mode: .implicit, ttl: .hour1)
        let prepared = ChatAuxiliaryControlSupport.prepareContextCacheEditorDraft(
            current: enabled, providerType: .openai,
            supportsContextCacheTTL: true, usesGPT62CacheTTL: true
        )
        XCTAssertEqual(prepared.ttlPreset, .providerDefault)
        for (preset, seconds) in [(ContextCacheTTLPreset.minutes30, 1_800), (.hours12, 43_200)] {
            let saved = try XCTUnwrap(ChatAuxiliaryControlSupport.applyContextCacheDraft(
                draft: enabled, ttlPreset: preset, customTTLDraft: "", minTokensDraft: "",
                supportsContextCacheTTL: true, supportsContextCacheStrategy: false,
                supportsExplicitContextCacheMode: false, providerType: .openai
            ).get())
            XCTAssertEqual(saved.ttl, .customSeconds(seconds))
            XCTAssertEqual(ContextCacheTTLPreset.from(ttl: saved.ttl, usesGPT62CacheTTL: true), preset)
        }
    }

    func testOpenRouterSeedance25FlashUsesVideoRouteAndPublishedControls() async throws {
        let adapter = OpenRouterAdapter(providerConfig: config(.openrouter), apiKey: "test-key")
        let id = "bytedance/seedance-2.5-flash"
        let added = ModelCatalog.modelInfo(for: id, provider: .openrouter)
        XCTAssertEqual(ModelSettingsResolver.resolve(model: added, providerType: .openrouter).modelType, .video)
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: id))
        let request = try await adapter.buildVideoGenerationRequest(
            modelID: id, prompt: "Clouds pass over a lake", images: [],
            controls: .init(openRouterVideoGeneration: .init(
                durationSeconds: -1, aspectRatio: .ratio21x9, resolution: .res1080p,
                generateAudio: true, seed: 12
            ))
        )
        let body = try json(request)
        XCTAssertEqual(request.url?.path, "/api/v1/videos")
        XCTAssertEqual(body["duration"] as? Int, -1)
        XCTAssertEqual(body["aspect_ratio"] as? String, "21:9")
        XCTAssertEqual(body["generate_audio"] as? Bool, true)
        XCTAssertEqual(body["seed"] as? Int, 12)
        XCTAssertNil(body["resolution"])
    }

    private func config(_ provider: ProviderType) -> ProviderConfig {
        ProviderConfig(id: provider.rawValue, name: provider.displayName, type: provider,
                       apiKey: "test-key", baseURL: provider.defaultBaseURL)
    }

    private func json(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
