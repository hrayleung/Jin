import XCTest
@testable import Jin

final class November10ModelSupportTests: XCTestCase {
    private struct ExpectedModel {
        let provider: ProviderType
        let id: String
        let context: Int
        let output: Int
        let efforts: [ReasoningEffort]?
        var canDisable = false
    }

    private let claudeEfforts: [ReasoningEffort] = [.low, .medium, .high, .xhigh, .max]
    private let emberEfforts: [ReasoningEffort] = [.minimal, .low, .medium, .high, .xhigh, .max]

    private var models: [ExpectedModel] {
        [
            .init(provider: .anthropic, id: "claude-fable-5-2", context: 1_000_000, output: 128_000, efforts: claudeEfforts),
            .init(provider: .anthropic, id: "claude-mythos-5-2", context: 1_000_000, output: 128_000, efforts: claudeEfforts),
            .init(provider: .claudeManagedAgents, id: "claude-fable-5-2", context: 1_000_000, output: 128_000, efforts: claudeEfforts),
            .init(provider: .claudeManagedAgents, id: "claude-mythos-5-2", context: 1_000_000, output: 128_000, efforts: claudeEfforts),
            .init(provider: .meta, id: "muse-ember-1.0", context: 1_048_576, output: 524_288, efforts: emberEfforts),
            .init(provider: .runinfra, id: "step-5-preview", context: 1_048_576, output: 1_048_576, efforts: nil),
            .init(provider: .runinfra, id: "stepfun-ai/Step-5-Preview", context: 1_048_576, output: 1_048_576, efforts: nil),
            .init(provider: .openrouter, id: "thinkingmachines/inkling-2-small:free", context: 1_048_576, output: 131_072,
                  efforts: [.minimal, .low, .medium, .high, .max]),
            .init(provider: .openrouter, id: "anthropic/claude-fable-5.2", context: 1_000_000, output: 128_000, efforts: claudeEfforts),
            .init(provider: .openrouter, id: "meta/muse-ember", context: 1_048_576, output: 943_718, efforts: emberEfforts),
            .init(provider: .openrouter, id: "liquid/lfm-3-1.7b", context: 262_144, output: 8_192, efforts: nil),
            .init(provider: .openrouter, id: "liquid/lfm-3-1.7b:free", context: 262_144, output: 8_192, efforts: nil),
            .init(provider: .vercelAIGateway, id: "anthropic/claude-fable-5.2", context: 1_000_000, output: 128_000, efforts: claudeEfforts),
            .init(provider: .vercelAIGateway, id: "anthropic/claude-fable-5.2-fast", context: 1_000_000, output: 128_000, efforts: claudeEfforts),
            .init(provider: .vercelAIGateway, id: "deepseek/deepseek-v4.1-flash-1017-ultrafast", context: 1_048_576,
                  output: 1_048_576, efforts: [.none, .low, .high, .max], canDisable: true),
            .init(provider: .vercelAIGateway, id: "humansand/ampersand-v0.1", context: 1_000_000, output: 32_768,
                  efforts: [.low, .medium, .high, .max]),
            .init(provider: .vercelAIGateway, id: "meta/muse-ember", context: 1_048_576, output: 1_048_576, efforts: emberEfforts),
            .init(provider: .router, id: "claude-fable-5-2", context: 1_000_000, output: 128_000, efforts: claudeEfforts),
            .init(provider: .router, id: "muse-ember-1.0", context: 1_048_576, output: 524_288, efforts: emberEfforts),
            .init(provider: .gemini, id: "gemini-omni-1.2-flash", context: 131_072, output: 65_536, efforts: nil, canDisable: true),
        ]
    }

    func testExactMetadataAndLegacyRowsAcquireVerifiedHostLimits() {
        for expected in models {
            let model = ModelCatalog.modelInfo(for: expected.id, provider: expected.provider)
            XCTAssertEqual(model.contextWindow, expected.context, expected.id)
            XCTAssertEqual(model.maxOutputTokens, expected.output, expected.id)
            XCTAssertEqual(model.reasoningConfig?.supportedEfforts, expected.efforts, expected.id)
            XCTAssertTrue(JinModelSupport.isFullySupported(providerType: expected.provider, modelID: expected.id))

            let legacy = ModelInfo(id: expected.id, name: "Saved", capabilities: [.streaming],
                                   contextWindow: 128_000, maxOutputTokens: 4_096)
            let resolved = ModelSettingsResolver.resolve(model: legacy, providerType: expected.provider)
            XCTAssertEqual(resolved.contextWindow, expected.context, expected.id)
            XCTAssertEqual(resolved.maxOutputTokens, expected.output, expected.id)
            XCTAssertEqual(resolved.capabilities, model.capabilities, expected.id)
            XCTAssertEqual(resolved.reasoningConfig, model.reasoningConfig, expected.id)
            XCTAssertEqual(resolved.reasoningCanDisable, expected.canDisable, expected.id)
            if let efforts = expected.efforts {
                XCTAssertEqual(ModelCapabilityRegistry.supportedReasoningEfforts(for: expected.provider, modelID: expected.id),
                               efforts, expected.id)
            }
            XCTAssertFalse(ModelCatalog.isFullySupported(modelID: expected.id + "-custom", provider: expected.provider))
        }
        XCTAssertTrue(ModelCatalog.seededModels(for: .anthropic).contains { $0.id == "claude-fable-5-2" })
        XCTAssertTrue(ModelCatalog.seededModels(for: .meta).contains { $0.id == "muse-ember-1.0" })
        XCTAssertTrue(ModelCatalog.seededModels(for: .runinfra).contains { $0.id == "step-5-preview" })
        XCTAssertNil(ModelCatalog.entry(for: "step-5-preview", provider: .runinfra)?.reasoningConfig)
    }

    func testModalitiesAndCapabilitiesRemainProviderSpecific() {
        let native = ModelCatalog.modelInfo(for: "muse-ember-1.0", provider: .meta)
        XCTAssertTrue(native.capabilities.isSuperset(of: [.vision, .audio, .videoInput, .nativePDF, .toolCalling, .promptCaching]))
        XCTAssertEqual(native.reasoningConfig?.defaultEffort, .max)
        let hosted = ModelCatalog.modelInfo(for: "meta/muse-ember", provider: .openrouter)
        XCTAssertTrue(hosted.capabilities.isSuperset(of: [.vision, .audio]))
        XCTAssertFalse(hosted.capabilities.contains(.videoInput))
        let vercel = ModelCatalog.modelInfo(for: "meta/muse-ember", provider: .vercelAIGateway)
        XCTAssertTrue(vercel.capabilities.contains(.vision))
        XCTAssertTrue(vercel.capabilities.intersection([.audio, .videoInput, .nativePDF]).isEmpty)
        XCTAssertNil(vercel.reasoningConfig?.defaultEffort)
        for id in ["claude-fable-5-2", "claude-mythos-5-2"] {
            XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: id))
            XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(for: .anthropic, modelID: id))
            XCTAssertTrue(ChatAuxiliaryControlSupport.supportsAnthropicFastModeControl(providerType: .anthropic, modelID: id))
            XCTAssertFalse(ChatAuxiliaryControlSupport.supportsAnthropicFastModeControl(providerType: .claudeManagedAgents, modelID: id))
        }
        XCTAssertFalse(AnthropicModelLimits.supportsAdaptiveThinking(for: "claude-fable-5-2-custom"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(for: .together, modelID: "humansand/ampersand-v0.1"))
        XCTAssertFalse(ModelCapabilityRegistry.isMetaMuseSparkModelID("meta/muse-ember-1.0"))
    }

    func testBlockedRoutesDoNotAcquireFullSupportOrSeeds() {
        let blocked: [(ProviderType, [String])] = [
            (.openai, ["gpt-6-cyber"]), (.openaiWebSocket, ["gpt-6-cyber"]),
            (.cloudflareAIGateway, ["meta/muse-ember-1.0"]),
            (.openrouter, ["anthropic/claude-fable-5.2:batch", "google/gemini-omni-1.2-flash", "openrouter/auto-code"]),
            (.vercelAIGateway, ["anthropic/claude-fable-5.2-batch", "google/gemini-omni-1.2-flash", "nace-ai/drex-v2.0"]),
            (.vertexai, ["claude-fable-5-2", "meta/muse-ember-1.0"]),
            (.deepinfra, ["Lightricks/LTX-2.5-Pro", "nace-ai/drex-max-finance"]),
            (.morphllm, ["morph-dsv41flash-abliterated", "reflex"]),
            (.zyphra, ["zyphra/ZONOS3-Mini", "zyphra/zonos3-mini"]),
        ]
        for (provider, ids) in blocked {
            for id in ids {
                XCTAssertFalse(JinModelSupport.isFullySupported(providerType: provider, modelID: id), id)
                XCTAssertFalse(ModelCatalog.seededModels(for: provider).contains { $0.id == id }, id)
            }
        }
    }

    func testClaude52EnforcesAdaptiveBindingAndSupportsFastMode() async throws {
        let adapter = AnthropicAdapter(providerConfig: config(.anthropic), apiKey: "test-key")
        for id in ["claude-fable-5-2", "claude-mythos-5-2"] {
            for enabled in [true, false] {
                let controls = GenerationControls(temperature: 0.4, topP: 0.7,
                    reasoning: .init(enabled: enabled, effort: .max), anthropicSpeed: .fast,
                    providerSpecific: ["thinking": AnyCodable(["type": "enabled", "budget_tokens": 2048]),
                                       "temperature": AnyCodable(0.2)])
                let request = try await adapter.buildRequest(messages: [], modelID: id, controls: controls, tools: [], streaming: false)
                let body = try json(request)
                let thinking = try XCTUnwrap(body["thinking"] as? [String: Any])
                XCTAssertEqual(thinking["type"] as? String, "adaptive")
                XCTAssertNil(thinking["budget_tokens"])
                XCTAssertEqual((thinking["block_binding"] as? [String: Any])?["prefix_mismatch_behavior"] as? String, "drop_block")
                XCTAssertEqual(body["speed"] as? String, "fast")
                XCTAssertNil(body["temperature"])
                XCTAssertNil(body["top_p"])
                XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "thinking-binding-controls-2026-08-01")
            }
        }
        let older = try await adapter.buildRequest(messages: [], modelID: "claude-fable-5-1", controls: .init(), tools: [], streaming: false)
        XCTAssertNil((try json(older)["thinking"] as? [String: Any])?["block_binding"])
        XCTAssertNil(older.value(forHTTPHeaderField: "anthropic-beta"))
    }

    func testGatewaySamplingAndEffortBandsSurvivePersistedControls() async throws {
        let vercel = OpenAICompatibleAdapter(providerConfig: config(.vercelAIGateway), apiKey: "test-key")
        let controls = GenerationControls(temperature: 0.4, topP: 0.8, reasoning: .init(enabled: false, effort: .none),
            providerSpecific: ["temperature": AnyCodable(0.2), "top_p": AnyCodable(0.5), "top_k": AnyCodable(10)])
        for id in ["anthropic/claude-fable-5.2", "anthropic/claude-fable-5.2-fast"] {
            let body = try json(try await vercel.buildRequest(messages: [], modelID: id, controls: controls, tools: [], streaming: false))
            XCTAssertNil(body["temperature"])
            XCTAssertNil(body["top_p"])
            XCTAssertNil(body["top_k"])
            XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "low")
        }
        for (id, enabled, effort, wire) in [
            ("humansand/ampersand-v0.1", true, ReasoningEffort.xhigh, "max"),
            ("meta/muse-ember", true, .max, "max"),
            ("deepseek/deepseek-v4.1-flash-1017-ultrafast", false, .max, "none"),
        ] {
            let body = try json(try await vercel.buildRequest(messages: [], modelID: id,
                controls: .init(reasoning: .init(enabled: enabled, effort: effort)), tools: [], streaming: false))
            XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, wire, id)
        }
        let router = OpenRouterAdapter(providerConfig: config(.openrouter), apiKey: "test-key")
        let body = try json(try await router.buildRequest(messages: [], modelID: "anthropic/claude-fable-5.2",
            controls: controls, tools: [], streaming: false))
        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["top_p"])
        XCTAssertNil(body["top_k"])
        for id in ["liquid/lfm-3-1.7b", "liquid/lfm-3-1.7b:free"] {
            let body = try json(try await router.buildRequest(messages: [], modelID: id,
                controls: .init(reasoning: .init(enabled: false)), tools: [], streaming: false))
            let reasoning = try XCTUnwrap(body["reasoning"] as? [String: Any])
            XCTAssertEqual(reasoning["enabled"] as? Bool, true)
            XCTAssertNil(reasoning["effort"])
        }
    }

    func testRunInfraStepPreservesVisionWithoutInventingEffortControls() async throws {
        let adapter = RunInfraAdapter(providerConfig: config(.runinfra), apiKey: "test-key")
        for id in ["step-5-preview", "stepfun-ai/Step-5-Preview"] {
            let request = try await adapter.buildRequest(messages: [Message(role: .user, content: [
                .image(ImageContent(mimeType: "image/png", url: URL(string: "https://example.com/image.png")))
            ])], modelID: id, controls: .init(reasoning: .init(enabled: false, effort: .none)), tools: [], streaming: true)
            let body = try json(request)
            XCTAssertNil(body["reasoning"])
            XCTAssertNil(body["reasoning_effort"])
            let content = (body["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]
            XCTAssertEqual(content?.last?["type"] as? String, "image_url")
        }
    }

    func testMetaEmberUsesMaxDefaultAndSerializesMultimodalInput() async throws {
        let adapter = MetaAdapter(providerConfig: config(.meta), apiKey: "test-key")
        let request = try await adapter.buildResponsesRequest(messages: [Message(role: .user, content: [
            .image(ImageContent(mimeType: "image/png", data: Data([1, 2]))),
            .audio(AudioContent(mimeType: "audio/wav", data: Data([1, 2]))),
            .video(VideoContent(mimeType: "video/mp4", data: Data([1, 2]))),
            .file(FileContent(mimeType: "application/pdf", filename: "document.pdf", data: Data([1, 2])))
        ])], modelID: "muse-ember-1.0", controls: .init(reasoning: .init(enabled: true), webSearch: .init(enabled: true)),
            tools: [], streaming: true)
        let body = try json(request)
        XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "max")
        XCTAssertEqual((body["tools"] as? [[String: Any]])?.first?["type"] as? String, "web_search")
        let content = (body["input"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.compactMap { $0["type"] as? String }, ["input_image", "input_file", "input_video", "input_file"])
        XCTAssertTrue((body["include"] as? [String])?.contains("reasoning.encrypted_content") == true)
    }

    func testRampFableOmitsSamplingEvenWhenSavedReasoningIsOff() async throws {
        let adapter = OpenAIAdapter(providerConfig: config(.router), apiKey: "test-key")
        let request = try await adapter.buildRequest(messages: [], modelID: "claude-fable-5-2",
            controls: .init(temperature: 0.4, maxTokens: 100, reasoning: .init(enabled: false)), tools: [], streaming: false)
        let body = try json(request)
        XCTAssertNil(body["temperature"])
        XCTAssertEqual(body["max_output_tokens"] as? Int, 1025)
    }

    func testOmni12VideoControlsAreExactAndUseDocumentedOptions() {
        let id = "gemini-omni-1.2-flash"
        XCTAssertTrue(GoogleVideoGenerationCore.isGeminiAPIVideoGenerationModel(id))
        XCTAssertFalse(GoogleVideoGenerationCore.isOmniFlashModel(id + "-custom"))
        XCTAssertFalse(GoogleVideoGenerationCore.isOmniFlashModel("google/" + id))
        XCTAssertEqual(GoogleVideoGenerationCore.supportedResolutions(for: id), [.res360p, .res720p, .res1080p, .res4k])
        XCTAssertEqual(GoogleVideoGenerationCore.supportedAspectRatios(for: id), [.ratio16x9, .ratio9x16])
        XCTAssertFalse(GoogleVideoGenerationCore.supportsDurationControl(id))
        XCTAssertEqual(ModelSettingsResolver.inferModelType(capabilities: ModelCatalog.modelInfo(for: id, provider: .gemini).capabilities,
                                                          modelID: id), .video)
    }

    private func config(_ provider: ProviderType) -> ProviderConfig {
        ProviderConfig(id: provider.rawValue, name: provider.displayName, type: provider,
                       apiKey: "test-key", baseURL: provider.defaultBaseURL, models: [])
    }

    private func json(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
