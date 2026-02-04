import Foundation
import XCTest
@testable import Jin

final class ChatCompletionsAdaptersTests: XCTestCase {
    func testFireworksAdapterBuildsRequestWithReasoningContentToolCallsAndToolResults() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "fw",
            name: "Fireworks",
            type: .fireworks,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "fireworks/kimi-k2p5")
            XCTAssertEqual(root["stream"] as? Bool, false)

            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 4)
            XCTAssertEqual(messages[0]["role"] as? String, "system")
            XCTAssertEqual(messages[0]["content"] as? String, "sys")
            XCTAssertEqual(messages[1]["role"] as? String, "user")
            XCTAssertEqual(messages[1]["content"] as? String, "hi")

            XCTAssertEqual(messages[2]["role"] as? String, "assistant")
            XCTAssertEqual(messages[2]["content"] as? String, "answer")
            XCTAssertEqual(messages[2]["reasoning_content"] as? String, "think")

            let toolCalls = try XCTUnwrap(messages[2]["tool_calls"] as? [[String: Any]])
            XCTAssertEqual(toolCalls.count, 1)
            XCTAssertEqual(toolCalls[0]["id"] as? String, "call_1")
            let fn = try XCTUnwrap(toolCalls[0]["function"] as? [String: Any])
            XCTAssertEqual(fn["name"] as? String, "tool_name")
            XCTAssertEqual(fn["arguments"] as? String, "{\"q\":\"x\"}")

            XCTAssertEqual(messages[3]["role"] as? String, "tool")
            XCTAssertEqual(messages[3]["tool_call_id"] as? String, "call_1")
            XCTAssertEqual(messages[3]["content"] as? String, "tool result")

            // Minimal response with both content + reasoning_content.
            let response: [String: Any] = [
                "id": "cmpl_123",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK",
                            "reasoning_content": "R"
                        ],
                        "finish_reason": "stop"
                    ]
                ],
                "usage": [
                    "prompt_tokens": 1,
                    "completion_tokens": 2,
                    "total_tokens": 3
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = FireworksAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let tool = ToolDefinition(
            id: "t",
            name: "tool_name",
            description: "desc",
            parameters: ParameterSchema(
                properties: [
                    "q": PropertySchema(type: "string", description: "query")
                ],
                required: ["q"]
            ),
            source: .builtin
        )

        let messages: [Message] = [
            Message(role: .system, content: [.text("sys")]),
            Message(role: .user, content: [.text("hi")]),
            Message(
                role: .assistant,
                content: [.text("answer"), .thinking(ThinkingBlock(text: "think"))],
                toolCalls: [ToolCall(id: "call_1", name: "tool_name", arguments: ["q": AnyCodable("x")])]
            ),
            Message(
                role: .tool,
                content: [],
                toolResults: [ToolResult(toolCallID: "call_1", toolName: "tool_name", content: "tool result")]
            )
        ]

        let stream = try await adapter.sendMessage(
            messages: messages,
            modelID: "fireworks/kimi-k2p5",
            controls: GenerationControls(),
            tools: [tool],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 4)

        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "cmpl_123")

        guard case .thinkingDelta(.thinking(let reasoning, _)) = events[1] else { return XCTFail("Expected thinkingDelta") }
        XCTAssertEqual(reasoning, "R")

        guard case .contentDelta(.text(let content)) = events[2] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "OK")

        guard case .messageEnd(let usage) = events[3] else { return XCTFail("Expected messageEnd") }
        XCTAssertEqual(usage?.inputTokens, 1)
        XCTAssertEqual(usage?.outputTokens, 2)
    }

    func testCerebrasAdapterClampsTemperatureAndSendsReasoningField() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "c",
            name: "Cerebras",
            type: .cerebras,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "zai-glm-4.7")
            XCTAssertEqual(root["max_completion_tokens"] as? Int, 123)
            XCTAssertEqual(root["temperature"] as? Double, 1.5)

            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 1)
            XCTAssertEqual(messages[0]["role"] as? String, "assistant")
            XCTAssertEqual(messages[0]["content"] as? String, "<think>think</think>\nanswer")
            XCTAssertNil(messages[0]["reasoning"])

            let response: [String: Any] = [
                "id": "cmpl_456",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK",
                            "reasoning": "R"
                        ],
                        "finish_reason": "stop"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = CerebrasAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .assistant, content: [.text("answer"), .thinking(ThinkingBlock(text: "think"))])
            ],
            modelID: "zai-glm-4.7",
            controls: GenerationControls(temperature: 2.0, maxTokens: 123),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 4)
        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "cmpl_456")
        guard case .thinkingDelta(.thinking(let reasoning, _)) = events[1] else { return XCTFail("Expected thinkingDelta") }
        XCTAssertEqual(reasoning, "R")
        guard case .contentDelta(.text(let content)) = events[2] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "OK")
        guard case .messageEnd = events[3] else { return XCTFail("Expected messageEnd") }
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
