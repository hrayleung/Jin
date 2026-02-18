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

    func testFireworksAdapterOmitsReasoningEffortNoneForMiniMaxM2Family() async throws {
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

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "fireworks/minimax-m2p5")
            XCTAssertNil(root["reasoning_effort"])

            let response: [String: Any] = [
                "id": "cmpl_789",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK"
                        ],
                        "finish_reason": "stop"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = FireworksAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "fireworks/minimax-m2p5",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: false)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testFireworksAdapterSanitizesMiniMaxProviderSpecificReasoningOverrides() async throws {
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
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            // `none` is invalid for MiniMax M2 family; adapter should keep control-driven effort.
            XCTAssertEqual(root["reasoning_effort"] as? String, "high")
            // MiniMax M2 family does not support preserved history.
            XCTAssertNil(root["reasoning_history"])

            let response: [String: Any] = [
                "id": "cmpl_790",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK"
                        ],
                        "finish_reason": "stop"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        var controls = GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .high))
        controls.providerSpecific = [
            "reasoning_effort": AnyCodable("none"),
            "reasoning_history": AnyCodable("preserved")
        ]

        let adapter = FireworksAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "fireworks/minimax-m2p5",
            controls: controls,
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testFireworksAdapterFetchModelsMapsKnownMetadata() async throws {
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
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let response: [String: Any] = [
                "data": [
                    ["id": "fireworks/glm-5"],
                    ["id": "fireworks/minimax-m2p5"],
                    ["id": "accounts/fireworks/models/minimax-m2p1"],
                    ["id": "accounts/fireworks/models/minimax-m2"],
                    ["id": "accounts/fireworks/models/glm-4p7"],
                    ["id": "accounts/fireworks/models/kimi-k2p5"],
                    ["id": "accounts/fireworks/models/glm-preview"],
                    ["id": "accounts/fireworks/models/other"]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = FireworksAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        let glm5 = try XCTUnwrap(byID["fireworks/glm-5"])
        XCTAssertEqual(glm5.name, "GLM-5")
        XCTAssertEqual(glm5.contextWindow, 202_800)
        XCTAssertTrue(glm5.capabilities.contains(.reasoning))
        XCTAssertFalse(glm5.capabilities.contains(.vision))

        let minimaxM2p5 = try XCTUnwrap(byID["fireworks/minimax-m2p5"])
        XCTAssertEqual(minimaxM2p5.name, "MiniMax M2.5")
        XCTAssertEqual(minimaxM2p5.contextWindow, 204_800)
        XCTAssertTrue(minimaxM2p5.capabilities.contains(.reasoning))
        XCTAssertFalse(minimaxM2p5.capabilities.contains(.vision))

        let minimaxM2p1 = try XCTUnwrap(byID["accounts/fireworks/models/minimax-m2p1"])
        XCTAssertEqual(minimaxM2p1.name, "MiniMax M2.1")
        XCTAssertEqual(minimaxM2p1.contextWindow, 204_800)
        XCTAssertTrue(minimaxM2p1.capabilities.contains(.reasoning))
        XCTAssertFalse(minimaxM2p1.capabilities.contains(.vision))

        let minimaxM2 = try XCTUnwrap(byID["accounts/fireworks/models/minimax-m2"])
        XCTAssertEqual(minimaxM2.name, "MiniMax M2")
        XCTAssertEqual(minimaxM2.contextWindow, 196_600)
        XCTAssertTrue(minimaxM2.capabilities.contains(.reasoning))
        XCTAssertFalse(minimaxM2.capabilities.contains(.vision))

        let glm4p7 = try XCTUnwrap(byID["accounts/fireworks/models/glm-4p7"])
        XCTAssertEqual(glm4p7.name, "GLM-4.7")
        XCTAssertEqual(glm4p7.contextWindow, 202_800)
        XCTAssertTrue(glm4p7.capabilities.contains(.reasoning))
        XCTAssertFalse(glm4p7.capabilities.contains(.vision))

        let kimiK2p5 = try XCTUnwrap(byID["accounts/fireworks/models/kimi-k2p5"])
        XCTAssertEqual(kimiK2p5.name, "Kimi K2.5")
        XCTAssertEqual(kimiK2p5.contextWindow, 262_100)
        XCTAssertTrue(kimiK2p5.capabilities.contains(.reasoning))
        XCTAssertTrue(kimiK2p5.capabilities.contains(.vision))

        let glmPreview = try XCTUnwrap(byID["accounts/fireworks/models/glm-preview"])
        XCTAssertFalse(glmPreview.capabilities.contains(.reasoning))
        XCTAssertNil(glmPreview.reasoningConfig)
        XCTAssertEqual(glmPreview.contextWindow, 128000)

        let other = try XCTUnwrap(byID["accounts/fireworks/models/other"])
        XCTAssertEqual(other.name, "accounts/fireworks/models/other")
        XCTAssertEqual(other.contextWindow, 128000)
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
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/chat/completions")
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

    func testDeepSeekAdapterUsesV1RouteAndParsesReasoningAndToolCalls() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "ds",
            name: "DeepSeek",
            type: .deepseek,
            apiKey: "ignored",
            baseURL: "https://api.deepseek.com/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "deepseek-chat")
            XCTAssertEqual(root["stream"] as? Bool, false)

            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 1)
            XCTAssertEqual(messages[0]["role"] as? String, "user")
            XCTAssertEqual(messages[0]["content"] as? String, "hello")

            let response: [String: Any] = [
                "id": "cmpl_ds_1",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "Answer",
                            "reasoning_content": "Reason",
                            "tool_calls": [
                                [
                                    "id": "call_1",
                                    "type": "function",
                                    "function": [
                                        "name": "search_docs",
                                        "arguments": "{\"q\":\"swift\"}"
                                    ]
                                ]
                            ]
                        ],
                        "finish_reason": "stop"
                    ]
                ],
                "usage": [
                    "prompt_tokens": 4,
                    "completion_tokens": 7,
                    "total_tokens": 11
                ]
            ]

            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = DeepSeekAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "deepseek-chat",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 6)

        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "cmpl_ds_1")

        guard case .thinkingDelta(.thinking(let reasoning, _)) = events[1] else { return XCTFail("Expected thinkingDelta") }
        XCTAssertEqual(reasoning, "Reason")

        guard case .contentDelta(.text(let content)) = events[2] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "Answer")

        guard case .toolCallStart(let startCall) = events[3] else { return XCTFail("Expected toolCallStart") }
        XCTAssertEqual(startCall.id, "call_1")
        XCTAssertEqual(startCall.name, "search_docs")

        guard case .toolCallEnd(let endCall) = events[4] else { return XCTFail("Expected toolCallEnd") }
        XCTAssertEqual(endCall.id, "call_1")
        XCTAssertEqual(endCall.name, "search_docs")
        XCTAssertEqual(endCall.arguments["q"]?.value as? String, "swift")

        guard case .messageEnd(let usage) = events[5] else { return XCTFail("Expected messageEnd") }
        XCTAssertEqual(usage?.inputTokens, 4)
        XCTAssertEqual(usage?.outputTokens, 7)
    }

    func testDeepSeekAdapterUsesBetaRouteForV32ExpModelOnDefaultHost() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "ds",
            name: "DeepSeek",
            type: .deepseek,
            apiKey: "ignored",
            baseURL: "https://api.deepseek.com/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/beta/chat/completions")

            let response: [String: Any] = [
                "id": "cmpl_ds_2",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK"
                        ],
                        "finish_reason": "stop"
                    ]
                ]
            ]

            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = DeepSeekAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "deepseek-v3.2-exp",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 3)
        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "cmpl_ds_2")
        guard case .contentDelta(.text(let content)) = events[1] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "OK")
        guard case .messageEnd = events[2] else { return XCTFail("Expected messageEnd") }
    }

    func testOpenRouterAdapterBuildsChatCompletionsRequestWithReasoningAndWebPlugin() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "or",
            name: "OpenRouter",
            type: .openrouter,
            apiKey: "ignored",
            baseURL: "https://openrouter.ai/api/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "openai/gpt-5")
            XCTAssertEqual(root["stream"] as? Bool, false)

            let reasoning = try XCTUnwrap(root["reasoning"] as? [String: Any])
            XCTAssertEqual(reasoning["effort"] as? String, "medium")
            XCTAssertEqual(root["include_reasoning"] as? Bool, true)

            let plugins = try XCTUnwrap(root["plugins"] as? [[String: Any]])
            XCTAssertEqual(plugins.count, 1)
            XCTAssertEqual(plugins[0]["id"] as? String, "web")

            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 1)
            XCTAssertEqual(messages[0]["role"] as? String, "assistant")
            XCTAssertEqual(messages[0]["content"] as? String, "answer")
            XCTAssertEqual(messages[0]["reasoning"] as? String, "think")

            let response: [String: Any] = [
                "id": "cmpl_or_1",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK",
                            "reasoning": "R"
                        ],
                        "finish_reason": "stop"
                    ]
                ],
                "usage": [
                    "prompt_tokens": 3,
                    "completion_tokens": 5,
                    "total_tokens": 8
                ]
            ]

            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenRouterAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .assistant, content: [.text("answer"), .thinking(ThinkingBlock(text: "think"))])],
            modelID: "openai/gpt-5",
            controls: GenerationControls(
                reasoning: ReasoningControls(enabled: true, effort: .medium),
                webSearch: WebSearchControls(enabled: true)
            ),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 4)
        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "cmpl_or_1")
        guard case .thinkingDelta(.thinking(let reasoning, _)) = events[1] else { return XCTFail("Expected thinkingDelta") }
        XCTAssertEqual(reasoning, "R")
        guard case .contentDelta(.text(let content)) = events[2] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "OK")
        guard case .messageEnd(let usage) = events[3] else { return XCTFail("Expected messageEnd") }
        XCTAssertEqual(usage?.inputTokens, 3)
        XCTAssertEqual(usage?.outputTokens, 5)
    }

    func testOpenRouterAdapterOmitsWebPluginWhenModelWebSearchOverrideIsDisabled() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "or",
            name: "OpenRouter",
            type: .openrouter,
            apiKey: "ignored",
            baseURL: "https://openrouter.ai/api/v1",
            models: [
                ModelInfo(
                    id: "openai/gpt-5",
                    name: "openai/gpt-5",
                    capabilities: [.streaming, .toolCalling, .reasoning],
                    contextWindow: 128_000,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
                    overrides: ModelOverrides(webSearchSupported: false)
                )
            ]
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertNil(root["plugins"])

            let response: [String: Any] = [
                "id": "cmpl_or_no_web_plugin",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK"
                        ],
                        "finish_reason": "stop"
                    ]
                ]
            ]

            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenRouterAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "openai/gpt-5",
            controls: GenerationControls(webSearch: WebSearchControls(enabled: true)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenRouterAdapterSendsXHighEffortForGPT52Models() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "or",
            name: "OpenRouter",
            type: .openrouter,
            apiKey: "ignored",
            baseURL: "https://openrouter.ai/api/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            let reasoning = try XCTUnwrap(root["reasoning"] as? [String: Any])
            XCTAssertEqual(reasoning["effort"] as? String, "xhigh")

            let response: [String: Any] = [
                "id": "cmpl_or_xhigh",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK"
                        ],
                        "finish_reason": "stop"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenRouterAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "openai/gpt-5.2",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .xhigh)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenRouterAdapterParsesReasoningDetailsWhenReasoningFieldIsMissing() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "or",
            name: "OpenRouter",
            type: .openrouter,
            apiKey: "ignored",
            baseURL: "https://openrouter.ai/api/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")

            let response: [String: Any] = [
                "id": "cmpl_or_reasoning_details",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK"
                        ],
                        "reasoning_details": [
                            [
                                "type": "reasoning.text",
                                "text": "R"
                            ]
                        ],
                        "finish_reason": "stop"
                    ]
                ]
            ]

            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenRouterAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "google/gemini-3-pro-preview",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .low)),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 4)
        guard case .thinkingDelta(.thinking(let reasoning, _)) = events[1] else {
            return XCTFail("Expected thinkingDelta")
        }
        XCTAssertEqual(reasoning, "R")
    }


    func testOpenAICompatibleAdapterNormalizesRootBaseURLAndParsesReasoningContent() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "oac",
            name: "Third Party",
            type: .openaiCompatible,
            apiKey: "ignored",
            baseURL: "https://example-compat.ai"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example-compat.ai/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "foo-reasoning")

            let response: [String: Any] = [
                "id": "cmpl_oac_1",
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
                    "prompt_tokens": 2,
                    "completion_tokens": 3,
                    "total_tokens": 5
                ]
            ]

            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAICompatibleAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "foo-reasoning",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .medium)),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 4)
        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "cmpl_oac_1")
        guard case .thinkingDelta(.thinking(let reasoning, _)) = events[1] else { return XCTFail("Expected thinkingDelta") }
        XCTAssertEqual(reasoning, "R")
        guard case .contentDelta(.text(let content)) = events[2] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "OK")
        guard case .messageEnd(let usage) = events[3] else { return XCTFail("Expected messageEnd") }
        XCTAssertEqual(usage?.inputTokens, 2)
        XCTAssertEqual(usage?.outputTokens, 3)
    }

    func testOpenAICompatibleAdapterSendsXHighEffortForGPT52Models() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "oac",
            name: "Third Party",
            type: .openaiCompatible,
            apiKey: "ignored",
            baseURL: "https://example-compat.ai"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example-compat.ai/v1/chat/completions")
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            let reasoning = try XCTUnwrap(root["reasoning"] as? [String: Any])
            XCTAssertEqual(reasoning["effort"] as? String, "xhigh")

            let response: [String: Any] = [
                "id": "cmpl_oac_xhigh",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK"
                        ],
                        "finish_reason": "stop"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAICompatibleAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "openai/gpt-5.2",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .xhigh)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenAICompatibleAdapterDoesNotInferAnthropicShapeFromModelName() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "oac",
            name: "Third Party",
            type: .openaiCompatible,
            apiKey: "ignored",
            baseURL: "https://example-compat.ai",
            models: [
                ModelInfo(
                    id: "anthropic/claude-sonnet-4-6",
                    name: "anthropic/claude-sonnet-4-6",
                    capabilities: [.streaming, .reasoning],
                    contextWindow: 128_000,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                )
            ]
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example-compat.ai/v1/chat/completions")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["temperature"] as? Double, 0.7)
            XCTAssertEqual(root["top_p"] as? Double, 0.9)
            XCTAssertNil(root["thinking"])
            XCTAssertNil(root["output_config"])
            let reasoning = try XCTUnwrap(root["reasoning"] as? [String: Any])
            XCTAssertEqual(reasoning["effort"] as? String, "high")

            let response: [String: Any] = [
                "id": "cmpl_oac_2",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK"
                        ],
                        "finish_reason": "stop"
                    ]
                ]
            ]

            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAICompatibleAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "anthropic/claude-sonnet-4-6",
            controls: GenerationControls(
                temperature: 0.7,
                topP: 0.9,
                reasoning: ReasoningControls(enabled: true, effort: .high)
            ),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenAICompatibleAdapterOmitsReasoningWhenModelOverrideDisablesReasoning() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "oac",
            name: "Third Party",
            type: .openaiCompatible,
            apiKey: "ignored",
            baseURL: "https://example-compat.ai",
            models: [
                ModelInfo(
                    id: "openai/gpt-oss-120b",
                    name: "openai/gpt-oss-120b",
                    capabilities: [.streaming, .toolCalling, .reasoning],
                    contextWindow: 128_000,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
                    overrides: ModelOverrides(
                        capabilities: [.streaming, .toolCalling],
                        reasoningConfig: ModelReasoningConfig(type: .none)
                    )
                )
            ]
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example-compat.ai/v1/chat/completions")
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertNil(root["reasoning"])
            XCTAssertNil(root["thinking"])
            XCTAssertNil(root["include_reasoning"])

            let response: [String: Any] = [
                "id": "cmpl_oac_disabled_reasoning",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK"
                        ],
                        "finish_reason": "stop"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAICompatibleAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "OpenAI/GPT-OSS-120B",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .medium)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenAICompatibleAdapterOmitsReasoningForUnrecognizedNonReasoningModel() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "oac",
            name: "Third Party",
            type: .openaiCompatible,
            apiKey: "ignored",
            baseURL: "https://example-compat.ai",
            models: []
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example-compat.ai/v1/chat/completions")
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertNil(root["reasoning"])
            XCTAssertNil(root["thinking"])
            XCTAssertNil(root["include_reasoning"])

            let response: [String: Any] = [
                "id": "cmpl_oac_unrecognized_non_reasoning",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK"
                        ],
                        "finish_reason": "stop"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAICompatibleAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "openai/gpt-oss-120b:free",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .medium)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenAICompatibleAdapterFetchModelsNormalizesAPIBaseURL() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "oac",
            name: "Third Party",
            type: .openaiCompatible,
            apiKey: "ignored",
            baseURL: "https://example-compat.ai/api"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example-compat.ai/api/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let payload: [String: Any] = [
                "data": [
                    ["id": "foo-chat"],
                    ["id": "foo-reasoning"]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAICompatibleAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()

        XCTAssertEqual(models.map(\.id), ["foo-chat", "foo-reasoning"])
        XCTAssertTrue(models.allSatisfy(\.isEnabled))
    }
    func testOpenRouterAdapterNormalizesRootBaseURLForKeyValidation() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "or",
            name: "OpenRouter",
            type: .openrouter,
            apiKey: "ignored",
            baseURL: "https://openrouter.ai"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/key")
            XCTAssertEqual(request.httpMethod, "GET")

            let data = Data("{}".utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenRouterAdapter(providerConfig: providerConfig, apiKey: "unused", networkManager: networkManager)
        let result = try await adapter.validateAPIKey("test-key")
        XCTAssertTrue(result)
    }

    func testOpenRouterAdapterUsesUnifiedReasoningForGeminiModelIDs() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "or",
            name: "OpenRouter",
            type: .openrouter,
            apiKey: "ignored",
            baseURL: "https://openrouter.ai/api/v1",
            models: [
                ModelInfo(
                    id: "google/gemini-2.5-pro",
                    name: "google/gemini-2.5-pro",
                    capabilities: [.streaming, .reasoning],
                    contextWindow: 128_000,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                )
            ]
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["temperature"] as? Double, 0.3)
            XCTAssertNil(root["generationConfig"])

            let reasoning = try XCTUnwrap(root["reasoning"] as? [String: Any])
            XCTAssertEqual(reasoning["effort"] as? String, "low")

            let response: [String: Any] = [
                "id": "cmpl_or_2",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK"
                        ],
                        "finish_reason": "stop"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenRouterAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "google/gemini-2.5-pro",
            controls: GenerationControls(
                temperature: 0.3,
                reasoning: ReasoningControls(enabled: true, effort: .low)
            ),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenRouterAdapterOmitsReasoningWhenModelOverrideDisablesReasoning() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "or",
            name: "OpenRouter",
            type: .openrouter,
            apiKey: "ignored",
            baseURL: "https://openrouter.ai/api/v1",
            models: [
                ModelInfo(
                    id: "openai/gpt-oss-120b",
                    name: "openai/gpt-oss-120b",
                    capabilities: [.streaming, .toolCalling, .reasoning],
                    contextWindow: 128_000,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
                    overrides: ModelOverrides(
                        capabilities: [.streaming, .toolCalling],
                        reasoningConfig: ModelReasoningConfig(type: .none)
                    )
                )
            ]
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertNil(root["reasoning"])
            XCTAssertNil(root["thinking"])

            let response: [String: Any] = [
                "id": "cmpl_or_disabled_reasoning",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK"
                        ],
                        "finish_reason": "stop"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenRouterAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "OpenAI/GPT-OSS-120B",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .medium)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenRouterAdapterOmitsReasoningForUnrecognizedNonReasoningModel() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "or",
            name: "OpenRouter",
            type: .openrouter,
            apiKey: "ignored",
            baseURL: "https://openrouter.ai/api/v1",
            models: []
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertNil(root["reasoning"])
            XCTAssertNil(root["thinking"])

            let response: [String: Any] = [
                "id": "cmpl_or_unrecognized_non_reasoning",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK"
                        ],
                        "finish_reason": "stop"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenRouterAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "openai/gpt-oss-120b:free",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .medium)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testCohereAdapterBuildsChatRequestAndParsesToolCalls() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "co",
            name: "Cohere",
            type: .cohere,
            apiKey: "ignored",
            baseURL: "https://example.com/v2"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v2/chat")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "command-r-plus")
            XCTAssertEqual(root["stream"] as? Bool, false)
            XCTAssertEqual(root["max_tokens"] as? Int, 12)
            XCTAssertEqual(root["temperature"] as? Double, 0.2)
            XCTAssertEqual(root["p"] as? Double, 0.9)

            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 4)
            XCTAssertEqual(messages[0]["role"] as? String, "system")
            XCTAssertEqual(messages[0]["content"] as? String, "sys")
            XCTAssertEqual(messages[1]["role"] as? String, "user")
            XCTAssertEqual(messages[1]["content"] as? String, "hi")

            let assistant = try XCTUnwrap(messages[2] as [String: Any])
            XCTAssertEqual(assistant["role"] as? String, "assistant")
            XCTAssertEqual(assistant["content"] as? String, "answer")

            let toolCalls = try XCTUnwrap(assistant["tool_calls"] as? [[String: Any]])
            XCTAssertEqual(toolCalls.count, 1)
            XCTAssertEqual(toolCalls[0]["id"] as? String, "call_1")
            let fn = try XCTUnwrap(toolCalls[0]["function"] as? [String: Any])
            XCTAssertEqual(fn["name"] as? String, "tool_name")
            XCTAssertEqual(fn["arguments"] as? String, "{\"q\":\"x\"}")

            XCTAssertEqual(messages[3]["role"] as? String, "tool")
            XCTAssertEqual(messages[3]["tool_call_id"] as? String, "call_1")
            XCTAssertEqual(messages[3]["content"] as? String, "tool result")

            let tools = try XCTUnwrap(root["tools"] as? [[String: Any]])
            XCTAssertEqual(tools.count, 1)
            let tool = try XCTUnwrap(tools[0]["function"] as? [String: Any])
            XCTAssertEqual(tool["name"] as? String, "tool_name")

            let response: [String: Any] = [
                "id": "msg_123",
                "finish_reason": "COMPLETE",
                "message": [
                    "role": "assistant",
                    "content": [
                        [
                            "type": "text",
                            "text": "OK"
                        ]
                    ],
                    "tool_calls": [
                        [
                            "id": "call_2",
                            "type": "function",
                            "function": [
                                "name": "tool_name",
                                "arguments": "{\"q\":\"y\"}"
                            ]
                        ]
                    ]
                ],
                "usage": [
                    "tokens": [
                        "input_tokens": 1,
                        "output_tokens": 2
                    ]
                ]
            ]

            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = CohereAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

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
                content: [.text("answer")],
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
            modelID: "command-r-plus",
            controls: GenerationControls(temperature: 0.2, maxTokens: 12, topP: 0.9),
            tools: [tool],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 5)

        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "msg_123")

        guard case .contentDelta(.text(let content)) = events[1] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "OK")

        guard case .toolCallStart(let call) = events[2] else { return XCTFail("Expected toolCallStart") }
        XCTAssertEqual(call.id, "call_2")
        XCTAssertEqual(call.name, "tool_name")
        XCTAssertEqual(call.arguments["q"]?.value as? String, "y")

        guard case .toolCallEnd(let endCall) = events[3] else { return XCTFail("Expected toolCallEnd") }
        XCTAssertEqual(endCall.id, "call_2")
        XCTAssertEqual(endCall.name, "tool_name")

        guard case .messageEnd(let usage) = events[4] else { return XCTFail("Expected messageEnd") }
        XCTAssertEqual(usage?.inputTokens, 1)
        XCTAssertEqual(usage?.outputTokens, 2)
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
