import XCTest
@testable import Jin

final class DatabricksProviderIntegrationTests: XCTestCase {

    // MARK: - Provider type defaults

    func testDatabricksProviderTypeDefaultsAndIconMapping() {
        XCTAssertEqual(ProviderType.databricks.displayName, "Databricks")
        XCTAssertEqual(
            ProviderType.databricks.defaultBaseURL,
            "https://dbc-00000000-0000.cloud.databricks.com/serving-endpoints"
        )
        XCTAssertEqual(LobeProviderIconCatalog.defaultIconID(for: .databricks), "Dbrx")
        // Databricks is OpenAI-chat-completions compatible.
        XCTAssertEqual(
            ModelCapabilityRegistry.requestShape(for: .databricks, modelID: "databricks-gpt-oss-120b"),
            .openAICompatible
        )
    }

    // MARK: - Adapter routing

    func testProviderManagerCreatesDatabricksAdapter() async throws {
        let config = ProviderConfig(
            id: "databricks",
            name: "Databricks",
            type: .databricks,
            apiKey: "dapi-test-token",
            baseURL: ProviderType.databricks.defaultBaseURL,
            models: []
        )

        let manager = ProviderManager()
        let adapter = try await manager.createAdapter(for: config)

        XCTAssertTrue(adapter is DatabricksAdapter)
    }

    // MARK: - Seeds

    func testDefaultProviderSeedsIncludeDatabricksWithSeededModels() {
        let providers = DefaultProviderSeeds.allProviders()
        guard let provider = providers.first(where: { $0.type == .databricks }) else {
            return XCTFail("Expected Databricks in default provider seeds.")
        }

        XCTAssertEqual(provider.id, "databricks")
        XCTAssertEqual(provider.baseURL, ProviderType.databricks.defaultBaseURL)
        XCTAssertEqual(
            provider.models.map(\.id),
            [
                "databricks-claude-sonnet-4-6",
                "databricks-claude-opus-5",
                "databricks-claude-opus-4-8",
                "databricks-gpt-oss-120b",
                "databricks-gemini-3-1-pro",
                "databricks-qwen35-122b-a10b",
                "databricks-llama-4-maverick",
                "databricks-meta-llama-3-3-70b-instruct",
                "databricks-gemma-3-12b",
            ]
        )
    }

    // MARK: - Catalog metadata

    func testDatabricksCatalogCapabilities() {
        // Claude via FMAPI: vision, 200K context. Reasoning is intentionally NOT exposed —
        // Databricks Claude uses thinking/budget_tokens, not the reasoning_effort the OpenAI-compat
        // adapter emits.
        let sonnet = ModelCatalog.modelInfo(for: "databricks-claude-sonnet-4-6", provider: .databricks)
        XCTAssertEqual(sonnet.contextWindow, 200_000)
        XCTAssertTrue(sonnet.capabilities.contains(.vision))
        XCTAssertFalse(sonnet.capabilities.contains(.reasoning))
        XCTAssertNil(sonnet.reasoningConfig)

        // GPT-OSS: reasoning, no vision.
        let gptOSS = ModelCatalog.modelInfo(for: "databricks-gpt-oss-120b", provider: .databricks)
        XCTAssertTrue(gptOSS.capabilities.contains(.reasoning))
        XCTAssertFalse(gptOSS.capabilities.contains(.vision))
        XCTAssertEqual(gptOSS.reasoningConfig?.type, .effort)

        // Llama 3.3: tools only, no vision, no reasoning.
        let llama = ModelCatalog.modelInfo(for: "databricks-meta-llama-3-3-70b-instruct", provider: .databricks)
        XCTAssertTrue(llama.capabilities.contains(.toolCalling))
        XCTAssertFalse(llama.capabilities.contains(.vision))
        XCTAssertFalse(llama.capabilities.contains(.reasoning))
        XCTAssertNil(llama.reasoningConfig)

        // Llama 4 Maverick: vision, no reasoning.
        let maverick = ModelCatalog.modelInfo(for: "databricks-llama-4-maverick", provider: .databricks)
        XCTAssertTrue(maverick.capabilities.contains(.vision))
        XCTAssertFalse(maverick.capabilities.contains(.reasoning))

        // Claude Fable 5.1: 1M context, vision, tools, no reasoning effort control
        let fable51 = ModelCatalog.modelInfo(for: "databricks-claude-fable-5-1", provider: .databricks)
        XCTAssertEqual(fable51.contextWindow, 1_000_000)
        XCTAssertEqual(fable51.maxOutputTokens, 128_000)
        XCTAssertTrue(fable51.capabilities.contains(.vision))
        XCTAssertTrue(fable51.capabilities.contains(.toolCalling))
        XCTAssertFalse(fable51.capabilities.contains(.reasoning))
        XCTAssertNil(fable51.reasoningConfig)

        // GLM 5.3 & Flash: 1M context, reasoning
        let glm53 = ModelCatalog.modelInfo(for: "databricks-glm-5-3", provider: .databricks)
        XCTAssertEqual(glm53.contextWindow, 1_048_576)
        XCTAssertTrue(glm53.capabilities.contains(.reasoning))
        XCTAssertFalse(glm53.capabilities.contains(.vision))

        let glm53Flash = ModelCatalog.modelInfo(for: "databricks-glm-5-3-flash", provider: .databricks)
        XCTAssertEqual(glm53Flash.contextWindow, 1_048_576)
        XCTAssertTrue(glm53Flash.capabilities.contains(.reasoning))
        XCTAssertTrue(glm53Flash.capabilities.contains(.vision))

        // Grok 4.6: 500k context, vision, reasoning
        let grok46 = ModelCatalog.modelInfo(for: "databricks-grok-4-6", provider: .databricks)
        XCTAssertEqual(grok46.contextWindow, 500_000)
        XCTAssertTrue(grok46.capabilities.contains(.vision))
        XCTAssertTrue(grok46.capabilities.contains(.reasoning))
    }

    // MARK: - Reasoning effort gating

    func testDatabricksReasoningEffortIsLowMediumHigh() {
        // Databricks documents reasoning_effort as low/medium/high only — no xhigh/max.
        let efforts = ModelCapabilityRegistry.supportedReasoningEfforts(
            for: .databricks,
            modelID: "databricks-gpt-oss-120b"
        )
        XCTAssertEqual(efforts, [.low, .medium, .high])

        let gptEfforts = ModelCapabilityRegistry.supportedReasoningEfforts(
            for: .databricks,
            modelID: "databricks-gpt-5-6-sol"
        )
        XCTAssertEqual(gptEfforts, [.low, .medium, .high])
    }

    // MARK: - Base URL normalization

    func testWorkspaceRootAndDerivedRoutes() async {
        func adapter(_ baseURL: String) -> DatabricksAdapter {
            DatabricksAdapter(
                providerConfig: ProviderConfig(
                    id: "databricks",
                    name: "Databricks",
                    type: .databricks,
                    apiKey: "dapi-test",
                    baseURL: baseURL
                ),
                apiKey: "dapi-test"
            )
        }

        let expectedRoot = "https://dbc-1234.cloud.databricks.com"

        // Full /serving-endpoints URL.
        let withServing = adapter("https://dbc-1234.cloud.databricks.com/serving-endpoints")
        let withServingRoot = await withServing.workspaceRoot
        let withServingChat = await withServing.chatCompletionsURLString
        let withServingList = await withServing.servingEndpointsListURLString
        XCTAssertEqual(withServingRoot, expectedRoot)
        XCTAssertEqual(withServingChat, "\(expectedRoot)/serving-endpoints/chat/completions")
        XCTAssertEqual(withServingList, "\(expectedRoot)/api/2.0/serving-endpoints")

        // Bare workspace host.
        let bareHostRoot = await adapter("https://dbc-1234.cloud.databricks.com").workspaceRoot
        XCTAssertEqual(bareHostRoot, expectedRoot)

        // Trailing slash after /serving-endpoints.
        let trailingSlashRoot = await adapter("https://dbc-1234.cloud.databricks.com/serving-endpoints/").workspaceRoot
        XCTAssertEqual(trailingSlashRoot, expectedRoot)

        // No scheme.
        let noSchemeRoot = await adapter("dbc-1234.cloud.databricks.com").workspaceRoot
        XCTAssertEqual(noSchemeRoot, expectedRoot)

        // Full chat completions URL pasted by mistake.
        let fullChatRoot = await adapter("https://dbc-1234.cloud.databricks.com/serving-endpoints/chat/completions").workspaceRoot
        XCTAssertEqual(fullChatRoot, expectedRoot)

        // Foundation Model APIs mode: chat route + not a gateway.
        let fmapi = adapter("https://dbc-1234.cloud.databricks.com")
        let fmapiIsGateway = await fmapi.isOpenAIGateway
        let fmapiChat = await fmapi.chatCompletionsURLString
        XCTAssertFalse(fmapiIsGateway)
        XCTAssertEqual(fmapiChat, "\(expectedRoot)/serving-endpoints/chat/completions")
    }

    func testOpenAIGatewayRoutesToNativeOpenAISurface() async {
        let adapter = DatabricksAdapter(
            providerConfig: ProviderConfig(
                id: "databricks",
                name: "Databricks",
                type: .databricks,
                apiKey: "dapi-test",
                baseURL: "https://dbc-1234.cloud.databricks.com/ai-gateway/openai/v1"
            ),
            apiKey: "dapi-test"
        )
        let isGateway = await adapter.isOpenAIGateway
        let chat = await adapter.chatCompletionsURLString
        let service = await adapter.gatewayProviderService
        XCTAssertTrue(isGateway)
        XCTAssertEqual(chat, "https://dbc-1234.cloud.databricks.com/ai-gateway/openai/v1/chat/completions")
        XCTAssertEqual(service, "workspace.default.openai")
    }

    func testDatabricksGatewayHelpers() {
        let ws = "https://dbc-1234.cloud.databricks.com"
        XCTAssertTrue(DatabricksGateway.isOpenAIGateway("\(ws)/ai-gateway/openai/v1"))
        XCTAssertTrue(DatabricksGateway.isAnthropicGateway("\(ws)/ai-gateway/anthropic/v1"))
        XCTAssertFalse(DatabricksGateway.isOpenAIGateway("\(ws)/ai-gateway/anthropic/v1"))
        XCTAssertFalse(DatabricksGateway.isGateway(ws))
        XCTAssertFalse(DatabricksGateway.isGateway("\(ws)/serving-endpoints"))

        XCTAssertEqual(DatabricksGateway.providerServiceName(from: "\(ws)/ai-gateway/openai/v1"), "workspace.default.openai")
        XCTAssertEqual(DatabricksGateway.providerServiceName(from: "\(ws)/ai-gateway/anthropic/v1/messages"), "workspace.default.anthropic")
        XCTAssertNil(DatabricksGateway.providerServiceName(from: ws))
        XCTAssertNil(DatabricksGateway.providerServiceName(from: "\(ws)/ai-gateway/mlflow/v1"))

        // Explicit ?service= override for non-default service locations/names.
        XCTAssertEqual(
            DatabricksGateway.providerServiceName(from: "\(ws)/ai-gateway/openai/v1?service=main.default.openai_prod"),
            "main.default.openai_prod"
        )
        XCTAssertEqual(
            DatabricksGateway.providerServiceName(from: "\(ws)/ai-gateway/anthropic/v1?service=main.default.claude_prod"),
            "main.default.claude_prod"
        )
        // A query string must not disturb protocol detection or the workspace root.
        XCTAssertTrue(DatabricksGateway.isOpenAIGateway("\(ws)/ai-gateway/openai/v1?service=main.default.openai_prod"))
        XCTAssertEqual(DatabricksGateway.workspaceRoot(from: "\(ws)/ai-gateway/openai/v1?service=main.default.x"), ws)

        XCTAssertEqual(DatabricksGateway.workspaceRoot(from: "\(ws)/ai-gateway/anthropic/v1"), ws)
        XCTAssertEqual(DatabricksGateway.workspaceRoot(from: ws), ws)
    }

    func testGatewayServiceOverrideReachesRequests() async throws {
        // OpenAI gateway: override flows into the Databricks-Model-Provider-Service header, and the
        // chat URL stays clean (no query string).
        let openai = DatabricksAdapter(
            providerConfig: ProviderConfig(
                id: "databricks", name: "Databricks", type: .databricks, apiKey: "dapi-test",
                baseURL: "https://dbc-1234.cloud.databricks.com/ai-gateway/openai/v1?service=main.default.openai_prod"
            ),
            apiKey: "dapi-test"
        )
        let req = try await openai.buildRequest(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gpt-4o", controls: GenerationControls(), tools: [], streaming: false
        )
        XCTAssertEqual(
            req.value(forHTTPHeaderField: "Databricks-Model-Provider-Service"),
            "main.default.openai_prod"
        )
        XCTAssertEqual(
            req.url?.absoluteString,
            "https://dbc-1234.cloud.databricks.com/ai-gateway/openai/v1/chat/completions"
        )

        // Anthropic gateway: override flows into the header via AnthropicAdapter.
        let anthropic = AnthropicAdapter(
            providerConfig: ProviderConfig(
                id: "databricks", name: "Databricks", type: .databricks, apiKey: "dapi-test",
                baseURL: "https://dbc-1234.cloud.databricks.com/ai-gateway/anthropic/v1?service=main.default.claude_prod"
            ),
            apiKey: "dapi-test"
        )
        let headers = await anthropic.anthropicHeaders(apiKey: "dapi-test", contentType: "application/json")
        XCTAssertEqual(headers["Databricks-Model-Provider-Service"], "main.default.claude_prod")
    }

    func testProviderManagerRoutesGatewaysToCorrectAdapters() async throws {
        func adapter(_ baseURL: String) async throws -> any LLMProviderAdapter {
            try await ProviderManager().createAdapter(for: ProviderConfig(
                id: "databricks",
                name: "Databricks",
                type: .databricks,
                apiKey: "dapi-test",
                baseURL: baseURL
            ))
        }

        // Anthropic gateway → AnthropicAdapter (Messages protocol).
        let anthropic = try await adapter("https://dbc-1234.cloud.databricks.com/ai-gateway/anthropic/v1")
        XCTAssertTrue(anthropic is AnthropicAdapter)

        // OpenAI gateway + bare host → DatabricksAdapter (OpenAI chat completions).
        let openai = try await adapter("https://dbc-1234.cloud.databricks.com/ai-gateway/openai/v1")
        XCTAssertTrue(openai is DatabricksAdapter)
        let fmapi = try await adapter("https://dbc-1234.cloud.databricks.com")
        XCTAssertTrue(fmapi is DatabricksAdapter)
    }

    func testOpenAIGatewayRequestShape() async throws {
        let adapter = DatabricksAdapter(
            providerConfig: ProviderConfig(
                id: "databricks",
                name: "Databricks",
                type: .databricks,
                apiKey: "dapi-test",
                baseURL: "https://dbc-1234.cloud.databricks.com/ai-gateway/openai/v1"
            ),
            apiKey: "dapi-test"
        )
        var controls = GenerationControls()
        controls.temperature = 0.1
        controls.maxTokens = 256

        // GPT-5 reasoning model: temperature/top_p dropped (OpenAI rejects non-default),
        // max_completion_tokens used, and the provider-service header is set.
        let req = try await adapter.buildRequest(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gpt-5.6-luna", controls: controls, tools: [], streaming: false
        )
        XCTAssertEqual(
            req.url?.absoluteString,
            "https://dbc-1234.cloud.databricks.com/ai-gateway/openai/v1/chat/completions"
        )
        XCTAssertEqual(
            req.value(forHTTPHeaderField: "Databricks-Model-Provider-Service"),
            "workspace.default.openai"
        )
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(req.httpBody)) as? [String: Any]
        XCTAssertNil(body?["temperature"])
        XCTAssertNil(body?["top_p"])
        XCTAssertNotNil(body?["max_completion_tokens"])
        XCTAssertNil(body?["max_tokens"])

        // Non-reasoning OpenAI model keeps custom temperature.
        let req2 = try await adapter.buildRequest(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gpt-4o", controls: controls, tools: [], streaming: false
        )
        let body2 = try JSONSerialization.jsonObject(with: try XCTUnwrap(req2.httpBody)) as? [String: Any]
        XCTAssertEqual(body2?["temperature"] as? Double, 0.1)
    }

    func testGatewayFetchReturnsCuratedModels() async throws {
        let openai = DatabricksAdapter(
            providerConfig: ProviderConfig(
                id: "databricks", name: "Databricks", type: .databricks, apiKey: "dapi-test",
                baseURL: "https://dbc-1234.cloud.databricks.com/ai-gateway/openai/v1"
            ),
            apiKey: "dapi-test"
        )
        let openaiModels = try await openai.fetchAvailableModels()
        XCTAssertTrue(openaiModels.contains { $0.id == "gpt-5" })
        XCTAssertTrue(openaiModels.contains { $0.id == "gpt-4o-mini" })
        XCTAssertEqual(openaiModels.first { $0.id == "gpt-5" }?.capabilities.contains(.reasoning), true)
        XCTAssertEqual(openaiModels.first { $0.id == "gpt-4o" }?.capabilities.contains(.reasoning), false)

        let anthropic = AnthropicAdapter(
            providerConfig: ProviderConfig(
                id: "databricks", name: "Databricks", type: .databricks, apiKey: "dapi-test",
                baseURL: "https://dbc-1234.cloud.databricks.com/ai-gateway/anthropic/v1"
            ),
            apiKey: "dapi-test"
        )
        let claudeModels = try await anthropic.fetchAvailableModels()
        XCTAssertTrue(claudeModels.contains { $0.id == "claude-sonnet-4-5" })
        XCTAssertFalse(claudeModels.isEmpty)
        XCTAssertTrue(claudeModels.allSatisfy { $0.id.hasPrefix("claude") })
    }

    func testAnthropicGatewayAdapterURLAndHeaders() async {
        let adapter = AnthropicAdapter(
            providerConfig: ProviderConfig(
                id: "databricks",
                name: "Databricks",
                type: .databricks,
                apiKey: "dapi-secret",
                baseURL: "https://dbc-1234.cloud.databricks.com/ai-gateway/anthropic/v1"
            ),
            apiKey: "dapi-secret"
        )
        let base = await adapter.baseURL
        XCTAssertEqual(base, "https://dbc-1234.cloud.databricks.com/ai-gateway/anthropic/v1")

        let headers = await adapter.anthropicHeaders(apiKey: "dapi-secret", contentType: "application/json")
        XCTAssertEqual(headers["Authorization"], "Bearer dapi-secret")
        XCTAssertEqual(headers["Databricks-Model-Provider-Service"], "workspace.default.anthropic")
        XCTAssertNil(headers["x-api-key"])
    }

    // MARK: - Serving endpoints listing decode + filter

    func testServingEndpointsListingDecodeAndChatFilter() throws {
        let json = """
        {
          "endpoints": [
            {
              "name": "databricks-claude-sonnet-4-6",
              "task": "llm/v1/chat",
              "state": { "ready": "READY", "config_update": "NOT_UPDATING" },
              "config": {
                "served_entities": [
                  {
                    "foundation_model": {
                      "display_name": "Claude Sonnet 4.6",
                      "name": "system.ai.databricks-claude-sonnet-4-6"
                    },
                    "name": "databricks-claude-sonnet-4-6"
                  }
                ]
              }
            },
            { "name": "databricks-gte-large-en", "task": "llm/v1/embeddings" },
            { "name": "fraud-model" }
          ]
        }
        """

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(
            DatabricksServingEndpointsResponse.self,
            from: Data(json.utf8)
        )

        // Only endpoints whose task is exactly "llm/v1/chat" are surfaced.
        let chatEndpoints = (response.endpoints ?? []).filter { $0.isChatEndpoint }
        XCTAssertEqual(chatEndpoints.map(\.name), ["databricks-claude-sonnet-4-6"])

        // Foundation-model display name is surfaced for nicer labels.
        let claude = chatEndpoints.first { $0.name == "databricks-claude-sonnet-4-6" }
        XCTAssertEqual(claude?.foundationModelDisplayName, "Claude Sonnet 4.6")

        // Embeddings endpoint and task-less custom (pyfunc) endpoint are filtered out — they
        // are not OpenAI-chat-compatible.
        XCTAssertFalse(chatEndpoints.contains { $0.name == "databricks-gte-large-en" })
        XCTAssertFalse(chatEndpoints.contains { $0.name == "fraud-model" })
    }

    // MARK: - Conservative capabilities for uncataloged endpoints

    func testUncatalogedModelsStayConservative() async {
        let adapter = DatabricksAdapter(
            providerConfig: ProviderConfig(
                id: "databricks", name: "Databricks", type: .databricks, apiKey: "dapi-test",
                baseURL: "https://dbc-1234.cloud.databricks.com"
            ),
            apiKey: "dapi-test"
        )
        // A cataloged vision model reports vision; an uncataloged endpoint is treated
        // conservatively (no vision) rather than guessed from the name.
        let cataloged = await adapter.modelSupportsVision("databricks-claude-sonnet-4-6")
        let unknown = await adapter.modelSupportsVision("databricks-some-future-model-xyz")
        XCTAssertTrue(cataloged)
        XCTAssertFalse(unknown)
    }
}
