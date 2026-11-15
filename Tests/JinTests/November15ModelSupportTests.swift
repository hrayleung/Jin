import XCTest
@testable import Jin

final class November15ModelSupportTests: XCTestCase {
    private struct ExpectedModel {
        let provider: ProviderType
        let id: String
        let context: Int
        let output: Int?
        let efforts: [ReasoningEffort]?
        let defaultEffort: ReasoningEffort?
        var reasoningType: ReasoningConfigType? = .effort
        var canDisable = true
        var isSeeded = false
    }

    private var models: [ExpectedModel] {
        [
            // Gemini API
            .init(
                provider: .gemini,
                id: "gemini-4-hydrogen",
                context: 1_048_576,
                output: 65_536,
                efforts: [.low, .medium, .high, .xhigh],
                defaultEffort: .high,
                isSeeded: true
            ),
            .init(
                provider: .gemini,
                id: "gemini-4-carbon",
                context: 1_048_576,
                output: 65_536,
                efforts: [.low, .medium, .high],
                defaultEffort: .medium,
                isSeeded: true
            ),
            // Vertex AI
            .init(
                provider: .vertexai,
                id: "gemini-4-hydrogen",
                context: 1_048_576,
                output: 65_536,
                efforts: [.low, .medium, .high, .xhigh],
                defaultEffort: .high,
                isSeeded: true
            ),
            .init(
                provider: .vertexai,
                id: "gemini-4-carbon",
                context: 1_048_576,
                output: 65_536,
                efforts: [.low, .medium, .high],
                defaultEffort: .medium,
                isSeeded: true
            ),
            .init(
                provider: .vertexai,
                id: "gemini-4-carbon-cyber-permissive",
                context: 1_048_576,
                output: 65_536,
                efforts: [.low, .medium, .high],
                defaultEffort: .high,
                isSeeded: false
            ),
            // OpenRouter
            .init(
                provider: .openrouter,
                id: "google/gemini-4-hydrogen",
                context: 1_048_576,
                output: 943_718,
                efforts: [.low, .medium, .high, .xhigh],
                defaultEffort: .high,
                canDisable: false
            ),
            .init(
                provider: .openrouter,
                id: "google/gemini-4-carbon",
                context: 1_048_576,
                output: 943_718,
                efforts: [.low, .medium, .high],
                defaultEffort: .medium,
                canDisable: false
            ),
            .init(
                provider: .openrouter,
                id: "thinkingmachines/inkling-2-small",
                context: 1_048_576,
                output: 943_718,
                efforts: [.minimal, .low, .medium, .high, .max],
                defaultEffort: .high,
                canDisable: false
            ),
            .init(
                provider: .openrouter,
                id: "nex-agi/nex-n2.6",
                context: 262_144,
                output: 235_929,
                efforts: [.medium, .high],
                defaultEffort: .high,
                canDisable: false
            ),
            .init(
                provider: .openrouter,
                id: "baidu/ernie-light-dt-1.0-intl",
                context: 1_024_000,
                output: 131_072,
                efforts: [.none, .low, .high, .max],
                defaultEffort: .max,
                canDisable: true
            ),
            .init(
                provider: .openrouter,
                id: "baidu/ernie-5.5-flash-preview:free",
                context: 1_024_000,
                output: 921_600,
                efforts: [.high],
                defaultEffort: .high,
                canDisable: false
            ),
            .init(
                provider: .openrouter,
                id: "inclusionai/ling-3.2-flash:free",
                context: 1_048_576,
                output: 262_144,
                efforts: nil,
                defaultEffort: nil,
                reasoningType: .toggle,
                canDisable: true
            ),
            // Vercel AI Gateway
            .init(
                provider: .vercelAIGateway,
                id: "google/gemini-4-hydrogen",
                context: 1_048_576,
                output: 65_536,
                efforts: [.low, .medium, .high, .xhigh],
                defaultEffort: .high,
                canDisable: false
            ),
            .init(
                provider: .vercelAIGateway,
                id: "google/gemini-4-carbon",
                context: 1_048_576,
                output: 65_536,
                efforts: [.low, .medium, .high],
                defaultEffort: .medium,
                canDisable: false
            ),
            .init(
                provider: .vercelAIGateway,
                id: "thinkingmachines/inkling-2-small",
                context: 1_048_576,
                output: 262_144,
                efforts: [.none, .minimal, .low, .medium, .high, .xhigh, .max],
                defaultEffort: .high
            ),
            .init(
                provider: .vercelAIGateway,
                id: "paperinstruments/ultramarine-1-flash",
                context: 1_048_576,
                output: 131_000,
                efforts: [.low, .high, .max],
                defaultEffort: .high,
                canDisable: false
            ),
            // Cloudflare AI Gateway
            .init(
                provider: .cloudflareAIGateway,
                id: "@cf/thinkingmachines/inkling-2-small",
                context: 1_048_576,
                output: nil,
                efforts: [.none, .minimal, .low, .medium, .high, .max],
                defaultEffort: .high
            ),
            .init(
                provider: .cloudflareAIGateway,
                id: "google-vertex-ai/google/gemini-4-hydrogen",
                context: 1_048_576,
                output: 65_536,
                efforts: [.low, .medium, .high, .xhigh],
                defaultEffort: .high,
                canDisable: false
            ),
            .init(
                provider: .cloudflareAIGateway,
                id: "google-ai-studio/gemini-4-hydrogen",
                context: 1_048_576,
                output: 65_536,
                efforts: [.low, .medium, .high, .xhigh],
                defaultEffort: .high,
                canDisable: false
            ),
            .init(
                provider: .cloudflareAIGateway,
                id: "google-vertex-ai/google/gemini-4-carbon",
                context: 1_048_576,
                output: 65_536,
                efforts: [.low, .medium, .high],
                defaultEffort: .medium,
                canDisable: false
            ),
            .init(
                provider: .cloudflareAIGateway,
                id: "google-ai-studio/gemini-4-carbon",
                context: 1_048_576,
                output: 65_536,
                efforts: [.low, .medium, .high],
                defaultEffort: .medium,
                canDisable: false
            ),
            .init(
                provider: .cloudflareAIGateway,
                id: "anthropic/claude-fable-5.2",
                context: 1_000_000,
                output: 128_000,
                efforts: [.low, .medium, .high, .xhigh, .max],
                defaultEffort: .high,
                canDisable: false
            ),
            .init(
                provider: .cloudflareAIGateway,
                id: "meta/muse-ember-1.0",
                context: 1_048_576,
                output: 524_288,
                efforts: [.minimal, .low, .medium, .high, .xhigh, .max],
                defaultEffort: .max,
                canDisable: false
            ),
            // DeepInfra
            .init(
                provider: .deepinfra,
                id: "thinkingmachines/Inkling-2-Small",
                context: 262_144,
                output: 131_072,
                efforts: [.none, .low, .medium, .high, .xhigh],
                defaultEffort: .high
            ),
            // Together
            .init(
                provider: .together,
                id: "thinkingmachines/Inkling-2-Small",
                context: 1_048_576,
                output: nil,
                efforts: [.low, .medium, .high],
                defaultEffort: .high,
                canDisable: false
            ),
            .init(
                provider: .together,
                id: "elorian-labs/glimpse-1.0",
                context: 262_144,
                output: 131_072,
                efforts: [.low, .medium, .high],
                defaultEffort: .high
            ),
            // Baseten
            .init(
                provider: .baseten,
                id: "moonshotai/Kimi-K3.1-Pro",
                context: 1_000_000,
                output: 1_048_576,
                efforts: [.none, .low, .high, .max],
                defaultEffort: .max,
                isSeeded: true
            ),
            // Modal
            .init(
                provider: .modal,
                id: "thinkingmachines/inkling-2-small",
                context: 1_048_576,
                output: 131_072,
                efforts: [.none, .minimal, .low, .medium, .high, .max],
                defaultEffort: .high
            ),
            // OpenCode Go
            .init(
                provider: .opencodeGo,
                id: "longcat-2.5-free",
                context: 1_000_000,
                output: 262_144,
                efforts: nil,
                defaultEffort: nil,
                reasoningType: nil,
                canDisable: true,
                isSeeded: true
            ),
            // Zyphra
            .init(
                provider: .zyphra,
                id: "zai-org/GLM-5.3-Flash-FP4",
                context: 1_048_576,
                output: 131_072,
                efforts: [.low, .high, .max],
                defaultEffort: .max,
                canDisable: false,
                isSeeded: true
            ),
        ]
    }

    func testExactMetadataSeedFlagsAndLegacyResolution() {
        for expected in models {
            XCTAssertTrue(
                JinModelSupport.isFullySupported(providerType: expected.provider, modelID: expected.id),
                "\(expected.provider.rawValue): \(expected.id)"
            )
            XCTAssertFalse(
                JinModelSupport.isFullySupported(providerType: expected.provider, modelID: expected.id + "-custom"),
                "\(expected.provider.rawValue): \(expected.id)-custom"
            )
            XCTAssertEqual(
                ModelCatalog.seededModels(for: expected.provider).contains(where: { $0.id == expected.id }),
                expected.isSeeded,
                "\(expected.provider.rawValue): \(expected.id)"
            )

            let info = ModelCatalog.modelInfo(for: expected.id, provider: expected.provider)
            XCTAssertEqual(info.contextWindow, expected.context, expected.id)
            XCTAssertEqual(info.maxOutputTokens, expected.output, expected.id)
            XCTAssertEqual(info.reasoningConfig?.type, expected.reasoningType, expected.id)
            XCTAssertEqual(info.reasoningConfig?.defaultEffort, expected.defaultEffort, expected.id)

            let legacy = ModelInfo(
                id: expected.id,
                name: expected.id,
                capabilities: [.streaming, .toolCalling],
                contextWindow: 8_192,
                maxOutputTokens: nil,
                reasoningConfig: nil,
                isEnabled: true
            )
            let resolved = ModelSettingsResolver.resolve(model: legacy, providerType: expected.provider)
            XCTAssertEqual(resolved.contextWindow, expected.context, expected.id)
            XCTAssertEqual(resolved.maxOutputTokens, expected.output, expected.id)
            XCTAssertEqual(resolved.reasoningConfig?.type, expected.reasoningType, expected.id)
            XCTAssertEqual(resolved.reasoningConfig?.defaultEffort, expected.defaultEffort, expected.id)
            XCTAssertEqual(resolved.reasoningCanDisable, expected.canDisable, expected.id)

            if let efforts = expected.efforts {
                XCTAssertEqual(
                    ModelCapabilityRegistry.supportedReasoningEfforts(for: expected.provider, modelID: expected.id),
                    efforts,
                    expected.id
                )
            }
        }

        // Baseten keeps Kimi-K3 first while listing Kimi-K3.1-Pro in preference order.
        XCTAssertEqual(ModelCatalog.seededModels(for: .baseten).first?.id, "moonshotai/Kimi-K3")
        XCTAssertTrue(ChatModelSelectionSupport.preferredBasetenModelOrder.contains("moonshotai/Kimi-K3.1-Pro"))
    }

    func testNonChatBatchEvalAndBlockedRoutesStayUnsupported() {
        let nonFullySupported: [(ProviderType, [String])] = [
            (
                .openrouter,
                [
                    "google/gemini-4-hydrogen:batch",
                    "google/gemini-4-carbon:batch",
                    "anthropic/claude-fable-5.2:batch",
                ]
            ),
            (
                .vercelAIGateway,
                [
                    "anthropic/claude-fable-5.2-batch",
                    "google/gemini-decision-1",
                    "minimax/minimax-h3-image",
                    "minimax/minimax-h3-image-highspeed",
                    "nace-ai/drex-max-finance",
                    "nace-ai/drex-max-v1.1",
                    "nace-ai/drex-v2.0",
                    "parallel/parallel-decisions-fast",
                    "perplexity/pplx-decider-v1.3",
                    "perplexity/pplx-decider-flash-v1.3",
                ]
            ),
        ]

        for (provider, ids) in nonFullySupported {
            for id in ids {
                XCTAssertFalse(JinModelSupport.isFullySupported(providerType: provider, modelID: id), id)
                XCTAssertFalse(ModelCatalog.seededModels(for: provider).contains(where: { $0.id == id }), id)
                XCTAssertNotNil(ModelCatalog.entry(for: id, provider: provider), id)
            }
        }
    }

    func testGemini4CarbonAndHydrogenCapabilitiesAndWireSerialization() async throws {
        for id in ["gemini-4-hydrogen", "gemini-4-carbon"] {
            XCTAssertTrue(GeminiModelConstants.knownModelIDs.contains(id), id)
            XCTAssertTrue(GeminiModelConstants.gemini4ModelIDs.contains(id), id)
            XCTAssertTrue(GeminiModelConstants.nativePDFModelIDs.contains(id), id)
            let (hasAudioInput, isPreferred) = await MainActor.run {
                (
                    ChatView.geminiAudioInputModelIDs.contains(id),
                    ChatView.geminiPreferredModelOrder.contains(id)
                )
            }
            XCTAssertTrue(hasAudioInput, id)
            XCTAssertTrue(isPreferred, id)
            XCTAssertFalse(GeminiModelConstants.supportsCustomSamplingParameters(id), id)

            for provider in [ProviderType.gemini, .vertexai] {
                XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: provider, modelID: id), "\(provider.rawValue): \(id)")
                XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: provider, modelID: id), "\(provider.rawValue): \(id)")
                XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: provider, modelID: id), "\(provider.rawValue): \(id)")
            }
            XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "google/\(id)"), id)
        }

        // Vertex Cyber Permissive Carbon
        let cyber = "gemini-4-carbon-cyber-permissive"
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: cyber))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: cyber))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: cyber))
        XCTAssertTrue(VertexAIModelSupport().knownModels.contains(where: { $0.id == cyber }))

        // Gemini native generationConfig: XHIGH only for Hydrogen; MINIMAL / Off fold to LOW; custom sampling omitted.
        let xhighConfig = GeminiRequestSupport.generationConfig(
            controls: GenerationControls(temperature: 0.5, topP: 0.8, reasoning: ReasoningControls(enabled: true, effort: .xhigh)),
            modelID: "gemini-4-hydrogen"
        )
        XCTAssertNil(xhighConfig["temperature"])
        XCTAssertNil(xhighConfig["topP"])
        let hydrogenThinking = try XCTUnwrap(xhighConfig["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(hydrogenThinking["thinkingLevel"] as? String, "XHIGH")

        let highOnHydrogen = GeminiRequestSupport.generationConfig(
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .high)),
            modelID: "gemini-4-hydrogen"
        )
        XCTAssertEqual((highOnHydrogen["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String, "HIGH")

        let disabledHydrogen = GeminiRequestSupport.generationConfig(
            controls: GenerationControls(reasoning: ReasoningControls(enabled: false)),
            modelID: "gemini-4-hydrogen"
        )
        XCTAssertEqual((disabledHydrogen["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String, "LOW")

        let carbonXHighClamped = GeminiRequestSupport.generationConfig(
            controls: GenerationControls(temperature: 0.4, reasoning: ReasoningControls(enabled: true, effort: .xhigh)),
            modelID: "gemini-4-carbon"
        )
        XCTAssertNil(carbonXHighClamped["temperature"])
        XCTAssertEqual((carbonXHighClamped["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String, "HIGH")

        // Vertex AI generationConfig
        let builder = VertexAIRequestBuilder(
            providerConfig: config(.vertexai),
            serviceAccountJSON: localVertexCredentials(),
            modelSupport: VertexAIModelSupport()
        )
        let vertexHydrogenXHigh = builder.makeGenerationConfig(
            GenerationControls(temperature: 0.4, reasoning: ReasoningControls(enabled: true, effort: .xhigh)),
            modelID: "gemini-4-hydrogen"
        )
        XCTAssertNil(vertexHydrogenXHigh["temperature"])
        XCTAssertEqual((vertexHydrogenXHigh["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String, "XHIGH")

        let vertexCarbonMaxClamped = builder.makeGenerationConfig(
            GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .max)),
            modelID: "gemini-4-carbon"
        )
        XCTAssertEqual((vertexCarbonMaxClamped["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String, "HIGH")

        // Gateway proxies keep OpenAI-compatible effort mapping (xhigh for Hydrogen, high for Carbon) and omit sampling.
        for (provider, id) in [
            (ProviderType.vercelAIGateway, "google/gemini-4-hydrogen"),
            (.cloudflareAIGateway, "google-vertex-ai/google/gemini-4-hydrogen"),
            (.cloudflareAIGateway, "google-ai-studio/gemini-4-hydrogen"),
        ] {
            let adapter = OpenAICompatibleAdapter(providerConfig: config(provider), apiKey: "test-key")
            let body = try json(
                try await adapter.buildRequest(
                    messages: [],
                    modelID: id,
                    controls: GenerationControls(temperature: 0.6, topP: 0.9, reasoning: ReasoningControls(enabled: true, effort: .max)),
                    tools: [],
                    streaming: false
                )
            )
            XCTAssertNil(body["temperature"], id)
            XCTAssertNil(body["top_p"], id)
            XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "xhigh", id)
        }
    }

    func testOpenRouterSamplingAndMandatoryReasoningPolicies() async throws {
        let router = OpenRouterAdapter(providerConfig: config(.openrouter), apiKey: "test-key")
        let samplingControls = GenerationControls(
            temperature: 0.3,
            topP: 0.85,
            reasoning: ReasoningControls(enabled: false, effort: ReasoningEffort.none)
        )

        // Gemini 4 suppresses custom sampling parameters while clamping Off to its lowest thinking effort.
        for (id, expectedFallbackEffort) in [
            ("google/gemini-4-carbon", "low"),
            ("google/gemini-4-hydrogen", "low"),
        ] {
            let body = try json(
                try await router.buildRequest(messages: [], modelID: id, controls: samplingControls, tools: [], streaming: false)
            )
            XCTAssertNil(body["temperature"], id)
            XCTAssertNil(body["top_p"], id)
            XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, expectedFallbackEffort, id)
            XCTAssertEqual(body["include_reasoning"] as? Bool, true, id)
        }

        // Newly allowed OpenRouter models preserve sampling controls while clamping Off to their lowest effort.
        for (id, expectedFallbackEffort) in [
            ("thinkingmachines/inkling-2-small", "minimal"),
            ("nex-agi/nex-n2.6", "medium"),
            ("baidu/ernie-5.5-flash-preview:free", "high"),
        ] {
            let body = try json(
                try await router.buildRequest(messages: [], modelID: id, controls: samplingControls, tools: [], streaming: false)
            )
            XCTAssertEqual(body["temperature"] as? Double, 0.3, id)
            XCTAssertEqual(body["top_p"] as? Double, 0.85, id)
            XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, expectedFallbackEffort, id)
            XCTAssertEqual(body["include_reasoning"] as? Bool, true, id)
        }

        // Batch Fable 5.2 keeps sampling suppressed.
        let batchFable = try json(
            try await router.buildRequest(
                messages: [],
                modelID: "anthropic/claude-fable-5.2:batch",
                controls: samplingControls,
                tools: [],
                streaming: false
            )
        )
        XCTAssertNil(batchFable["temperature"])
        XCTAssertNil(batchFable["top_p"])

        // Optional ERNIE Light DT allows effort "none" and "max".
        let ernieOff = try json(
            try await router.buildRequest(
                messages: [],
                modelID: "baidu/ernie-light-dt-1.0-intl",
                controls: GenerationControls(reasoning: ReasoningControls(enabled: false)),
                tools: [],
                streaming: false
            )
        )
        XCTAssertEqual((ernieOff["reasoning"] as? [String: Any])?["effort"] as? String, "none")

        let ernieMax = try json(
            try await router.buildRequest(
                messages: [],
                modelID: "baidu/ernie-light-dt-1.0-intl",
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .max)),
                tools: [],
                streaming: false
            )
        )
        XCTAssertEqual((ernieMax["reasoning"] as? [String: Any])?["effort"] as? String, "max")

        // Toggle-only Ling 3.2 Flash sends boolean `enabled` without `effort`.
        let lingOff = try json(
            try await router.buildRequest(
                messages: [],
                modelID: "inclusionai/ling-3.2-flash:free",
                controls: GenerationControls(reasoning: ReasoningControls(enabled: false)),
                tools: [],
                streaming: false
            )
        )
        XCTAssertEqual((lingOff["reasoning"] as? [String: Any])?["enabled"] as? Bool, false)
        XCTAssertNil((lingOff["reasoning"] as? [String: Any])?["effort"])
    }

    func testBasetenOpenCodeGoZyphraAndGatewayWireShapes() async throws {
        // Baseten Kimi-K3.1-Pro: keeps temperature, omits top_p (even from overrides), supports max & none.
        let baseten = BasetenAdapter(providerConfig: config(.baseten), apiKey: "test-key")
        XCTAssertFalse(ModelCapabilityRegistry.supportsTopP(for: .baseten, modelID: "moonshotai/Kimi-K3.1-Pro"))
        let basetenBody = try json(
            try await baseten.buildRequest(
                messages: [],
                modelID: "moonshotai/Kimi-K3.1-Pro",
                controls: GenerationControls(
                    temperature: 0.7,
                    topP: 0.9,
                    reasoning: ReasoningControls(enabled: true, effort: .max),
                    providerSpecific: ["top_p": AnyCodable(0.5)]
                ),
                tools: [],
                streaming: false
            )
        )
        XCTAssertEqual(basetenBody["temperature"] as? Double, 0.7)
        XCTAssertNil(basetenBody["top_p"])
        XCTAssertEqual(basetenBody["reasoning_effort"] as? String, "max")

        // OpenCode Go longcat-2.5-free: omits temperature and reasoning_effort while preserving vision parts.
        let go = OpenCodeGoAdapter(providerConfig: config(.opencodeGo), apiKey: "test-key")
        let visionMsg = [Message(role: .user, content: [
            .text("Inspect"),
            .image(ImageContent(mimeType: "image/png", data: nil, url: URL(string: "https://example.com/a.png")))
        ])]
        let goBody = try json(
            try await go.buildOpenAIRequest(
                messages: visionMsg,
                modelID: "longcat-2.5-free",
                controls: GenerationControls(temperature: 0.4, reasoning: ReasoningControls(enabled: true, effort: .high)),
                tools: [],
                streaming: false
            )
        )
        XCTAssertNil(goBody["temperature"])
        XCTAssertNil(goBody["reasoning_effort"])
        let parts = (goBody["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]
        XCTAssertEqual(parts?.last?["type"] as? String, "image_url")

        // Zyphra GLM-5.3-Flash-FP4: canonicalizes lowercase ID and maps reasoning effort low/high/max.
        let zyphra = ZyphraAdapter(providerConfig: config(.zyphra), apiKey: "test-key")
        let zyphraBody = try json(
            try await zyphra.buildRequest(
                messages: [],
                modelID: "zai-org/glm-5.3-flash-fp4",
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .max)),
                tools: [],
                streaming: false
            )
        )
        XCTAssertEqual(zyphraBody["model"] as? String, "zai-org/GLM-5.3-Flash-FP4")
        XCTAssertEqual(zyphraBody["reasoning_effort"] as? String, "max")

        // Cloudflare AI Gateway: Inkling 2 Small allows none/max; Fable 5.2 & Muse Ember 1.0 clamp Off to lowest effort.
        let cloudflare = OpenAICompatibleAdapter(providerConfig: config(.cloudflareAIGateway), apiKey: "test-key")
        for (id, enabled, effort, expectedWire) in [
            ("@cf/thinkingmachines/inkling-2-small", false, ReasoningEffort.high, "none"),
            ("@cf/thinkingmachines/inkling-2-small", true, .max, "max"),
            ("anthropic/claude-fable-5.2", false, .none, "low"),
            ("anthropic/claude-fable-5.2", true, .max, "max"),
            ("meta/muse-ember-1.0", false, .none, "minimal"),
            ("meta/muse-ember-1.0", true, .max, "max"),
        ] {
            let body = try json(
                try await cloudflare.buildRequest(
                    messages: [],
                    modelID: id,
                    controls: GenerationControls(reasoning: ReasoningControls(enabled: enabled, effort: effort)),
                    tools: [],
                    streaming: false
                )
            )
            XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, expectedWire, id)
        }

        // Vercel AI Gateway: Ultramarine 1 Flash clamps Off to low; Inkling 2 Small preserves xhigh/max/none.
        let vercel = OpenAICompatibleAdapter(providerConfig: config(.vercelAIGateway), apiKey: "test-key")
        for (id, enabled, effort, expectedWire) in [
            ("paperinstruments/ultramarine-1-flash", false, ReasoningEffort.none, "low"),
            ("paperinstruments/ultramarine-1-flash", true, .max, "max"),
            ("thinkingmachines/inkling-2-small", true, .xhigh, "xhigh"),
            ("thinkingmachines/inkling-2-small", true, .max, "max"),
            ("thinkingmachines/inkling-2-small", false, .high, "none"),
        ] {
            let body = try json(
                try await vercel.buildRequest(
                    messages: [],
                    modelID: id,
                    controls: GenerationControls(reasoning: ReasoningControls(enabled: enabled, effort: effort)),
                    tools: [],
                    streaming: false
                )
            )
            XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, expectedWire, id)
        }
    }

    private func config(_ provider: ProviderType) -> ProviderConfig {
        ProviderConfig(
            id: provider.rawValue,
            name: provider.displayName,
            type: provider,
            apiKey: "test-key",
            baseURL: provider.defaultBaseURL,
            models: []
        )
    }

    private func json(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func localVertexCredentials() -> ServiceAccountCredentials {
        ServiceAccountCredentials(
            type: "service_account",
            projectID: "project",
            privateKeyID: "key-id",
            privateKey: "unused-for-generation-config",
            clientEmail: "svc@example.com",
            clientID: "1234567890",
            authURI: "https://accounts.google.com/o/oauth2/auth",
            tokenURI: "https://oauth2.googleapis.com/token",
            authProviderX509CertURL: "https://www.googleapis.com/oauth2/v1/certs",
            clientX509CertURL: "https://www.googleapis.com/robot/v1/metadata/x509/svc%40example.com",
            location: "global"
        )
    }
}
