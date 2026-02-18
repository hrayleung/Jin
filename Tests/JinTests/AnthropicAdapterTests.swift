import Foundation
import XCTest
@testable import Jin

final class AnthropicAdapterTests: XCTestCase {
    func testAnthropicAdapterDefaultsMaxTokensToClaude45ModelLimitWhenMissing() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "claude-sonnet-4-5-20250929")
            XCTAssertEqual(root["max_tokens"] as? Int, 64000)

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "claude-sonnet-4-5-20250929",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, budgetTokens: 2048)),
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicAdapterCapsMaxTokensToClaude45ModelLimit() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "claude-haiku-4-5-20251001")
            XCTAssertEqual(root["max_tokens"] as? Int, 64000)

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "claude-haiku-4-5-20251001",
            controls: GenerationControls(maxTokens: 999_999),
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicOpus46BuildsAdaptiveThinkingAndEffortRequest() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/messages")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "fine-grained-tool-streaming-2025-05-14")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "claude-opus-4-6")
            XCTAssertEqual(root["stream"] as? Bool, true)
            XCTAssertEqual(root["max_tokens"] as? Int, 3210)
            XCTAssertNil(root["temperature"])
            XCTAssertNil(root["top_p"])

            let thinking = try XCTUnwrap(root["thinking"] as? [String: Any])
            XCTAssertEqual(thinking["type"] as? String, "adaptive")
            XCTAssertNil(thinking["budget_tokens"])

            let outputConfig = try XCTUnwrap(root["output_config"] as? [String: Any])
            XCTAssertEqual(outputConfig["effort"] as? String, "max")

            let format = try XCTUnwrap(outputConfig["format"] as? [String: Any])
            XCTAssertEqual(format["type"] as? String, "json_schema")
            XCTAssertEqual(format["name"] as? String, "AgentOutput")

            let schema = try XCTUnwrap(format["schema"] as? [String: Any])
            XCTAssertEqual(schema["type"] as? String, "object")

            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 1)
            XCTAssertEqual(messages[0]["role"] as? String, "user")

            let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
            XCTAssertEqual(content.count, 1)
            XCTAssertEqual(content[0]["type"] as? String, "text")
            XCTAssertEqual(content[0]["text"] as? String, "hi")

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let controls = GenerationControls(
            maxTokens: 3210,
            reasoning: ReasoningControls(enabled: true, effort: .xhigh),
            providerSpecific: [
                "anthropic_beta": AnyCodable("fine-grained-tool-streaming-2025-05-14"),
                "output_format": AnyCodable([
                    "type": "json_schema",
                    "name": "AgentOutput",
                    "schema": [
                        "type": "object",
                        "properties": [
                            "answer": ["type": "string"]
                        ],
                        "required": ["answer"]
                    ]
                ])
            ]
        )

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "claude-opus-4-6",
            controls: controls,
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicSonnet46BuildsAdaptiveThinkingWithoutMaxEffort() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "claude-sonnet-4-6")
            XCTAssertEqual(root["max_tokens"] as? Int, 64000)
            XCTAssertNil(root["temperature"])
            XCTAssertNil(root["top_p"])

            let thinking = try XCTUnwrap(root["thinking"] as? [String: Any])
            XCTAssertEqual(thinking["type"] as? String, "adaptive")
            XCTAssertNil(thinking["budget_tokens"])

            let outputConfig = try XCTUnwrap(root["output_config"] as? [String: Any])
            XCTAssertEqual(outputConfig["effort"] as? String, "high")

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let controls = GenerationControls(
            temperature: 0.3,
            maxTokens: 999_999,
            topP: 0.8,
            reasoning: ReasoningControls(enabled: true, effort: .xhigh)
        )

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "claude-sonnet-4-6",
            controls: controls,
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicOpus45BuildsBudgetThinkingWithoutEffortOutputConfig() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "claude-opus-4-5-20251101")

            let thinking = try XCTUnwrap(root["thinking"] as? [String: Any])
            XCTAssertEqual(thinking["type"] as? String, "enabled")
            XCTAssertEqual(thinking["budget_tokens"] as? Int, 4096)

            let outputConfig = root["output_config"] as? [String: Any]
            XCTAssertNil(outputConfig?["effort"])

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let controls = GenerationControls(
            reasoning: ReasoningControls(enabled: true, budgetTokens: 4096)
        )

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "claude-opus-4-5-20251101",
            controls: controls,
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicStreamingUsageParsingIncludesInputOutputAndCacheRead() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/messages")

            let sse = """
            event: message_start
            data: {"type":"message_start","message":{"id":"msg_123","type":"message","role":"assistant","model":"claude-opus-4-6","usage":{"input_tokens":120,"cache_read_input_tokens":40,"cache_creation_input_tokens":18}}}

            event: content_block_start
            data: {"type":"content_block_start","index":0,"content_block":{"type":"text"}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

            event: message_delta
            data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":25}}

            event: message_stop
            data: {"type":"message_stop"}

            data: [DONE]

            """

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(sse.utf8)
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "claude-opus-4-6",
            controls: GenerationControls(),
            tools: [],
            streaming: true
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertGreaterThanOrEqual(events.count, 4)

        guard case .messageStart(let id) = events[0] else {
            return XCTFail("Expected messageStart")
        }
        XCTAssertEqual(id, "msg_123")

        let hasContentDelta = events.contains { event in
            guard case .contentDelta(.text(let text)) = event else { return false }
            return text == "Hello"
        }
        XCTAssertTrue(hasContentDelta)

        let usageEvents = events.compactMap { event -> Usage? in
            if case .messageEnd(let usage) = event {
                return usage
            }
            return nil
        }

        XCTAssertFalse(usageEvents.isEmpty)
        let usageWithValues = try XCTUnwrap(usageEvents.first)
        XCTAssertEqual(usageWithValues.inputTokens, 120)
        XCTAssertEqual(usageWithValues.outputTokens, 25)
        XCTAssertEqual(usageWithValues.cachedTokens, 40)
        XCTAssertEqual(usageWithValues.cacheCreationTokens, 18)
        XCTAssertEqual(usageWithValues.cacheWriteTokens, 18)
    }

    func testAnthropicModelLimitsKnownClaude45AndClaude46Series() {
        XCTAssertEqual(AnthropicModelLimits.maxOutputTokens(for: "claude-opus-4-6"), 128000)
        XCTAssertEqual(AnthropicModelLimits.maxOutputTokens(for: "claude-sonnet-4-6"), 64000)
        XCTAssertEqual(AnthropicModelLimits.maxOutputTokens(for: "claude-opus-4-5-20251101"), 64000)
        XCTAssertEqual(AnthropicModelLimits.maxOutputTokens(for: "claude-sonnet-4-5-20250929"), 64000)
        XCTAssertEqual(AnthropicModelLimits.maxOutputTokens(for: "claude-haiku-4-5-20251001"), 64000)
        XCTAssertNil(AnthropicModelLimits.maxOutputTokens(for: "claude-3-5-sonnet-20241022"))
    }

    func testAnthropicThinkingCapabilitiesSplit46From45Series() {
        XCTAssertTrue(AnthropicModelLimits.supportsAdaptiveThinking(for: "claude-opus-4-6"))
        XCTAssertTrue(AnthropicModelLimits.supportsEffort(for: "claude-opus-4-6"))
        XCTAssertTrue(AnthropicModelLimits.supportsMaxEffort(for: "claude-opus-4-6"))

        XCTAssertTrue(AnthropicModelLimits.supportsAdaptiveThinking(for: "claude-sonnet-4-6"))
        XCTAssertTrue(AnthropicModelLimits.supportsEffort(for: "claude-sonnet-4-6"))
        XCTAssertFalse(AnthropicModelLimits.supportsMaxEffort(for: "claude-sonnet-4-6"))

        XCTAssertFalse(AnthropicModelLimits.supportsAdaptiveThinking(for: "claude-opus-4-5-20251101"))
        XCTAssertFalse(AnthropicModelLimits.supportsEffort(for: "claude-opus-4-5-20251101"))
        XCTAssertFalse(AnthropicModelLimits.supportsMaxEffort(for: "claude-opus-4-5-20251101"))
    }
}

// MARK: - URLProtocol stubbing

private final class MockURLProtocol: URLProtocol {
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

private func makeMockedURLSession() -> (URLSession, MockURLProtocol.Type) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return (URLSession(configuration: config), MockURLProtocol.self)
}

private func requestBodyData(_ request: URLRequest) -> Data? {
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
