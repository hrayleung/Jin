import XCTest
@testable import Jin

final class MakoraAdapterTests: XCTestCase {
    override func tearDown() {
        MakoraMockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testValidateAPIKeyHitsModelsEndpoint() async throws {
        let (configuration, protocolType) = makeMakoraMockedSession()
        let networkManager = NetworkManager(configuration: configuration)
        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://inference.makora.com/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let data = Data(#"{"object":"list","data":[]}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = MakoraAdapter(
            providerConfig: makeMakoraConfig(),
            apiKey: "ignored",
            networkManager: networkManager
        )
        let isValid = try await adapter.validateAPIKey("test-key")
        XCTAssertTrue(isValid)
    }

    func testFetchAvailableModelsAppliesCatalogMetadata() async throws {
        let (configuration, protocolType) = makeMakoraMockedSession()
        let networkManager = NetworkManager(configuration: configuration)
        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://inference.makora.com/v1/models")
            let payload: [String: Any] = [
                "object": "list",
                "data": [
                    ["id": "moonshotai/Kimi-K3"],
                    ["id": "google/gemma-4-26B-A4B"],
                    ["id": "unknown-org/mystery-model"],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = MakoraAdapter(
            providerConfig: makeMakoraConfig(),
            apiKey: "test-key",
            networkManager: networkManager
        )
        let models = try await adapter.fetchAvailableModels()
        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        let kimi = try XCTUnwrap(byID["moonshotai/Kimi-K3"])
        XCTAssertEqual(kimi.contextWindow, 1_048_576)
        XCTAssertTrue(kimi.capabilities.contains(.vision))

        let gemma = try XCTUnwrap(byID["google/gemma-4-26B-A4B"])
        XCTAssertEqual(gemma.contextWindow, 131_072)

        let unknown = try XCTUnwrap(byID["unknown-org/mystery-model"])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
    }

    func testDeepSeekFlash0731ThinkingRewrite() async throws {
        let body = try await captureChatBody(
            modelID: "deepseek-ai/DeepSeek-V4-Flash-0731",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .high))
        )
        XCTAssertEqual(body["include_reasoning"] as? Bool, true)
        let kwargs = try XCTUnwrap(body["chat_template_kwargs"] as? [String: Any])
        XCTAssertEqual(kwargs["thinking"] as? Bool, true)
        XCTAssertNil(body["thinking"])
        XCTAssertEqual(body["reasoning_effort"] as? String, "high")
        XCTAssertEqual(body["model"] as? String, "deepseek-ai/DeepSeek-V4-Flash-0731")
    }

    func testDeepSeekFlashThinkingCanDisable() async throws {
        let body = try await captureChatBody(
            modelID: "deepseek-ai/DeepSeek-V4-Flash",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: false))
        )
        XCTAssertEqual(body["include_reasoning"] as? Bool, false)
        let kwargs = try XCTUnwrap(body["chat_template_kwargs"] as? [String: Any])
        XCTAssertEqual(kwargs["thinking"] as? Bool, false)
        XCTAssertNil(body["reasoning_effort"])
    }

    func testGLM52EnableThinkingAndMaxCompletionTokens() async throws {
        let body = try await captureChatBody(
            modelID: "zai-org/GLM-5.2-FP8",
            controls: GenerationControls(
                maxTokens: 2048,
                reasoning: ReasoningControls(enabled: true, effort: .max)
            )
        )
        let kwargs = try XCTUnwrap(body["chat_template_kwargs"] as? [String: Any])
        XCTAssertEqual(kwargs["enable_thinking"] as? Bool, true)
        XCTAssertEqual(body["reasoning_effort"] as? String, "max")
        XCTAssertEqual(body["max_completion_tokens"] as? Int, 2048)
        XCTAssertNil(body["max_tokens"])
    }

    func testKimiK26DisablesNativeToolChoiceWhenToolsPresent() async throws {
        let tool = makeMakoraLookupTool()
        let body = try await captureChatBody(
            modelID: "nvidia/Kimi-K2.6-NVFP4",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .medium)),
            tools: [tool]
        )
        XCTAssertEqual(body["tool_choice"] as? String, "none")
        XCTAssertEqual(body["skip_special_tokens"] as? Bool, false)
        XCTAssertNotNil(body["tools"])
    }

    func testGLM51SetsToolStream() async throws {
        let tool = makeMakoraLookupTool()
        let body = try await captureChatBody(
            modelID: "zai-org/GLM-5.1-FP8",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true)),
            tools: [tool]
        )
        XCTAssertEqual(body["tool_stream"] as? Bool, true)
        XCTAssertNil(body["tool_choice"])
    }

    func testLlamaFP8UsesPerSlugEndpoint() async throws {
        let url = try await captureChatURL(
            modelID: "amd/Llama-3.3-70B-Instruct-FP8-KV",
            controls: GenerationControls()
        )
        XCTAssertEqual(
            url,
            "https://inference.makora.com/llama3-3-70b-instruct-fp8/v1/chat/completions"
        )
    }

    func testCanonicalModelIDPreservesMakoraCasing() {
        XCTAssertEqual(
            MakoraModelSupport.canonicalModelID(for: "google/gemma-4-26b-a4b"),
            "google/gemma-4-26B-A4B"
        )
        XCTAssertEqual(
            MakoraModelSupport.canonicalModelID(for: "zai-org/glm-5.2-nvfp4"),
            "zai-org/GLM-5.2-NVFP4"
        )
    }

    func testGLMFollowUpStripsToolCallsToXML() async throws {
        let call = ToolCall(
            id: "call_1",
            name: "lookup",
            arguments: ["q": AnyCodable("x")]
        )
        let assistant = Message(
            role: .assistant,
            content: [.text("ok")],
            toolCalls: [call]
        )
        let body = try await captureChatBody(
            modelID: "zai-org/GLM-5.2-FP8",
            messages: [assistant],
            controls: GenerationControls()
        )
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertNil(messages[0]["tool_calls"])
        let content = try XCTUnwrap(messages[0]["content"] as? String)
        XCTAssertTrue(content.contains("<tool_call>"))
        XCTAssertTrue(content.contains("<tool_name>lookup</tool_name>"))
        XCTAssertTrue(content.contains("\"q\":\"x\""))
    }

    // MARK: - Helpers

    private func captureChatBody(
        modelID: String,
        messages: [Message] = [Message(role: .user, content: [.text("hi")])],
        controls: GenerationControls,
        tools: [ToolDefinition] = []
    ) async throws -> [String: Any] {
        var captured: [String: Any] = [:]
        let (configuration, protocolType) = makeMakoraMockedSession()
        let networkManager = NetworkManager(configuration: configuration)
        protocolType.requestHandler = { request in
            let data = try XCTUnwrap(makoraRequestBodyData(request))
            captured = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, makoraEmptyCompletionData())
        }

        let adapter = MakoraAdapter(
            providerConfig: makeMakoraConfig(),
            apiKey: "test-key",
            networkManager: networkManager
        )
        let stream = try await adapter.sendMessage(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: false
        )
        for try await _ in stream {}
        return captured
    }

    private func captureChatURL(
        modelID: String,
        controls: GenerationControls
    ) async throws -> String {
        var captured = ""
        let (configuration, protocolType) = makeMakoraMockedSession()
        let networkManager = NetworkManager(configuration: configuration)
        protocolType.requestHandler = { request in
            captured = request.url?.absoluteString ?? ""
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, makoraEmptyCompletionData())
        }

        let adapter = MakoraAdapter(
            providerConfig: makeMakoraConfig(),
            apiKey: "test-key",
            networkManager: networkManager
        )
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: modelID,
            controls: controls,
            tools: [],
            streaming: false
        )
        for try await _ in stream {}
        return captured
    }
}

final class MakoraToolCallRepairTests: XCTestCase {
    func testParsesGLMToolCallXML() {
        let text = """
        hello
        <tool_call>
        <tool_name>lookup</tool_name>
        <parameters>{"q":"x"}</parameters>
        </tool_call>
        """
        let parsed = MakoraToolCallRepair.parse(text, modelID: "zai-org/GLM-5.1-FP8")
        XCTAssertEqual(parsed, [MakoraToolCallRepair.ParsedCall(name: "lookup", argumentsJSON: "{\"q\":\"x\"}")])
        XCTAssertEqual(MakoraToolCallRepair.textBeforeTools(text, modelID: "zai-org/GLM-5.1-FP8"), "hello")
    }

    func testParsesKimiToolCallTokens() {
        let text = "<|tool_call_begin|>search\n{\"q\":\"hi\"}<|tool_call_end|>"
        let parsed = MakoraToolCallRepair.parse(text, modelID: "nvidia/Kimi-K2.6-NVFP4")
        XCTAssertEqual(parsed.map(\.name), ["search"])
    }

    func testParsesQwenFunctionXML() {
        let text = "<function=run>{\"cmd\":\"ls\"}</function>"
        let parsed = MakoraToolCallRepair.parse(text, modelID: "unsloth/Qwen3.6-27B-NVFP4")
        XCTAssertEqual(parsed, [MakoraToolCallRepair.ParsedCall(name: "run", argumentsJSON: "{\"cmd\":\"ls\"}")])
    }
}

private func makeMakoraLookupTool() -> ToolDefinition {
    ToolDefinition(
        id: "t",
        name: "lookup",
        description: "d",
        parameters: ParameterSchema(
            properties: [
                "q": PropertySchema(type: "string", description: "query")
            ],
            required: ["q"]
        ),
        source: .builtin
    )
}

private func makeMakoraConfig() -> ProviderConfig {
    ProviderConfig(
        id: "makora",
        name: "Makora",
        type: .makora,
        apiKey: "ignored",
        baseURL: ProviderType.makora.defaultBaseURL,
        models: ModelCatalog.seededModels(for: .makora)
    )
}

private func makeMakoraMockedSession() -> (URLSessionConfiguration, MakoraMockURLProtocol.Type) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MakoraMockURLProtocol.self]
    return (config, MakoraMockURLProtocol.self)
}

private func makoraEmptyCompletionData() -> Data {
    let response: [String: Any] = [
        "id": "cmpl_test",
        "choices": [
            [
                "message": ["role": "assistant", "content": "ok"],
                "finish_reason": "stop",
            ]
        ],
    ]
    return (try? JSONSerialization.data(withJSONObject: response)) ?? Data()
}

private func makoraRequestBodyData(_ request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 16 * 1024)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data
}

private final class MakoraMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
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
