import XCTest
@testable import Jin

final class November2026ModelSupportTests: XCTestCase {
    private struct ExpectedModel {
        let provider: ProviderType
        let id: String
        let context: Int
        let output: Int?
        let vision: Bool
        let efforts: [ReasoningEffort]?
        let canDisable: Bool
    }

    private let models: [ExpectedModel] = [
        .init(provider: .openrouter, id: "ricursiveai/ripple-65b-preview", context: 1_048_576,
              output: 131_072, vision: false, efforts: nil, canDisable: true),
        .init(provider: .openrouter, id: "tencent/hy4", context: 1_048_576,
              output: 65_536, vision: true, efforts: [.none, .low, .high], canDisable: true),
        .init(provider: .openrouter, id: "stealth/crouton-alpha", context: 1_048_576,
              output: 943_718, vision: true, efforts: [.minimal, .low, .medium, .high, .xhigh, .max], canDisable: false),
        .init(provider: .openrouter, id: "z-ai/glm-5.3-flashx-legal", context: 1_048_576,
              output: 131_072, vision: true, efforts: [.low, .high, .max], canDisable: false),
        .init(provider: .vercelAIGateway, id: "inclusionai/ling-3.1-flash-1019", context: 1_000_000,
              output: 262_144, vision: false, efforts: [.none, .low, .medium, .high], canDisable: true),
        .init(provider: .vercelAIGateway, id: "meituan/longcat-2.5", context: 1_048_576,
              output: 131_072, vision: true, efforts: [.none, .low, .medium, .high], canDisable: true),
        .init(provider: .vercelAIGateway, id: "tencent/hy4", context: 1_024_000,
              output: 64_000, vision: true, efforts: [.none, .high], canDisable: true),
        .init(provider: .vercelAIGateway, id: "zai/glm-5.3-flashx-legal", context: 1_000_000,
              output: 131_072, vision: true, efforts: [.low, .high, .max], canDisable: false),
        .init(provider: .deepinfra, id: "moonshotai/Kimi-K3.1-Pro", context: 1_048_576,
              output: 943_718, vision: true, efforts: nil, canDisable: true),
        .init(provider: .databricks, id: "databricks-kimi-k3-1-pro", context: 1_048_576,
              output: 1_048_576, vision: true, efforts: [.none, .low, .high, .max], canDisable: true),
        .init(provider: .opencodeGo, id: "hy4", context: 1_048_576,
              output: 65_536, vision: true, efforts: [.none, .high], canDisable: true),
        .init(provider: .fireworks, id: "accounts/fireworks/routers/deepseek-v4p1-flash-1017-ultrafast",
              context: 1_048_576, output: nil, vision: true, efforts: [.low, .high, .max], canDisable: true),
    ]

    func testExactMetadataAndLegacyPersistedModelsUseHostSpecifications() {
        for expected in models {
            let model = ModelCatalog.modelInfo(for: expected.id, provider: expected.provider)
            XCTAssertEqual(model.contextWindow, expected.context, expected.id)
            XCTAssertEqual(model.maxOutputTokens, expected.output, expected.id)
            XCTAssertEqual(model.capabilities.contains(.vision), expected.vision, expected.id)
            XCTAssertTrue(model.capabilities.isSuperset(of: [.streaming, .toolCalling]), expected.id)
            XCTAssertFalse(model.capabilities.contains(.videoInput), expected.id)
            XCTAssertFalse(model.capabilities.contains(.nativePDF), expected.id)
            XCTAssertEqual(model.reasoningConfig?.supportedEfforts, expected.efforts, expected.id)
            XCTAssertTrue(JinModelSupport.isFullySupported(providerType: expected.provider, modelID: expected.id))

            // A persisted row from before this catalog update must acquire the verified
            // metadata, even if it previously had guessed limits and no reasoning config.
            let legacy = ModelInfo(id: expected.id, name: "Saved model", capabilities: [.streaming],
                                   contextWindow: 128_000, maxOutputTokens: 4_096)
            let resolved = ModelSettingsResolver.resolve(model: legacy, providerType: expected.provider)
            XCTAssertEqual(resolved.contextWindow, expected.context, expected.id)
            XCTAssertEqual(resolved.maxOutputTokens, expected.output ?? legacy.maxOutputTokens, expected.id)
            XCTAssertEqual(resolved.capabilities, model.capabilities, expected.id)
            XCTAssertEqual(resolved.reasoningConfig, model.reasoningConfig, expected.id)
            XCTAssertEqual(resolved.reasoningCanDisable, expected.canDisable, expected.id)
            if let efforts = expected.efforts {
                XCTAssertEqual(ModelCapabilityRegistry.supportedReasoningEfforts(
                    for: expected.provider, modelID: expected.id), efforts, expected.id)
            }
            XCTAssertFalse(ModelCatalog.isFullySupported(modelID: expected.id + "-custom", provider: expected.provider))
        }
        XCTAssertEqual(ModelCatalog.seededModels(for: .opencodeGo).first?.id, "glm-5.3")
        XCTAssertTrue(ModelCatalog.seededModels(for: .opencodeGo).contains { $0.id == "hy4" })
        XCTAssertFalse(ModelCatalog.isFullySupported(modelID: "z-ai/glm-5.3-flashx-legal", provider: .vercelAIGateway))
        XCTAssertFalse(ModelCatalog.isFullySupported(modelID: "zai/glm-5.3-flashx-legal", provider: .openrouter))
    }

    func testGatewayEffortPoliciesDoNotLeakToOtherProviders() {
        XCTAssertFalse(ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(
            for: .together, modelID: "z-ai/glm-5.3-flashx-legal"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(
            for: .deepinfra, modelID: "zai/glm-5.3-flashx-legal"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(
            for: .vercelAIGateway, modelID: "z-ai/glm-5.3-flashx-legal"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(
            for: .openrouter, modelID: "zai/glm-5.3-flashx-legal"))
    }

    func testUnverifiedAndUnsupportedEndpointsNeverGainFullSupport() throws {
        let blocked: [(ProviderType, [String])] = [
            (.openai, ["gpt-6-rosalind"]),
            (.openaiWebSocket, ["gpt-6-rosalind"]),
            (.vercelAIGateway, ["openai/gpt-image-2.6-flare", "openai/gpt-image-2.6-sunburst", "baseten/joey-1"]),
            (.openrouter, ["cohere/embed-5-pro", "cohere/embed-5-fast", "cohere/rerank-5-pro", "cohere/rerank-5-fast"]),
            (.together, ["moonshotai/Kimi-K3.1-Pro"]),
            (.morphllm, ["morph-kimik31"]),
            (.baseten, ["decision-models/baseten-joey-2b-latest"]),
        ]
        for (provider, ids) in blocked {
            for id in ids {
                let entry = try XCTUnwrap(ModelCatalog.entry(for: id, provider: provider))
                XCTAssertFalse(entry.isFullySupported, "\(provider): \(id)")
                XCTAssertFalse(ModelCatalog.seededModels(for: provider).contains { $0.id == id })
            }
        }
        XCTAssertNil(ModelCatalog.entry(for: "moonshotai/Kimi-K3.1-Pro", provider: .together)?.maxOutputTokens)
        XCTAssertEqual(ModelCatalog.entry(for: "moonshotai/Kimi-K3.1-Pro", provider: .deepinfra)?.reasoningConfig?.type, .toggle)
        XCTAssertEqual(ModelCatalog.entry(for: "moonshotai/Kimi-K3.1-Pro", provider: .deepinfra)?.maxOutputTokens, 943_718)
        XCTAssertEqual(ModelCatalog.entry(for: "morph-kimik31", provider: .morphllm)?.maxOutputTokens, 1_048_576)
    }

    func testHy4GoExplicitlyDisablesReasoningAndKeepsImageInput() async throws {
        let adapter = OpenCodeGoAdapter(providerConfig: config(.opencodeGo), apiKey: "test-key")
        let messages = [Message(role: .user, content: [
            .text("Describe this image"),
            .image(ImageContent(mimeType: "image/png", data: nil, url: URL(string: "https://example.com/image.png")))
        ])]
        for (enabled, effort, wire) in [(false, ReasoningEffort.high, "none"), (true, .none, "none"), (true, .medium, "high")] {
            let request = try await adapter.buildOpenAIRequest(messages: messages, modelID: "hy4",
                controls: GenerationControls(temperature: 0.4, reasoning: .init(enabled: enabled, effort: effort)),
                tools: [], streaming: true)
            let body = try json(request)
            XCTAssertTrue(request.url?.path.hasSuffix("/chat/completions") == true)
            XCTAssertEqual(body["reasoning_effort"] as? String, wire)
            XCTAssertEqual(body["temperature"] as? Double, 0.4)
            let parts = (body["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]
            XCTAssertEqual(parts?.last?["type"] as? String, "image_url")
        }
    }

    func testDeepInfraKimiToggleKeepsServerDefaultWhenEnabled() async throws {
        let adapter = OpenAICompatibleAdapter(providerConfig: config(.deepinfra), apiKey: "test-key")
        for enabled in [true, false] {
            let request = try await adapter.buildRequest(messages: [], modelID: "moonshotai/Kimi-K3.1-Pro",
                controls: GenerationControls(reasoning: .init(enabled: enabled)), tools: [], streaming: false)
            let body = try json(request)
            let reasoning = body["reasoning"] as? [String: Any]
            XCTAssertEqual(reasoning?["enabled"] as? Bool, enabled)
            XCTAssertNil(reasoning?["effort"])
            XCTAssertNil(body["reasoning_effort"])
        }
    }

    func testDatabricksKimiKeepsMaxAndExplicitOff() async throws {
        let adapter = DatabricksAdapter(providerConfig: config(.databricks), apiKey: "test-key")
        for (enabled, effort, wire) in [(true, ReasoningEffort.max, "max"), (false, .max, "none"), (true, .medium, "high")] {
            let request = try await adapter.buildRequest(messages: [], modelID: "databricks-kimi-k3-1-pro",
                controls: GenerationControls(reasoning: .init(enabled: enabled, effort: effort)), tools: [], streaming: false)
            XCTAssertEqual(try json(request)["reasoning_effort"] as? String, wire)
        }
    }

    func testAlwaysOnOpenRouterModelsClampOffToTheirLowestEffort() async throws {
        let adapter = OpenRouterAdapter(providerConfig: config(.openrouter), apiKey: "test-key")
        for (id, wire) in [("stealth/crouton-alpha", "minimal"), ("z-ai/glm-5.3-flashx-legal", "low")] {
            for (enabled, effort, expected) in [(false, ReasoningEffort.none, wire), (true, .max, "max")] {
                let request = try await adapter.buildRequest(messages: [], modelID: id,
                    controls: GenerationControls(reasoning: .init(enabled: enabled, effort: effort)), tools: [], streaming: true)
                let body = try json(request)
                XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, expected)
                XCTAssertEqual(body["include_reasoning"] as? Bool, true)
            }
        }
    }

    func testVercelUsesItsOwnEffortBandsAndAlwaysOnPolicy() async throws {
        let adapter = OpenAICompatibleAdapter(providerConfig: config(.vercelAIGateway), apiKey: "test-key")
        for (id, enabled, effort, wire) in [
            ("tencent/hy4", true, ReasoningEffort.low, "high"),
            ("tencent/hy4", false, .high, "none"),
            ("meituan/longcat-2.5", true, .medium, "medium"),
            ("inclusionai/ling-3.1-flash-1019", true, .max, "high"),
            ("zai/glm-5.3-flashx-legal", false, .none, "low"),
            ("zai/glm-5.3-flashx-legal", true, .max, "max"),
        ] {
            let request = try await adapter.buildRequest(messages: [], modelID: id,
                controls: GenerationControls(reasoning: .init(enabled: enabled, effort: effort)), tools: [], streaming: false)
            let body = try json(request)
            XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, wire, id)
        }
    }

    func testHostSamplingListsKeepTemperatureAndOmitUndocumentedTopP() async throws {
        let controls = GenerationControls(temperature: 0.4, topP: 0.8,
                                          providerSpecific: ["top_p": AnyCodable(0.7)])
        let openRouter = OpenRouterAdapter(providerConfig: config(.openrouter), apiKey: "test-key")
        let request = try await openRouter.buildRequest(messages: [], modelID: "tencent/hy4",
            controls: controls, tools: [], streaming: false)
        XCTAssertEqual(try json(request)["temperature"] as? Double, 0.4)
        XCTAssertNil(try json(request)["top_p"])
        let vercel = OpenAICompatibleAdapter(providerConfig: config(.vercelAIGateway), apiKey: "test-key")
        for id in ["tencent/hy4", "inclusionai/ling-3.1-flash-1019", "meituan/longcat-2.5", "zai/glm-5.3-flashx-legal"] {
            let request = try await vercel.buildRequest(messages: [], modelID: id,
                controls: controls, tools: [], streaming: false)
            XCTAssertEqual(try json(request)["temperature"] as? Double, 0.4, id)
            XCTAssertNil(try json(request)["top_p"], id)
        }
        XCTAssertTrue(ModelCapabilityRegistry.supportsTopP(for: .openrouter, modelID: "meituan/longcat-2.5"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsTopP(for: .openrouter, modelID: "tencent/hy4-preview"))
    }

    func testCroutonAudioIsSerializedWithoutClaimingUnverifiedVideoOrPDF() async throws {
        let model = ModelCatalog.modelInfo(for: "stealth/crouton-alpha", provider: .openrouter)
        XCTAssertTrue(model.capabilities.contains(.audio))
        let adapter = OpenRouterAdapter(providerConfig: config(.openrouter), apiKey: "test-key")
        let audioData = Data([1, 2, 3, 4])
        let request = try await adapter.buildRequest(messages: [Message(role: .user, content: [
            .audio(AudioContent(mimeType: "audio/wav", data: audioData, url: nil))
        ])], modelID: model.id, controls: GenerationControls(), tools: [], streaming: false)
        let parts = (try json(request)["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]
        let audio = parts?.first?["input_audio"] as? [String: Any]
        XCTAssertEqual(parts?.first?["type"] as? String, "input_audio")
        XCTAssertEqual(audio?["data"] as? String, audioData.base64EncodedString())
        XCTAssertEqual(audio?["format"] as? String, "wav")
    }

    func testFireworksUltraFastUsesThinkingEnvelopeAndRejectsPriority() async throws {
        let id = "accounts/fireworks/routers/deepseek-v4p1-flash-1017-ultrafast"
        let adapter = FireworksAdapter(providerConfig: config(.fireworks), apiKey: "test-key")
        for enabled in [false, true] {
            let request = try await adapter.buildRequest(messages: [], modelID: id,
                controls: GenerationControls(reasoning: .init(enabled: enabled, effort: .max),
                                             providerSpecific: ["service_tier": AnyCodable("priority")]),
                tools: [], streaming: false)
            let body = try json(request)
            XCTAssertEqual(body["model"] as? String, id)
            XCTAssertNil(body["service_tier"])
            if enabled {
                XCTAssertEqual(body["reasoning_effort"] as? String, "max")
                XCTAssertNil(body["thinking"])
            } else {
                XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "disabled")
                XCTAssertNil(body["reasoning_effort"])
            }
        }
        XCTAssertFalse(isFireworksDeepSeekV4GAModel(id + "-custom"))
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
