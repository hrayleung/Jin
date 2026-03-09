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
