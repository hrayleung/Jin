import XCTest
@testable import Jin

/// Census additions verified 2026-11-13 (docs/model-census-2026-11-13.md):
/// Gemini 4 Carbon/Hydrogen (AI Studio + Vertex), gateway copies on
/// OpenRouter / Vercel / Cloudflare / Databricks, and new hosted IDs on
/// Together, Fireworks, Modal, Zyphra, and OpenCode Go.
final class November13ModelSupportTests: XCTestCase {
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
        // OpenRouter — live /api/v1/models, created 2026-11-09..11.
        .init(provider: .openrouter, id: "thinkingmachines/inkling-2-small", context: 1_048_576,
              output: 131_072, vision: true,
              efforts: [.minimal, .low, .medium, .high, .max], canDisable: false),
        .init(provider: .openrouter, id: "google/gemini-4-carbon", context: 1_048_576,
              output: 65_536, vision: true,
              efforts: [.low, .medium, .high], canDisable: false),
        .init(provider: .openrouter, id: "google/gemini-4-hydrogen", context: 1_048_576,
              output: 65_536, vision: true,
              efforts: [.low, .medium, .high, .xhigh], canDisable: false),
        .init(provider: .openrouter, id: "baidu/ernie-5.5-flash-preview:free", context: 1_024_000,
              output: nil, vision: false, efforts: [.high], canDisable: false),
        .init(provider: .openrouter, id: "baidu/ernie-light-dt-1.0-intl", context: 1_024_000,
              output: nil, vision: false,
              efforts: [.none, .low, .high, .max], canDisable: true),
        .init(provider: .openrouter, id: "nex-agi/nex-n2.6", context: 262_144,
              output: nil, vision: true, efforts: [.medium, .high], canDisable: false),
        // Vercel AI Gateway — live /v1/models + changelog, released 2026-11-10..12.
        .init(provider: .vercelAIGateway, id: "thinkingmachines/inkling-2-small", context: 1_048_576,
              output: 262_144, vision: true,
              efforts: [.none, .low, .medium, .high], canDisable: true),
        .init(provider: .vercelAIGateway, id: "paperinstruments/ultramarine-1-flash", context: 1_048_576,
              output: 131_000, vision: true,
              efforts: [.low, .high, .max], canDisable: false),
        // Cloudflare AI Gateway — developers.cloudflare.com/ai/models catalog.
        .init(provider: .cloudflareAIGateway, id: "anthropic/claude-fable-5.2", context: 1_000_000,
              output: 128_000, vision: true,
              efforts: [.low, .medium, .high, .xhigh, .max], canDisable: false),
        .init(provider: .cloudflareAIGateway, id: "google/gemini-4-carbon", context: 1_048_576,
              output: 65_536, vision: true,
              efforts: [.low, .medium, .high], canDisable: false),
        .init(provider: .cloudflareAIGateway, id: "@cf/thinkingmachines/inkling-2-small", context: 1_048_576,
              output: nil, vision: true,
              efforts: [.none, .minimal, .low, .medium, .high, .max], canDisable: true),
        // Together serverless table + model page, verified 2026-11-13.
        .init(provider: .together, id: "thinkingmachines/Inkling-2-Small", context: 1_048_576,
              output: nil, vision: true, efforts: nil, canDisable: false),
        // Fireworks model library card, verified 2026-11-13.
        .init(provider: .fireworks, id: "accounts/fireworks/models/kimi-k3p1-pro", context: 1_048_576,
              output: 131_072, vision: true,
              efforts: [.low, .high, .max], canDisable: false),
        .init(provider: .fireworks, id: "fireworks/kimi-k3p1-pro", context: 1_048_576,
              output: 131_072, vision: true,
              efforts: [.low, .high, .max], canDisable: false),
        // Modal Shared Endpoints changelog 2026-11-04 + supported-models page.
        .init(provider: .modal, id: "moonshotai/Kimi-K3.1-Pro", context: 1_048_576,
              output: 131_072, vision: true,
              efforts: [.low, .high, .max], canDisable: false),
        // Zyphra model feed releaseDate 2026-11-12.
        .init(provider: .zyphra, id: "zai-org/GLM-5.3-Flash-FP4", context: 1_048_576,
              output: 131_072, vision: true,
              efforts: [.low, .high, .max], canDisable: false),
        // OpenCode Go live /zen/go/v1/models, 2026-11-13.
        .init(provider: .opencodeGo, id: "longcat-2.5-free", context: 1_000_000,
              output: 262_144, vision: true, efforts: nil, canDisable: true),
        // Databricks supported-models page updated 2026-11-10.
        .init(provider: .databricks, id: "databricks-gemini-4-carbon", context: 1_048_576,
              output: 65_536, vision: true,
              efforts: [.low, .medium, .high], canDisable: false),
        .init(provider: .databricks, id: "databricks-claude-fable-5-2", context: 1_000_000,
              output: 128_000, vision: true, efforts: nil, canDisable: true),
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
            XCTAssertTrue(JinModelSupport.isFullySupported(providerType: expected.provider, modelID: expected.id), expected.id)

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
    }

    func testGeminiAndVertexGemini4CarbonHydrogenRecords() {
        // thinkingLevel LOW/MEDIUM/HIGH (Carbon) and LOW/MEDIUM/HIGH/XHIGH
        // (Hydrogen); `thinking_budget`/MINIMAL 400; custom sampling ignored;
        // implicit caching only. Multimodal file/image/video + audio input,
        // native PDF, code execution — verified on the official model pages.
        let cases: [(ProviderType, String, [ReasoningEffort], ReasoningEffort)] = [
            (.gemini, "gemini-4-carbon", [.low, .medium, .high], .medium),
            (.gemini, "gemini-4-hydrogen", [.low, .medium, .high, .xhigh], .high),
            (.vertexai, "gemini-4-carbon", [.low, .medium, .high], .medium),
            (.vertexai, "gemini-4-carbon-cyber-permissive", [.low, .medium, .high], .high),
            (.vertexai, "gemini-4-hydrogen", [.low, .medium, .high, .xhigh], .high),
        ]
        for (provider, id, efforts, defaultEffort) in cases {
            let model = ModelCatalog.modelInfo(for: id, provider: provider)
            XCTAssertEqual(model.contextWindow, 1_048_576, "\(provider): \(id)")
            XCTAssertEqual(model.maxOutputTokens, 65_536, "\(provider): \(id)")
            XCTAssertEqual(model.reasoningConfig?.type, .effort, "\(provider): \(id)")
            XCTAssertEqual(model.reasoningConfig?.defaultEffort, defaultEffort, "\(provider): \(id)")
            XCTAssertEqual(model.reasoningConfig?.supportedEfforts, efforts, "\(provider): \(id)")
            for capability: ModelCapability in [.streaming, .toolCalling, .vision, .videoInput,
                                                .audio, .reasoning, .promptCaching, .nativePDF,
                                                .codeExecution] {
                XCTAssertTrue(model.capabilities.contains(capability), "\(provider): \(id) missing \(capability)")
            }
            XCTAssertTrue(JinModelSupport.isFullySupported(providerType: provider, modelID: id), "\(provider): \(id)")
            XCTAssertFalse(GeminiModelConstants.supportsCustomSamplingParameters(id), "\(provider): \(id)")
            XCTAssertTrue(GeminiModelConstants.isGemini4Model(id), "\(provider): \(id)")
            XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: provider, modelID: id), "\(provider): \(id)")
        }
        // Cyber Permissive is Vertex-only — no AI Studio twin.
        XCTAssertNil(ModelCatalog.entry(for: "gemini-4-carbon-cyber-permissive", provider: .gemini))
        XCTAssertTrue(ModelCatalog.seededModels(for: .gemini).contains { $0.id == "gemini-4-carbon" })
        XCTAssertTrue(ModelCatalog.seededModels(for: .vertexai).contains { $0.id == "gemini-4-hydrogen" })
    }

    func testVercelGemini4RecordsKeepNativePDFWithoutVideoClaim() {
        // The Vercel feed lists pdf + video input modalities, but `.videoInput`
        // stays withheld until a live gateway probe (same policy as Argon).
        for id in ["google/gemini-4-carbon", "google/gemini-4-hydrogen"] {
            let model = ModelCatalog.modelInfo(for: id, provider: .vercelAIGateway)
            XCTAssertTrue(model.capabilities.contains(.nativePDF), id)
            XCTAssertFalse(model.capabilities.contains(.videoInput), id)
            XCTAssertEqual(model.contextWindow, 1_048_576, id)
            XCTAssertEqual(model.maxOutputTokens, 65_536, id)
        }
    }

    func testHydrogenXHighMapsToXHIGHThinkingLevel() {
        XCTAssertEqual(
            GeminiModelConstants.mapEffortToThinkingLevel(.xhigh, for: .vertexai, modelID: "gemini-4-hydrogen"),
            "XHIGH")
        // Every other Gemini 4 model tops out at HIGH.
        XCTAssertEqual(
            GeminiModelConstants.mapEffortToThinkingLevel(.xhigh, for: .vertexai, modelID: "gemini-4-carbon"),
            "HIGH")
        XCTAssertEqual(
            GeminiModelConstants.mapEffortToThinkingLevel(.xhigh, for: .gemini, modelID: "gemini-4-argon"),
            "HIGH")
    }

    func testBatchAndAdapterBlockedIDsStayCatalogOnly() throws {
        // OpenRouter `:batch` twins expose only /api/v1/batches — Jin has no
        // synchronous batch surface, so they are recognized but not supported.
        for (provider, id) in [
            (ProviderType.openrouter, "google/gemini-4-carbon:batch"),
            (.openrouter, "google/gemini-4-hydrogen:batch"),
            (.openrouter, "anthropic/claude-fable-5.2:batch"),
        ] {
            let entry = try XCTUnwrap(ModelCatalog.entry(for: id, provider: provider), id)
            XCTAssertFalse(entry.isFullySupported, id)
            XCTAssertFalse(ModelCatalog.seededModels(for: provider).contains { $0.id == id }, id)
        }
        // Vercel `evaluation`-type and `image`-type releases have no chat surface.
        for id in ["google/gemini-decision-1", "perplexity/pplx-decider-v1.3",
                   "perplexity/pplx-decider-flash-v1.3",
                   "minimax/minimax-h3-image", "minimax/minimax-h3-image-highspeed"] {
            let entry = try XCTUnwrap(ModelCatalog.entry(for: id, provider: .vercelAIGateway), id)
            XCTAssertFalse(entry.isFullySupported, id)
        }
    }

    func testNewAlwaysOnModelsClampOffToLowestPublishedEffort() async throws {
        let adapter = OpenRouterAdapter(providerConfig: config(.openrouter), apiKey: "test-key")
        for (id, wire) in [("google/gemini-4-carbon", "low"), ("nex-agi/nex-n2.6", "medium")] {
            let request = try await adapter.buildRequest(messages: [], modelID: id,
                controls: GenerationControls(reasoning: .init(enabled: false, effort: ReasoningEffort.none)),
                tools: [], streaming: true)
            let body = try json(request)
            XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, wire, id)
        }
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
