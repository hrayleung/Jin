import XCTest
@testable import Jin

final class November18ModelSupportTests: XCTestCase {
    private let gptIDs = ["gpt-6.2-astra", "gpt-6.2-sol"]
    private let gptEfforts: [ReasoningEffort] = [.low, .medium, .high, .xhigh, .max]

    func testGPT62CatalogAndLegacyRows() throws {
        for id in gptIDs {
            let routes: [(ProviderType, String)] = [
                (.openai, id), (.openaiWebSocket, id),
                (.openrouter, "openai/" + id), (.openrouter, "openai/" + id + "-pro"),
                (.vercelAIGateway, "openai/" + id), (.vercelAIGateway, "openai/" + id + "-fast"),
            ]
            for (provider, modelID) in routes {
                let resolved = try assertCatalog(
                    provider, modelID, context: 1_050_000, output: 128_000,
                    capabilities: [.streaming, .toolCalling, .reasoning, .vision]
                )
                XCTAssertEqual(resolved.reasoningConfig?.supportedEfforts, gptEfforts, modelID)
                XCTAssertEqual(resolved.reasoningConfig?.defaultEffort, .medium, modelID)
                XCTAssertFalse(resolved.reasoningCanDisable, modelID)
                let native = provider == .openai || provider == .openaiWebSocket
                XCTAssertTrue(resolved.capabilities.contains(.nativePDF), modelID)
                XCTAssertTrue(ChatModelCapabilitySupport.adapterCanSendNativePDF(
                    providerType: provider, modelID: modelID
                ))
                XCTAssertEqual(resolved.capabilities.contains(.codeExecution), native, modelID)
                XCTAssertEqual(ModelCatalog.seededModels(for: provider).contains { $0.id == modelID }, native)
            }
            for suffix in [":batch", "-pro:batch"] {
                let batch = try XCTUnwrap(ModelCatalog.entry(for: "openai/" + id + suffix, provider: .openrouter))
                XCTAssertFalse(batch.isFullySupported)
                XCTAssertFalse(batch.capabilities.contains(.streaming))
            }
            XCTAssertNil(ModelCatalog.entry(for: id + "-pro", provider: .openai))
        }
    }

    func testHostedModelsUseEachGatewaysLimitsAndCapabilities() throws {
        let cases: [(ProviderType, String, Int, Int?, ModelCapability)] = [
            (.openrouter, "tencent/hy4-flash", 1_048_576, 65_536, [.vision, .reasoning]),
            (.openrouter, "qwen/qwen4-max", 1_000_000, 131_072, [.vision, .reasoning]),
            (.vercelAIGateway, "tencent/hy4-flash", 1_024_000, 64_000, [.vision, .reasoning]),
            (.vercelAIGateway, "alibaba/qwen4-max", 1_000_000, 384_000, [.vision, .reasoning]),
            (.vercelAIGateway, "recursive/flint-v1.0", 262_144, 262_144, [.reasoning]),
            (.deepinfra, "Qwen/Qwen4-Max", 1_000_000, nil, [.vision, .videoInput]),
            (.databricks, "system.ai.gemini-4-hydrogen", 1_048_576, 65_536, []),
        ]
        for (provider, id, context, output, capabilities) in cases {
            let resolved = try assertCatalog(provider, id, context: context, output: output,
                                             capabilities: capabilities.union(.streaming))
            XCTAssertEqual(resolved.capabilities.contains(.vision), capabilities.contains(.vision), id)
            XCTAssertEqual(resolved.capabilities.contains(.videoInput), capabilities.contains(.videoInput), id)
            XCTAssertFalse(resolved.capabilities.contains(.nativePDF), id)
        }
    }

    func testNativeGPT62ResponsesAndWebSocketRequests() async throws {
        let http = OpenAIAdapter(providerConfig: config(.openai), apiKey: "test-key")
        let socket = OpenAIWebSocketAdapter(providerConfig: config(.openaiWebSocket), apiKey: "test-key")
        var controls = GenerationControls(
            temperature: 0.7, topP: 0.8,
            reasoning: ReasoningControls(enabled: true, effort: .max, mode: .pro)
        )
        controls.openAIServiceTier = .ultrafast
        controls.webSearch = WebSearchControls(enabled: true)
        controls.codeExecution = CodeExecutionControls(enabled: true)
        let tools = [ToolDefinition(id: "lookup", name: "lookup", description: "Look up a value",
                                    parameters: ParameterSchema(properties: [:]), source: .builtin)]
        for id in gptIDs {
            let request = try await http.buildRequest(messages: [], modelID: id, controls: controls,
                                                      tools: tools, streaming: true)
            XCTAssertEqual(request.url?.path, "/v1/responses")
            let httpBody = try json(request)
            let socketBody = try await socket.buildResponsePayload(
                messages: [], modelID: id, controls: controls, tools: tools, previousResponseID: nil
            )
            for body in [httpBody, socketBody] {
                XCTAssertEqual(body["model"] as? String, id)
                XCTAssertNil(body["temperature"])
                XCTAssertNil(body["top_p"])
                XCTAssertEqual(body["service_tier"] as? String, "ultrafast")
                XCTAssertEqual(body["reasoning"] as? [String: String], ["effort": "max", "mode": "pro"])
                let types = try XCTUnwrap(body["tools"] as? [[String: Any]]).compactMap { $0["type"] as? String }
                XCTAssertEqual(Set(types), ["function", "web_search", "code_interpreter"])
            }
        }
        XCTAssertNil(resolvedOpenAIServiceTier(from: controls, modelID: "gpt-6.2-astra-custom", providerType: .openai))
    }

    func testHostedReasoningWireFormats() async throws {
        let controls = GenerationControls(
            temperature: 0.7, topP: 0.8,
            reasoning: ReasoningControls(enabled: false, effort: ReasoningEffort.none)
        )
        let router = OpenRouterAdapter(providerConfig: config(.openrouter), apiKey: "test-key")
        let routerRequest = try await router.buildRequest(messages: [], modelID: "openai/gpt-6.2-astra-pro",
                                                          controls: controls, tools: [], streaming: true)
        XCTAssertEqual(try json(routerRequest)["reasoning"] as? [String: String], ["effort": "low"])
        let toggleRequest = try await router.buildRequest(messages: [], modelID: "tencent/hy4-flash",
                                                          controls: controls, tools: [], streaming: true)
        XCTAssertEqual(try json(toggleRequest)["reasoning"] as? [String: Bool], ["enabled": false])

        let deepInfra = OpenAICompatibleAdapter(providerConfig: config(.deepinfra), apiKey: "test-key")
        let deepInfraRequest = try await deepInfra.buildRequest(
            messages: [], modelID: "thinkingmachines/Inkling-2-Small", controls: controls, tools: [], streaming: true
        )
        let deepInfraBody = try json(deepInfraRequest)
        XCTAssertEqual(deepInfraBody["reasoning_effort"] as? String, "none")
        XCTAssertNil(deepInfraBody["reasoning"])
    }

    func testHostedGPT62NativePDFAndVercelResponsesControls() async throws {
        let file = FileContent(mimeType: "application/pdf", filename: "sample.pdf", data: Data([1, 2, 3]))
        let messages = [Message(role: .user, content: [.file(file)])]
        var controls = GenerationControls(temperature: 0.7, topP: 0.8)
        controls.reasoning = ReasoningControls(enabled: true, effort: .max)
        controls.webSearch = WebSearchControls(enabled: true)
        controls.openAIServiceTier = .ultrafast

        let id = "openai/gpt-6.2-sol"
        let vercel = OpenAIAdapter(providerConfig: config(.vercelAIGateway), apiKey: "test-key")
        let vercelRequest = try await vercel.buildRequest(
            messages: messages, modelID: id, controls: controls, tools: [], streaming: true
        )
        XCTAssertEqual(vercelRequest.url?.path, "/v1/responses")
        let vercelBody = try json(vercelRequest)
        XCTAssertEqual(vercelBody["reasoning"] as? [String: String], ["effort": "max"])
        XCTAssertEqual(vercelBody["service_tier"] as? String, "ultrafast")
        XCTAssertNil(vercelBody["temperature"])
        XCTAssertNil(vercelBody["top_p"])
        XCTAssertEqual((vercelBody["tools"] as? [[String: Any]])?.first?["type"] as? String, "web_search")
        let input = try XCTUnwrap(vercelBody["input"] as? [[String: Any]])
        let vercelParts = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        XCTAssertEqual(vercelParts.first?["type"] as? String, "input_file")
        XCTAssertEqual(vercelParts.first?["file_data"] as? String, "data:application/pdf;base64,AQID")

        let router = OpenRouterAdapter(providerConfig: config(.openrouter), apiKey: "test-key")
        let routerRequest = try await router.buildRequest(
            messages: messages, modelID: id, controls: controls, tools: [], streaming: true
        )
        let routerBody = try json(routerRequest)
        let routerMessages = try XCTUnwrap(routerBody["messages"] as? [[String: Any]])
        let routerParts = try XCTUnwrap(routerMessages.first?["content"] as? [[String: Any]])
        XCTAssertEqual(routerParts.first?["type"] as? String, "file")
        XCTAssertEqual(routerParts.first?["file"] as? [String: String],
                       ["filename": "sample.pdf", "file_data": "data:application/pdf;base64,AQID"])
    }

    func testDatabricksHydrogenUsesUnityModelService() async throws {
        let adapter = DatabricksAdapter(providerConfig: config(.databricks), apiKey: "test-key")
        let id = "system.ai.gemini-4-hydrogen"
        let request = try await adapter.buildRequest(
            messages: [Message(role: .user, content: [.text("Hello")])], modelID: id,
            controls: GenerationControls(maxTokens: 2048, reasoning: ReasoningControls(enabled: true, effort: .low)),
            tools: [], streaming: true
        )
        let body = try json(request)
        XCTAssertEqual(request.url?.path, "/ai-gateway/mlflow/v1/chat/completions")
        XCTAssertNil(request.value(forHTTPHeaderField: DatabricksGateway.modelProviderServiceHeader))
        XCTAssertEqual(body["model"] as? String, id)
        XCTAssertEqual(body["max_tokens"] as? Int, 2048)
        XCTAssertNil(body["reasoning_effort"])
    }

    @discardableResult
    private func assertCatalog(
        _ provider: ProviderType, _ id: String, context: Int, output: Int?, capabilities: ModelCapability
    ) throws -> ResolvedModelSettings {
        let entry = try XCTUnwrap(ModelCatalog.entry(for: id, provider: provider), id)
        XCTAssertEqual(entry.contextWindow, context, id)
        XCTAssertEqual(entry.maxOutputTokens, output, id)
        XCTAssertTrue(entry.capabilities.isSuperset(of: capabilities), id)
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: provider, modelID: id), id)
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: provider, modelID: id + "-custom"), id)
        let legacy = ModelInfo(id: id, name: "Saved model", capabilities: [], contextWindow: 128_000,
                               maxOutputTokens: 4_096)
        let resolved = ModelSettingsResolver.resolve(model: legacy, providerType: provider)
        XCTAssertEqual(resolved.contextWindow, context, id)
        XCTAssertEqual(resolved.maxOutputTokens, output ?? 4_096, id)
        XCTAssertEqual(resolved.capabilities, entry.capabilities, id)
        XCTAssertEqual(resolved.reasoningConfig, entry.reasoningConfig, id)
        return resolved
    }

    private func config(_ provider: ProviderType) -> ProviderConfig {
        ProviderConfig(id: provider.rawValue, name: provider.displayName, type: provider,
                       baseURL: provider.defaultBaseURL, models: [])
    }

    private func json(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
