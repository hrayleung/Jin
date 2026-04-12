import XCTest
@testable import Jin

final class AdapterRequestConstructionTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        AdapterRequestConstructionMockURLProtocol.requestHandler = nil
    }

    func testOpenRouterAdapterFetchModelsIncludesOpenRouterHeaders() async throws {
        let (configuration, protocolType) = makeAdapterRequestConstructionSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "or",
            name: "OpenRouter",
            type: .openrouter,
            apiKey: "ignored",
            baseURL: "https://openrouter.ai"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "HTTP-Referer"), "https://jin.app")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Title"), "Jin")

            let payload: [String: Any] = [
                "data": [
                    [
                        "id": "openai/gpt-4o",
                        "architecture": [
                            "input_modalities": ["text", "image"]
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let adapter = OpenRouterAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()

        XCTAssertEqual(models.first?.id, "openai/gpt-4o")
    }

    func testOpenRouterAdapterFetchModelsUsesCatalogAndAPIModelMetadata() async throws {
        let (configuration, protocolType) = makeAdapterRequestConstructionSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "or",
            name: "OpenRouter",
            type: .openrouter,
            apiKey: "ignored",
            baseURL: "https://openrouter.ai/api/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/models")

            let payload: [String: Any] = [
                "data": [
                    [
                        "id": "xiaomi/mimo-v2-omni",
                        "name": "Xiaomi: MiMo-V2-Omni",
                        "context_length": 262_144,
                        "architecture": [
                            "input_modalities": ["text", "image", "audio", "video"],
                            "output_modalities": ["text"],
                        ],
                        "supported_parameters": ["reasoning", "tools", "tool_choice"],
                        "top_provider": [
                            "context_length": 262_144,
                            "max_completion_tokens": 65_536,
                        ],
                        "pricing": [
                            "input_cache_read": "0.00000008",
                        ],
                    ],
                    [
                        "id": "vendor/unknown-vision-reasoner",
                        "name": "Unknown Vision Reasoner",
                        "context_length": 321_000,
                        "architecture": [
                            "input_modalities": ["text", "image"],
                            "output_modalities": ["text"],
                        ],
                        "supported_parameters": ["reasoning", "tools"],
                        "top_provider": [
                            "max_completion_tokens": 12_345,
                        ],
                        "pricing": [
                            "input_cache_read": "0.00000001",
                        ],
                    ],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let adapter = OpenRouterAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        let mimoOmni = try XCTUnwrap(byID["xiaomi/mimo-v2-omni"])
        XCTAssertEqual(mimoOmni.name, "MiMo V2 Omni")
        XCTAssertEqual(mimoOmni.contextWindow, 262_144)
        XCTAssertEqual(mimoOmni.maxOutputTokens, 65_536)
        XCTAssertTrue(mimoOmni.capabilities.contains(.toolCalling))
        XCTAssertTrue(mimoOmni.capabilities.contains(.vision))
        XCTAssertTrue(mimoOmni.capabilities.contains(.audio))
        XCTAssertTrue(mimoOmni.capabilities.contains(.reasoning))
        XCTAssertTrue(mimoOmni.capabilities.contains(.promptCaching))
        XCTAssertEqual(mimoOmni.reasoningConfig?.type, .effort)

        let unknown = try XCTUnwrap(byID["vendor/unknown-vision-reasoner"])
        XCTAssertEqual(unknown.name, "Unknown Vision Reasoner")
        XCTAssertEqual(unknown.contextWindow, 321_000)
        XCTAssertEqual(unknown.maxOutputTokens, 12_345)
        XCTAssertTrue(unknown.capabilities.contains(.toolCalling))
        XCTAssertTrue(unknown.capabilities.contains(.vision))
        XCTAssertTrue(unknown.capabilities.contains(.reasoning))
        XCTAssertTrue(unknown.capabilities.contains(.promptCaching))
        XCTAssertEqual(unknown.reasoningConfig?.type, .effort)
    }

    func testOpenAICompatibleGitHubCatalogFetchIncludesGitHubHeaders() async throws {
        let (configuration, protocolType) = makeAdapterRequestConstructionSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "gh",
            name: "GitHub Models",
            type: .githubCopilot,
            apiKey: "ignored",
            baseURL: "https://models.github.ai/inference"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://models.github.ai/catalog/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), jinUserAgent)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")

            let payload: [[String: Any]] = [
                [
                    "id": "openai/gpt-4o",
                    "name": "GPT-4o",
                    "supported_output_modalities": ["text"],
                    "supported_input_modalities": ["text", "image"],
                    "max_input_tokens": 128_000,
                    "max_output_tokens": 16_384,
                    "capabilities": ["streaming", "tool_calling"]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let adapter = OpenAICompatibleAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()

        XCTAssertEqual(models.first?.id, "openai/gpt-4o")
    }

    func testPerplexityAdapterBuildsChatRequestThroughSharedFactory() async throws {
        let (configuration, protocolType) = makeAdapterRequestConstructionSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "pplx",
            name: "Perplexity",
            type: .perplexity,
            apiKey: "ignored"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.perplexity.ai/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

            let bodyData = try XCTUnwrap(adapterRequestBodyData(request))
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            XCTAssertEqual(root["model"] as? String, "sonar-reasoning-pro")
            XCTAssertEqual(root["stream"] as? Bool, false)
            XCTAssertEqual((root["max_tokens"] as? NSNumber)?.intValue, 32)
            XCTAssertEqual((root["top_p"] as? NSNumber)?.doubleValue, 0.9)
            XCTAssertEqual(root["reasoning_effort"] as? String, "high")
            XCTAssertEqual(root["disable_search"] as? Bool, true)
            XCTAssertEqual(root["has_image_url"] as? Bool, true)

            let tools = try XCTUnwrap(root["tools"] as? [[String: Any]])
            XCTAssertEqual(tools.count, 1)

            let response: [String: Any] = [
                "id": "resp_test",
                "choices": [
                    [
                        "message": [
                            "content": "ok"
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let adapter = PerplexityAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let tool = ToolDefinition(
            id: "lookup",
            name: "lookup",
            description: "Lookup something",
            parameters: ParameterSchema(
                properties: [
                    "q": PropertySchema(type: "string", description: "query")
                ],
                required: ["q"]
            ),
            source: .builtin
        )

        let messages: [Message] = [
            Message(
                role: .user,
                content: [
                    .text("What is in this image?"),
                    .image(ImageContent(mimeType: "image/png", data: Data([0x89, 0x50, 0x4e, 0x47]), url: nil))
                ]
            )
        ]

        let controls = GenerationControls(
            maxTokens: 32,
            topP: 0.9,
            reasoning: ReasoningControls(enabled: true, effort: .high),
            webSearch: WebSearchControls(enabled: false)
        )

        let stream = try await adapter.sendMessage(
            messages: messages,
            modelID: "sonar-reasoning-pro",
            controls: controls,
            tools: [tool],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testClaudeManagedAgentsCreatesSessionUsesManagedStreamEndpointAndSendsCustomToolResultEvent() async throws {
        let (configuration, protocolType) = makeAdapterRequestConstructionSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "claude-managed",
            name: "Claude Managed Agents",
            type: .claudeManagedAgents,
            apiKey: "ignored",
            baseURL: "https://api.anthropic.com"
        )

        var observedRequests: [URLRequest] = []
        protocolType.requestHandler = { request in
            observedRequests.append(request)

            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/v1/sessions"):
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
                XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "managed-agents-2026-04-01")

                let bodyData = try XCTUnwrap(adapterRequestBodyData(request))
                let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
                XCTAssertEqual(root["agent"] as? String, "agent_123")
                XCTAssertEqual(root["environment_id"] as? String, "env_456")
                XCTAssertNil(root["model"])
                XCTAssertNil(root["system"])
                XCTAssertNil(root["tools"])

                let payload = ["id": "sess_123"]
                let data = try JSONSerialization.data(withJSONObject: payload)
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data
                )

            case ("POST", "/v1/sessions/sess_123/events"):
                let bodyData = try XCTUnwrap(adapterRequestBodyData(request))
                let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
                let events = try XCTUnwrap(root["events"] as? [[String: Any]])
                XCTAssertEqual(events.count, 1)
                let event = events[0]
                XCTAssertEqual(event["type"] as? String, "user.custom_tool_result")
                XCTAssertEqual(event["custom_tool_use_id"] as? String, "evt_custom_1")
                XCTAssertEqual(event["session_thread_id"] as? String, "sthread_1")
                XCTAssertEqual(event["is_error"] as? Bool, false)

                let content = try XCTUnwrap(event["content"] as? [[String: Any]])
                XCTAssertEqual(content.first?["type"] as? String, "text")
                XCTAssertEqual(content.first?["text"] as? String, "tool output")

                let data = try JSONSerialization.data(withJSONObject: ["ok": true])
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data
                )

            case ("GET", "/v1/sessions/sess_123/events/stream"):
                let data = Data()
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data
                )

            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "nil") \(request.url?.absoluteString ?? "nil")")
                throw URLError(.badServerResponse)
            }
        }

        let adapter = ClaudeManagedAgentsAdapter(
            providerConfig: providerConfig,
            apiKey: "test-key",
            networkManager: networkManager
        )

        var controls = GenerationControls()
        controls.claudeManagedAgentID = "agent_123"
        controls.claudeManagedEnvironmentID = "env_456"
        controls.claudeManagedPendingCustomToolResults = [
            ClaudeManagedAgentPendingToolResult(
                eventID: "evt_custom_1",
                toolCallID: "toolu_1",
                toolName: "workspace_search",
                content: "tool output",
                isError: false,
                sessionThreadID: "sthread_1"
            )
        ]

        let messages: [Message] = [
            Message(role: .system, content: [.text("System prompt")]),
            Message(role: .tool, content: [], toolResults: [
                ToolResult(toolCallID: "toolu_1", toolName: "workspace_search", content: "tool output")
            ])
        ]

        let stream = try await adapter.sendMessage(
            messages: messages,
            modelID: "claude-sonnet-4-6",
            controls: controls,
            tools: [],
            streaming: true
        )

        for try await _ in stream {}

        XCTAssertEqual(observedRequests.count, 3)
        XCTAssertEqual(observedRequests[0].url?.absoluteString, "https://api.anthropic.com/v1/sessions?beta=true")
        XCTAssertEqual(observedRequests[1].url?.absoluteString, "https://api.anthropic.com/v1/sessions/sess_123/events/stream?beta=true")
        XCTAssertEqual(observedRequests[2].url?.absoluteString, "https://api.anthropic.com/v1/sessions/sess_123/events?beta=true")
    }
}

private final class AdapterRequestConstructionMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

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

private func makeAdapterRequestConstructionSessionConfiguration() -> (URLSessionConfiguration, AdapterRequestConstructionMockURLProtocol.Type) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AdapterRequestConstructionMockURLProtocol.self]
    return (config, AdapterRequestConstructionMockURLProtocol.self)
}

private func adapterRequestBodyData(_ request: URLRequest) -> Data? {
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
        if read < 0 {
            return nil
        }
        if read == 0 {
            break
        }
        data.append(buffer, count: read)
    }

    return data
}
