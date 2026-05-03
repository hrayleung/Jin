import Foundation
import XCTest
@testable import Jin

final class ChatCompletionsAdaptersTests: XCTestCase {
    func testFireworksAdapterBuildsRequestWithReasoningContentToolCallsAndToolResults() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testFireworksAdapterBuildsDeepSeekV4ProThinkingRequest() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

            XCTAssertEqual(root["model"] as? String, "accounts/fireworks/models/deepseek-v4-pro")
            let thinking = try XCTUnwrap(root["thinking"] as? [String: Any])
            XCTAssertEqual(thinking["type"] as? String, "enabled")
            XCTAssertEqual(root["reasoning_effort"] as? String, "max")

            let response: [String: Any] = [
                "id": "cmpl_v4_pro",
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

        let controls = GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .max))
        let adapter = FireworksAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "accounts/fireworks/models/deepseek-v4-pro",
            controls: controls,
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testFireworksAdapterBuildsDeepSeekV4ProThinkingDisabledRequest() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

            XCTAssertEqual(root["model"] as? String, "deepseek-ai/deepseek-v4-pro")
            let thinking = try XCTUnwrap(root["thinking"] as? [String: Any])
            XCTAssertEqual(thinking["type"] as? String, "disabled")
            XCTAssertNil(root["reasoning_effort"])

            let response: [String: Any] = [
                "id": "cmpl_v4_pro_disabled",
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

        var controls = GenerationControls(reasoning: ReasoningControls(enabled: false, effort: .max))
        controls.providerSpecific = ["reasoning_effort": AnyCodable("max")]

        let adapter = FireworksAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "deepseek-ai/deepseek-v4-pro",
            controls: controls,
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testFireworksAdapterSanitizesMiniMaxProviderSpecificReasoningOverrides() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testFireworksAdapterFetchModelsPrefersServerlessCatalogListing() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "fw",
            name: "Fireworks",
            type: .fireworks,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        var requestedURLs: [String] = []
        protocolType.requestHandler = { request in
            let url = try XCTUnwrap(request.url?.absoluteString)
            requestedURLs.append(url)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let response: [String: Any]
            let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            let queryItems = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
            )

            switch (components.path, queryItems["pageToken"]) {
            case ("/v1/accounts/fireworks/models", nil):
                XCTAssertEqual(queryItems["filter"], "supports_serverless=true")
                XCTAssertEqual(queryItems["pageSize"], "200")
                response = [
                    "models": [
                        ["name": "accounts/fireworks/models/qwen3p6-plus"],
                        ["name": "accounts/fireworks/models/DeepSeek-V4-Pro"],
                        ["name": "accounts/fireworks/models/deepseek-v3p2"],
                        ["name": "accounts/fireworks/models/kimi-k2-instruct-0905"],
                        ["name": "accounts/fireworks/models/kimi-k2p6"],
                        ["name": "accounts/fireworks/models/glm-5"]
                    ],
                    "nextPageToken": "page-2"
                ]
            case ("/v1/accounts/fireworks/models", "page-2"):
                XCTAssertEqual(queryItems["filter"], "supports_serverless=true")
                XCTAssertEqual(queryItems["pageSize"], "200")
                response = [
                    "models": [
                        ["name": "accounts/fireworks/models/minimax-m2p1"],
                        ["name": "accounts/fireworks/models/qwen3-235b-a22b"],
                        ["name": "accounts/fireworks/models/glm-preview"],
                        ["name": "accounts/fireworks/models/other"]
                    ]
                ]
            default:
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }

            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = FireworksAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        XCTAssertEqual(
            requestedURLs,
            [
                "https://example.com/v1/accounts/fireworks/models?filter=supports_serverless%3Dtrue&pageSize=200",
                "https://example.com/v1/accounts/fireworks/models?filter=supports_serverless%3Dtrue&pageSize=200&pageToken=page-2"
            ]
        )

        let qwen36 = try XCTUnwrap(byID["fireworks/qwen3p6-plus"])
        XCTAssertEqual(qwen36.name, "Qwen3.6 Plus")
        XCTAssertEqual(qwen36.contextWindow, 128_000)
        XCTAssertTrue(qwen36.capabilities.contains(.vision))
        XCTAssertFalse(qwen36.capabilities.contains(.reasoning))

        let deepSeekV4Pro = try XCTUnwrap(byID["accounts/fireworks/models/deepseek-v4-pro"])
        XCTAssertEqual(deepSeekV4Pro.name, "DeepSeek V4 Pro")
        XCTAssertEqual(deepSeekV4Pro.contextWindow, 1_048_600)
        XCTAssertEqual(deepSeekV4Pro.capabilities, [.streaming, .toolCalling, .reasoning])
        XCTAssertEqual(deepSeekV4Pro.reasoningConfig?.defaultEffort, .high)

        let deepSeek = try XCTUnwrap(byID["fireworks/deepseek-v3p2"])
        XCTAssertEqual(deepSeek.name, "DeepSeek V3.2")
        XCTAssertEqual(deepSeek.contextWindow, 163_800)
        XCTAssertFalse(deepSeek.capabilities.contains(.vision))
        XCTAssertFalse(deepSeek.capabilities.contains(.reasoning))

        let kimiInstruct = try XCTUnwrap(byID["fireworks/kimi-k2-instruct-0905"])
        XCTAssertEqual(kimiInstruct.name, "Kimi K2 Instruct 0905")
        XCTAssertEqual(kimiInstruct.contextWindow, 262_100)
        XCTAssertFalse(kimiInstruct.capabilities.contains(.vision))
        XCTAssertFalse(kimiInstruct.capabilities.contains(.reasoning))

        let kimiK26 = try XCTUnwrap(byID["fireworks/kimi-k2p6"])
        XCTAssertEqual(kimiK26.name, "Kimi K2.6")
        XCTAssertEqual(kimiK26.contextWindow, 262_100)
        XCTAssertTrue(kimiK26.capabilities.contains(.vision))
        XCTAssertTrue(kimiK26.capabilities.contains(.reasoning))
        XCTAssertEqual(kimiK26.reasoningConfig?.defaultEffort, .medium)

        let glm5 = try XCTUnwrap(byID["fireworks/glm-5"])
        XCTAssertEqual(glm5.name, "GLM-5")
        XCTAssertEqual(glm5.contextWindow, 202_800)
        XCTAssertTrue(glm5.capabilities.contains(.reasoning))
        XCTAssertFalse(glm5.capabilities.contains(.vision))

        let minimaxM2p1 = try XCTUnwrap(byID["fireworks/minimax-m2p1"])
        XCTAssertEqual(minimaxM2p1.name, "MiniMax M2.1")
        XCTAssertEqual(minimaxM2p1.contextWindow, 204_800)
        XCTAssertTrue(minimaxM2p1.capabilities.contains(.reasoning))
        XCTAssertFalse(minimaxM2p1.capabilities.contains(.vision))

        let qwen235 = try XCTUnwrap(byID["fireworks/qwen3-235b-a22b"])
        XCTAssertEqual(qwen235.name, "Qwen3 235B A22B")
        XCTAssertEqual(qwen235.contextWindow, 131_100)
        XCTAssertFalse(qwen235.capabilities.contains(.vision))
        XCTAssertFalse(qwen235.capabilities.contains(.reasoning))

        let glmPreview = try XCTUnwrap(byID["fireworks/glm-preview"])
        XCTAssertFalse(glmPreview.capabilities.contains(.reasoning))
        XCTAssertNil(glmPreview.reasoningConfig)
        XCTAssertEqual(glmPreview.contextWindow, 128_000)

        let other = try XCTUnwrap(byID["fireworks/other"])
        XCTAssertEqual(other.name, "fireworks/other")
        XCTAssertEqual(other.contextWindow, 128_000)
    }

    func testFireworksAdapterFetchModelsDoesNotFallBackToOpenAICompatibleModelsEndpoint() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "fw",
            name: "Fireworks",
            type: .fireworks,
            apiKey: "ignored",
            baseURL: "https://example.com/inference/v1"
        )

        var requestedURLs: [String] = []
        protocolType.requestHandler = { request in
            let url = try XCTUnwrap(request.url?.absoluteString)
            requestedURLs.append(url)

            if let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false),
               components.path == "/v1/accounts/fireworks/models" {
                let queryItems = Dictionary(
                    uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
                )
                XCTAssertEqual(queryItems["filter"], "supports_serverless=true")
                XCTAssertEqual(queryItems["pageSize"], "200")
                let invalidJSON = Data("{".utf8)
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    invalidJSON
                )
            }

            return (
                HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        let adapter = FireworksAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        do {
            _ = try await adapter.fetchAvailableModels()
            XCTFail("Expected fetchAvailableModels to fail when the Fireworks catalog response is invalid.")
        } catch is DecodingError {
            // Expected: Fireworks model discovery should fail rather than silently falling back.
        } catch {
            XCTFail("Expected DecodingError, got \(error).")
        }

        XCTAssertEqual(
            requestedURLs,
            ["https://example.com/v1/accounts/fireworks/models?filter=supports_serverless%3Dtrue&pageSize=200"]
        )
    }

    func testSambaNovaAdapterMapsReasoningOffToLowEffortForGptOss() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "sn",
            name: "SambaNova",
            type: .sambanova,
            apiKey: "ignored",
            baseURL: "https://example.com/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/chat/completions")
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "gpt-oss-120b")
            XCTAssertEqual(root["reasoning_effort"] as? String, "low")
            XCTAssertNil(root["chat_template_kwargs"])

            let response: [String: Any] = [
                "id": "cmpl_sn_gpt_oss",
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

        let adapter = SambaNovaAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gpt-oss-120b",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: false)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testSambaNovaAdapterUsesEnableThinkingToggleForDeepSeekV31() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "sn",
            name: "SambaNova",
            type: .sambanova,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/chat/completions")
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "DeepSeek-V3.1")
            XCTAssertNil(root["reasoning_effort"])
            let template = try XCTUnwrap(root["chat_template_kwargs"] as? [String: Any])
            XCTAssertEqual(template["enable_thinking"] as? Bool, false)

            let response: [String: Any] = [
                "id": "cmpl_sn_v31",
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

        let adapter = SambaNovaAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "DeepSeek-V3.1",
            controls: GenerationControls(
                temperature: 0.6,
                topP: 0.9,
                reasoning: ReasoningControls(enabled: false)
            ),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testSambaNovaAdapterOmitsReasoningToggleForDeepSeekR1Family() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "sn",
            name: "SambaNova",
            type: .sambanova,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/chat/completions")
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "DeepSeek-R1-Distill-Llama-70B")
            XCTAssertNil(root["chat_template_kwargs"])
            XCTAssertNil(root["reasoning_effort"])
            XCTAssertNil(root["temperature"])
            XCTAssertNil(root["top_p"])

            let response: [String: Any] = [
                "id": "cmpl_sn_r1",
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

        let adapter = SambaNovaAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "DeepSeek-R1-Distill-Llama-70B",
            controls: GenerationControls(
                temperature: 0.6,
                topP: 0.9,
                reasoning: ReasoningControls(enabled: false)
            ),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testSambaNovaAdapterFetchModelsMarksDeepSeekR1DistillAsToolCallable() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "sn",
            name: "SambaNova",
            type: .sambanova,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/models")
            let response: [String: Any] = [
                "data": [
                    ["id": "DeepSeek-R1-Distill-Llama-70B"]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = SambaNovaAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let r1Distill = try XCTUnwrap(models.first)
        XCTAssertEqual(r1Distill.id, "DeepSeek-R1-Distill-Llama-70B")
        XCTAssertEqual(r1Distill.name, "DeepSeek R1 Distill Llama 70B")
        XCTAssertTrue(r1Distill.capabilities.contains(.toolCalling))
        XCTAssertTrue(r1Distill.capabilities.contains(.reasoning))
    }

    func testSambaNovaAdapterFetchModelsUsesCatalogDisplayNameForKnownModel() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "sn",
            name: "SambaNova",
            type: .sambanova,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/models")
            let response: [String: Any] = [
                "data": [
                    ["id": "MiniMax-M2.5"]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = SambaNovaAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let miniMax = try XCTUnwrap(models.first)
        XCTAssertEqual(miniMax.id, "MiniMax-M2.5")
        XCTAssertEqual(miniMax.name, "MiniMax M2.5")
        XCTAssertEqual(miniMax.contextWindow, 160_000)
    }

    func testSambaNovaAdapterFetchModelsIncludesDeepSeekV32() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "sn",
            name: "SambaNova",
            type: .sambanova,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/models")
            let response: [String: Any] = [
                "data": [
                    ["id": "DeepSeek-V3.2"],
                    ["id": "DeepSeek-V3.1"],
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = SambaNovaAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let deepSeekV32 = try XCTUnwrap(models.first(where: { $0.id.caseInsensitiveCompare("DeepSeek-V3.2") == .orderedSame }))
        XCTAssertEqual(deepSeekV32.contextWindow, 8_192)
        XCTAssertEqual(deepSeekV32.capabilities, [.streaming])
        XCTAssertTrue(models.contains(where: { $0.id == "DeepSeek-V3.1" }))
    }

    func testOpenAIAdapterFetchModelsAddsNativePDFForVisionFamilies() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "openai",
            name: "OpenAI",
            type: .openai,
            apiKey: "ignored",
            baseURL: "https://example.com/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let payload: [String: Any] = [
                "data": [
                    ["id": "gpt-5.2", "max_tokens": 128_000, "context_window": 400_000],
                    ["id": "gpt-5.3-codex", "max_tokens": 128_000, "context_window": 400_000],
                    ["id": "gpt-5.3-chat-latest", "max_tokens": 32_000, "context_window": 128_000],
                    ["id": "gpt-4o", "max_tokens": 16_384, "context_window": 128_000],
                    ["id": "gpt-4.1-mini", "max_tokens": 32_000, "context_window": 128_000]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        let gpt52 = try XCTUnwrap(byID["gpt-5.2"])
        XCTAssertEqual(gpt52.contextWindow, 400_000)
        XCTAssertEqual(gpt52.maxOutputTokens, 128_000)
        XCTAssertTrue(gpt52.capabilities.contains(.vision))
        XCTAssertTrue(gpt52.capabilities.contains(.reasoning))
        XCTAssertTrue(gpt52.capabilities.contains(.nativePDF))
        XCTAssertEqual(ModelSettingsResolver.resolve(model: gpt52, providerType: .openai).maxOutputTokens, 128_000)

        let gpt53 = try XCTUnwrap(byID["gpt-5.3-codex"])
        XCTAssertEqual(gpt53.contextWindow, 400_000)
        XCTAssertEqual(gpt53.maxOutputTokens, 128_000)
        XCTAssertTrue(gpt53.capabilities.contains(.vision))
        XCTAssertTrue(gpt53.capabilities.contains(.reasoning))
        XCTAssertTrue(gpt53.capabilities.contains(.nativePDF))
        XCTAssertEqual(ModelSettingsResolver.resolve(model: gpt53, providerType: .openai).maxOutputTokens, 128_000)

        let gpt53ChatLatest = try XCTUnwrap(byID["gpt-5.3-chat-latest"])
        XCTAssertEqual(gpt53ChatLatest.contextWindow, 128_000)
        XCTAssertEqual(gpt53ChatLatest.maxOutputTokens, 32_000)
        XCTAssertTrue(gpt53ChatLatest.capabilities.contains(.vision))
        XCTAssertFalse(gpt53ChatLatest.capabilities.contains(.reasoning))
        XCTAssertFalse(gpt53ChatLatest.capabilities.contains(.nativePDF))
        XCTAssertEqual(ModelSettingsResolver.resolve(model: gpt53ChatLatest, providerType: .openai).maxOutputTokens, 32_000)

        let gpt4o = try XCTUnwrap(byID["gpt-4o"])
        XCTAssertEqual(gpt4o.contextWindow, 128_000)
        XCTAssertEqual(gpt4o.maxOutputTokens, 16_384)
        XCTAssertTrue(gpt4o.capabilities.contains(.vision))
        XCTAssertFalse(gpt4o.capabilities.contains(.reasoning))
        XCTAssertTrue(gpt4o.capabilities.contains(.nativePDF))
        XCTAssertEqual(ModelSettingsResolver.resolve(model: gpt4o, providerType: .openai).maxOutputTokens, 16_384)

        let gpt41mini = try XCTUnwrap(byID["gpt-4.1-mini"])
        XCTAssertEqual(gpt41mini.contextWindow, 128_000)
        XCTAssertEqual(gpt41mini.maxOutputTokens, 32_000)
        XCTAssertFalse(gpt41mini.capabilities.contains(.nativePDF))
        XCTAssertEqual(ModelSettingsResolver.resolve(model: gpt41mini, providerType: .openai).maxOutputTokens, 32_000)
    }

    func testOpenAIAdapterFetchModelsPreservesAudioMetadataForKnownAudioIDs() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "openai",
            name: "OpenAI",
            type: .openai,
            apiKey: "ignored",
            baseURL: "https://example.com/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/models")
            let payload: [String: Any] = [
                "data": [
                    ["id": "gpt-4o-audio-preview"],
                    ["id": "gpt-realtime-mini"],
                    ["id": "gpt-4.1-mini"]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        XCTAssertTrue(try XCTUnwrap(byID["gpt-4o-audio-preview"]).capabilities.contains(.audio))
        XCTAssertTrue(try XCTUnwrap(byID["gpt-realtime-mini"]).capabilities.contains(.audio))
        XCTAssertFalse(try XCTUnwrap(byID["gpt-4.1-mini"]).capabilities.contains(.audio))
    }

    func testVertexAIAdapterFetchModelsUsesKnownContextWindows() async throws {
        let (configuration, _) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "vertex",
            name: "Vertex AI",
            type: .vertexai,
            apiKey: "ignored"
        )

        let credentials = ServiceAccountCredentials(
            type: "service_account",
            projectID: "project",
            privateKeyID: "key-id",
            privateKey: "-----BEGIN PRIVATE KEY-----\\nFAKE\\n-----END PRIVATE KEY-----\\n",
            clientEmail: "svc@example.com",
            clientID: "1234567890",
            authURI: "https://accounts.google.com/o/oauth2/auth",
            tokenURI: "https://oauth2.googleapis.com/token",
            authProviderX509CertURL: "https://www.googleapis.com/oauth2/v1/certs",
            clientX509CertURL: "https://www.googleapis.com/robot/v1/metadata/x509/svc%40example.com",
            location: "global"
        )

        let adapter = VertexAIAdapter(providerConfig: providerConfig, serviceAccountJSON: credentials, networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        XCTAssertEqual(try XCTUnwrap(byID["gemini-3-pro-image-preview"]).contextWindow, 65_536)
        XCTAssertEqual(try XCTUnwrap(byID["gemini-3.1-flash-image-preview"]).contextWindow, 131_072)
        XCTAssertEqual(try XCTUnwrap(byID["gemini-3.1-flash-lite-preview"]).contextWindow, 1_048_576)
        XCTAssertEqual(try XCTUnwrap(byID["gemini-2.5-flash-image"]).contextWindow, 32_768)
    }

    func testCerebrasAdapterClampsTemperatureAndSendsReasoningField() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testCerebrasAdapterFetchModelsUsesCatalogMetadataWhenKnown() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "c",
            name: "Cerebras",
            type: .cerebras,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/models")
            let payload: [String: Any] = [
                "data": [
                    ["id": "qwen-3-235b-a22b-instruct-2507"],
                    ["id": "zai-glm-4.7"],
                    ["id": "unknown-model"],
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = CerebrasAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        let qwen235 = try XCTUnwrap(byID["qwen-3-235b-a22b-instruct-2507"])
        XCTAssertEqual(qwen235.contextWindow, 65_000)
        XCTAssertEqual(qwen235.maxOutputTokens, 32_000)
        XCTAssertFalse(qwen235.capabilities.contains(.reasoning))

        let glm47 = try XCTUnwrap(byID["zai-glm-4.7"])
        XCTAssertEqual(glm47.contextWindow, 64_000)
        XCTAssertEqual(glm47.maxOutputTokens, 40_000)
        XCTAssertTrue(glm47.capabilities.contains(.reasoning))

        let unknown = try XCTUnwrap(byID["unknown-model"])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.reasoningConfig)
    }

    func testDeepSeekAdapterUsesV1RouteAndParsesReasoningAndToolCalls() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testDeepSeekReasonerOmitsUnsupportedThinkingParameter() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "ds",
            name: "DeepSeek",
            type: .deepseek,
            apiKey: "ignored",
            baseURL: "https://api.deepseek.com/v1"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "deepseek-reasoner")
            XCTAssertNil(root["thinking"])
            XCTAssertNil(root["reasoning_effort"])

            let response: [String: Any] = [
                "id": "cmpl_ds_reasoner",
                "choices": [["message": ["role": "assistant", "content": "OK"], "finish_reason": "stop"]]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = DeepSeekAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "deepseek-reasoner",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .high)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testDeepSeekAdapterUsesV4ThinkingAndReasoningEffortControls() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "ds",
            name: "DeepSeek",
            type: .deepseek,
            apiKey: "ignored",
            baseURL: "https://api.deepseek.com/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/v1/chat/completions")
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "deepseek-v4-pro")
            let thinking = try XCTUnwrap(root["thinking"] as? [String: Any])
            XCTAssertEqual(thinking["type"] as? String, "enabled")
            XCTAssertEqual(root["reasoning_effort"] as? String, "max")
            XCTAssertNil(root["reasoning"])

            let response: [String: Any] = [
                "id": "cmpl_ds_v4",
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
            modelID: "deepseek-v4-pro",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .xhigh)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testDeepSeekAdapterDisablesV4ThinkingWithoutLegacyReasoningField() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "ds",
            name: "DeepSeek",
            type: .deepseek,
            apiKey: "ignored",
            baseURL: "https://api.deepseek.com/v1"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "deepseek-v4-flash")
            let thinking = try XCTUnwrap(root["thinking"] as? [String: Any])
            XCTAssertEqual(thinking["type"] as? String, "disabled")
            XCTAssertNil(root["reasoning_effort"])
            XCTAssertNil(root["reasoning"])

            let response: [String: Any] = [
                "id": "cmpl_ds_v4_off",
                "choices": [["message": ["role": "assistant", "content": "OK"], "finish_reason": "stop"]]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = DeepSeekAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "deepseek-v4-flash",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: false)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testDeepSeekAdapterFetchModelsUsesCatalogMetadataForV4Models() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "ds",
            name: "DeepSeek",
            type: .deepseek,
            apiKey: "ignored",
            baseURL: "https://api.deepseek.com/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/v1/models")
            let response: [String: Any] = [
                "object": "list",
                "data": [
                    ["id": "deepseek-v4-flash", "object": "model"],
                    ["id": "deepseek-v4-pro", "object": "model"]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = DeepSeekAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let flash = try XCTUnwrap(models.first(where: { $0.id == "deepseek-v4-flash" }))
        XCTAssertEqual(flash.contextWindow, 1_000_000)
        XCTAssertEqual(flash.maxOutputTokens, 384_000)
        XCTAssertTrue(flash.capabilities.contains(.promptCaching))
        XCTAssertEqual(flash.reasoningConfig?.type, .effort)

        let pro = try XCTUnwrap(models.first(where: { $0.id == "deepseek-v4-pro" }))
        XCTAssertEqual(pro.contextWindow, 1_000_000)
        XCTAssertEqual(pro.maxOutputTokens, 384_000)
        XCTAssertEqual(pro.reasoningConfig?.defaultEffort, .high)
    }

    func testOpenRouterAdapterBuildsChatCompletionsRequestWithReasoningAndWebPlugin() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testOpenCodeGoAdapterBuildsMiMoV25RequestWithNativeWebSearchTool() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "opencode",
            name: "OpenCode Go",
            type: .opencodeGo,
            apiKey: "ignored"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://opencode.ai/zen/go/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "mimo-v2.5")
            XCTAssertEqual(root["stream"] as? Bool, false)
            XCTAssertEqual(root["max_tokens"] as? Int, 2048)

            let reasoning = try XCTUnwrap(root["reasoning"] as? [String: Any])
            XCTAssertEqual(reasoning["effort"] as? String, "medium")

            let toolObjects = try XCTUnwrap(root["tools"] as? [[String: Any]])
            XCTAssertEqual(toolObjects.count, 2)

            let webSearchTool = try XCTUnwrap(toolObjects.first { ($0["type"] as? String) == "web_search" })
            XCTAssertEqual(webSearchTool["limit"] as? Int, 2)

            let functionTool = try XCTUnwrap(toolObjects.first { ($0["type"] as? String) == "function" })
            XCTAssertEqual(functionTool["type"] as? String, "function")
            let function = try XCTUnwrap(functionTool["function"] as? [String: Any])
            XCTAssertEqual(function["name"] as? String, "lookup_status")

            let response: [String: Any] = [
                "id": "cmpl_opencode_mimo",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK",
                            "reasoning_content": "R"
                        ],
                        "finish_reason": "stop"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenCodeGoAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("Search and summarize")])],
            modelID: "mimo-v2.5",
            controls: GenerationControls(
                maxTokens: 2048,
                reasoning: ReasoningControls(enabled: true, effort: .medium),
                webSearch: WebSearchControls(enabled: true, maxUses: 2)
            ),
            tools: [
                ToolDefinition(
                    id: "tool_1",
                    name: "lookup_status",
                    description: "Lookup a project status by ID.",
                    parameters: ParameterSchema(
                        properties: [
                            "id": PropertySchema(type: "string", description: "Project ID")
                        ],
                        required: ["id"]
                    ),
                    source: .builtin
                )
            ],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 4)
        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "cmpl_opencode_mimo")
        guard case .thinkingDelta(.thinking(let reasoning, _)) = events[1] else { return XCTFail("Expected thinkingDelta") }
        XCTAssertEqual(reasoning, "R")
        guard case .contentDelta(.text(let content)) = events[2] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "OK")
        guard case .messageEnd = events[3] else { return XCTFail("Expected messageEnd") }
    }

    func testOpenCodeGoAdapterOmitsWebSearchForUnsupportedMiMoPreview() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "opencode",
            name: "OpenCode Go",
            type: .opencodeGo,
            apiKey: "ignored"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://opencode.ai/zen/go/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "mimo-v2.5-preview")
            XCTAssertEqual(root["stream"] as? Bool, false)
            XCTAssertEqual(root["max_tokens"] as? Int, 2048)

            let reasoning = try XCTUnwrap(root["reasoning"] as? [String: Any])
            XCTAssertEqual(reasoning["effort"] as? String, "medium")

            let toolObjects = try XCTUnwrap(root["tools"] as? [[String: Any]])
            XCTAssertEqual(toolObjects.count, 1)
            XCTAssertNil(toolObjects.first { ($0["type"] as? String) == "web_search" })

            let functionTool = try XCTUnwrap(toolObjects.first { ($0["type"] as? String) == "function" })
            XCTAssertEqual(functionTool["type"] as? String, "function")
            let function = try XCTUnwrap(functionTool["function"] as? [String: Any])
            XCTAssertEqual(function["name"] as? String, "lookup_status")

            let response: [String: Any] = [
                "id": "cmpl_opencode_mimo_preview",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK",
                            "reasoning_content": "R"
                        ],
                        "finish_reason": "stop"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenCodeGoAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("Search and summarize")])],
            modelID: "mimo-v2.5-preview",
            controls: GenerationControls(
                maxTokens: 2048,
                reasoning: ReasoningControls(enabled: true, effort: .medium),
                webSearch: WebSearchControls(enabled: true, maxUses: 2)
            ),
            tools: [
                ToolDefinition(
                    id: "tool_1",
                    name: "lookup_status",
                    description: "Lookup a project status by ID.",
                    parameters: ParameterSchema(
                        properties: [
                            "id": PropertySchema(type: "string", description: "Project ID")
                        ],
                        required: ["id"]
                    ),
                    source: .builtin
                )
            ],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 4)
        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "cmpl_opencode_mimo_preview")
        guard case .thinkingDelta(.thinking(let reasoning, _)) = events[1] else { return XCTFail("Expected thinkingDelta") }
        XCTAssertEqual(reasoning, "R")
        guard case .contentDelta(.text(let content)) = events[2] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "OK")
        guard case .messageEnd = events[3] else { return XCTFail("Expected messageEnd") }
    }

    func testMiMoTokenPlanOpenAIAdapterBuildsDocumentedRequestShape() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "mimo-openai",
            name: "Xiaomi MiMo Token Plan (OpenAI)",
            type: .mimoTokenPlanOpenAI,
            apiKey: "ignored",
            baseURL: "https://token-plan-sgp.xiaomimimo.com/v1"
        )

        let audioURL = try XCTUnwrap(URL(string: "https://cdn.example.com/audio.wav"))
        let videoData = Data([0x00, 0x01, 0x02])

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://token-plan-sgp.xiaomimimo.com/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "test-key")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "mimo-v2.5")
            XCTAssertEqual(root["stream"] as? Bool, false)
            XCTAssertEqual(root["max_completion_tokens"] as? Int, 2048)
            XCTAssertNil(root["max_tokens"])

            let thinking = try XCTUnwrap(root["thinking"] as? [String: Any])
            XCTAssertEqual(thinking["type"] as? String, "enabled")

            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 2)

            let userContent = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
            XCTAssertEqual(userContent.count, 3)
            XCTAssertEqual(userContent[0]["type"] as? String, "text")

            let inputAudio = try XCTUnwrap(userContent.first { ($0["type"] as? String) == "input_audio" })
            let inputAudioPayload = try XCTUnwrap(inputAudio["input_audio"] as? [String: Any])
            XCTAssertEqual(inputAudioPayload["data"] as? String, audioURL.absoluteString)
            XCTAssertNil(inputAudioPayload["format"])

            let video = try XCTUnwrap(userContent.first { ($0["type"] as? String) == "video_url" })
            let videoPayload = try XCTUnwrap(video["video_url"] as? [String: Any])
            XCTAssertEqual(videoPayload["url"] as? String, mediaDataURI(mimeType: "video/mp4", data: videoData))
            XCTAssertEqual(video["fps"] as? Int, 2)
            XCTAssertEqual(video["media_resolution"] as? String, "default")

            XCTAssertEqual(messages[1]["role"] as? String, "assistant")
            XCTAssertEqual(messages[1]["content"] as? String, "answer")
            XCTAssertEqual(messages[1]["reasoning_content"] as? String, "thinking trace")

            let toolObjects = try XCTUnwrap(root["tools"] as? [[String: Any]])
            XCTAssertEqual(toolObjects.count, 2)

            let webSearch = try XCTUnwrap(toolObjects.first { ($0["type"] as? String) == "web_search" })
            XCTAssertEqual(webSearch["limit"] as? Int, 3)
            XCTAssertEqual(webSearch["max_keyword"] as? Int, 3)
            let location = try XCTUnwrap(webSearch["user_location"] as? [String: Any])
            XCTAssertEqual(location["type"] as? String, "approximate")
            XCTAssertEqual(location["country"] as? String, "US")
            XCTAssertEqual(location["region"] as? String, "California")
            XCTAssertEqual(location["city"] as? String, "San Francisco")
            XCTAssertEqual(location["timezone"] as? String, "America/Los_Angeles")

            let functionTool = try XCTUnwrap(toolObjects.first { ($0["type"] as? String) == "function" })
            let function = try XCTUnwrap(functionTool["function"] as? [String: Any])
            XCTAssertEqual(function["name"] as? String, "lookup_status")

            let response: [String: Any] = [
                "id": "cmpl_mimo_token_plan",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK",
                            "reasoning_content": "R"
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
            messages: [
                Message(
                    role: .user,
                    content: [
                        .text("Describe these inputs"),
                        .audio(AudioContent(mimeType: "audio/wav", data: nil, url: audioURL)),
                        .video(VideoContent(mimeType: "video/mp4", data: videoData, url: nil))
                    ]
                ),
                Message(
                    role: .assistant,
                    content: [
                        .text("answer"),
                        .thinking(ThinkingBlock(text: "thinking trace"))
                    ]
                )
            ],
            modelID: "mimo-v2.5",
            controls: GenerationControls(
                maxTokens: 2048,
                reasoning: ReasoningControls(enabled: true, effort: .medium),
                webSearch: WebSearchControls(
                    enabled: true,
                    maxUses: 3,
                    userLocation: WebSearchUserLocation(
                        city: "San Francisco",
                        region: "California",
                        country: "US",
                        timezone: "America/Los_Angeles"
                    )
                )
            ),
            tools: [
                ToolDefinition(
                    id: "tool_1",
                    name: "lookup_status",
                    description: "Lookup a project status by ID.",
                    parameters: ParameterSchema(
                        properties: [
                            "id": PropertySchema(type: "string", description: "Project ID")
                        ],
                        required: ["id"]
                    ),
                    source: .builtin
                )
            ],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 4)
        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "cmpl_mimo_token_plan")
        guard case .thinkingDelta(.thinking(let reasoning, _)) = events[1] else { return XCTFail("Expected thinkingDelta") }
        XCTAssertEqual(reasoning, "R")
        guard case .contentDelta(.text(let content)) = events[2] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "OK")
        guard case .messageEnd = events[3] else { return XCTFail("Expected messageEnd") }
    }

    func testMiMoTokenPlanOpenAIAdapterOmitsWebSearchForUnsupportedPreview() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "mimo-openai",
            name: "Xiaomi MiMo Token Plan (OpenAI)",
            type: .mimoTokenPlanOpenAI,
            apiKey: "ignored",
            baseURL: "https://token-plan-sgp.xiaomimimo.com/v1"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "mimo-v2.5-preview")
            XCTAssertNil(root["tools"])

            let response: [String: Any] = [
                "id": "cmpl_mimo_preview",
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
            messages: [Message(role: .user, content: [.text("Search")])],
            modelID: "mimo-v2.5-preview",
            controls: GenerationControls(webSearch: WebSearchControls(enabled: true, maxUses: 3)),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 3)
    }

    func testMiMoTokenPlanOpenAIAdapterFetchModelsUsesAPIKeyAndFiltersTTSModels() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "mimo-openai",
            name: "Xiaomi MiMo Token Plan (OpenAI)",
            type: .mimoTokenPlanOpenAI,
            apiKey: "ignored",
            baseURL: "https://token-plan-sgp.xiaomimimo.com/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://token-plan-sgp.xiaomimimo.com/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "test-key")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

            let payload: [String: Any] = [
                "data": [
                    ["id": "mimo-v2.5-pro"],
                    ["id": "mimo-v2.5"],
                    ["id": "mimo-v2.5-tts"],
                    ["id": "mimo-v2.5-tts-voicedesign"],
                    ["id": "mimo-v2-tts"]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAICompatibleAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()

        XCTAssertEqual(models.map(\.id), ["mimo-v2.5-pro", "mimo-v2.5"])
        let pro = try XCTUnwrap(models.first(where: { $0.id == "mimo-v2.5-pro" }))
        XCTAssertEqual(pro.contextWindow, 1_048_576)
        XCTAssertEqual(pro.maxOutputTokens, 131_072)

        let omni = try XCTUnwrap(models.first(where: { $0.id == "mimo-v2.5" }))
        XCTAssertTrue(omni.capabilities.contains(.vision))
        XCTAssertTrue(omni.capabilities.contains(.audio))
        XCTAssertTrue(omni.capabilities.contains(.videoInput))
    }

    func testMiMoTokenPlanAnthropicAdapterBuildsDocumentedRequestShape() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "mimo-anthropic",
            name: "Xiaomi MiMo Token Plan (Anthropic)",
            type: .mimoTokenPlanAnthropic,
            apiKey: "ignored",
            baseURL: "https://token-plan-sgp.xiaomimimo.com/anthropic"
        )

        let imageData = Data([0x89, 0x50, 0x4e, 0x47])

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://token-plan-sgp.xiaomimimo.com/anthropic/v1/messages")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "test-key")
            XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
            XCTAssertNil(request.value(forHTTPHeaderField: "anthropic-version"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "mimo-v2.5")
            XCTAssertEqual(root["stream"] as? Bool, false)
            XCTAssertEqual(root["max_tokens"] as? Int, 4096)
            XCTAssertEqual(root["temperature"] as? Double, 0.7)
            XCTAssertEqual(root["top_p"] as? Double, 0.8)

            let thinking = try XCTUnwrap(root["thinking"] as? [String: Any])
            XCTAssertEqual(thinking["type"] as? String, "enabled")
            XCTAssertNil(thinking["budget_tokens"])

            XCTAssertNil(root["tools"])

            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 1)
            XCTAssertEqual(messages[0]["role"] as? String, "user")

            let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
            XCTAssertEqual(content.count, 2)
            XCTAssertEqual(content[0]["type"] as? String, "text")
            XCTAssertEqual(content[0]["text"] as? String, "describe this image")

            let image = try XCTUnwrap(content.first { ($0["type"] as? String) == "image" })
            let source = try XCTUnwrap(image["source"] as? [String: Any])
            XCTAssertEqual(source["type"] as? String, "base64")
            XCTAssertEqual(source["media_type"] as? String, "image/png")
            XCTAssertEqual(source["data"] as? String, imageData.base64EncodedString())

            let sse = """
            event: message_start
            data: {"type":"message_start","message":{"id":"msg_mimo_token_plan","type":"message","role":"assistant","content":[],"model":"mimo-v2.5","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":9,"output_tokens":0}}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"R"}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"OK"}}

            event: message_stop
            data: {"type":"message_stop"}

            """
            let data = try XCTUnwrap(sse.data(using: .utf8))
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!,
                data
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [
                Message(
                    role: .user,
                    content: [
                        .text("describe this image"),
                        .image(ImageContent(mimeType: "image/png", data: imageData))
                    ]
                )
            ],
            modelID: "mimo-v2.5",
            controls: GenerationControls(
                temperature: 0.7,
                maxTokens: 4096,
                topP: 0.8,
                reasoning: ReasoningControls(enabled: true),
                webSearch: WebSearchControls(enabled: true, maxUses: 3)
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
        XCTAssertEqual(id, "msg_mimo_token_plan")
        guard case .thinkingDelta(.thinking(let reasoning, _)) = events[1] else { return XCTFail("Expected thinkingDelta") }
        XCTAssertEqual(reasoning, "R")
        guard case .contentDelta(.text(let content)) = events[2] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "OK")
        guard case .messageEnd = events[3] else { return XCTFail("Expected messageEnd") }
    }

    func testOpenCodeGoAdapterRoutesDeepSeekV4ToAnthropicMessagesEndpoint() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "opencode",
            name: "OpenCode Go",
            type: .opencodeGo,
            apiKey: "ignored"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://opencode.ai/zen/go/v1/messages")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "deepseek-v4-pro")
            XCTAssertEqual(root["stream"] as? Bool, false)
            XCTAssertEqual(root["max_tokens"] as? Int, 2048)

            let thinking = try XCTUnwrap(root["thinking"] as? [String: Any])
            XCTAssertEqual(thinking["type"] as? String, "enabled")
            XCTAssertNil(thinking["budget_tokens"])

            let outputConfig = try XCTUnwrap(root["output_config"] as? [String: Any])
            XCTAssertEqual(outputConfig["effort"] as? String, "max")

            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 1)
            XCTAssertEqual(messages[0]["role"] as? String, "user")
            let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
            XCTAssertEqual(content.first?["type"] as? String, "text")
            XCTAssertEqual(content.first?["text"] as? String, "hi")

            let sse = """
            event: message_start
            data: {"type":"message_start","message":{"id":"msg_opencode_deepseek","type":"message","role":"assistant","content":[],"model":"deepseek-v4-pro","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":3,"output_tokens":0}}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"OK"}}

            event: message_stop
            data: {"type":"message_stop"}

            """
            let data = try XCTUnwrap(sse.data(using: .utf8))
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!,
                data
            )
        }

        let adapter = OpenCodeGoAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "deepseek-v4-pro",
            controls: GenerationControls(
                maxTokens: 2048,
                reasoning: ReasoningControls(enabled: true, effort: .max)
            ),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 3)
        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "msg_opencode_deepseek")
        guard case .contentDelta(.text(let content)) = events[1] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "OK")
        guard case .messageEnd = events[2] else { return XCTFail("Expected messageEnd") }
    }

    func testOpenCodeGoValidateAPIKeyUsesMessagesEndpointForAnthropicRoutedModel() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "opencode",
            name: "OpenCode Go",
            type: .opencodeGo,
            apiKey: "ignored",
            models: [
                ModelInfo(
                    id: "deepseek-v4-flash",
                    name: "DeepSeek V4 Flash",
                    capabilities: [.streaming, .toolCalling, .reasoning],
                    contextWindow: 1_000_000
                )
            ]
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://opencode.ai/zen/go/v1/messages")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "deepseek-v4-flash")
            XCTAssertEqual(root["max_tokens"] as? Int, 1)
            XCTAssertEqual(root["stream"] as? Bool, false)

            let response = ["id": "msg_validation"]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenCodeGoAdapter(providerConfig: providerConfig, apiKey: "ignored", networkManager: networkManager)
        let isValid = try await adapter.validateAPIKey("test-key")
        XCTAssertTrue(isValid)
    }

    func testOpenRouterAdapterOmitsWebPluginWhenModelWebSearchOverrideIsDisabled() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testOpenRouterAdapterSendsNestedXHighEffortForDeepSeekV4Models() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
            XCTAssertEqual(root["model"] as? String, "deepseek/deepseek-v4-pro")
            XCTAssertNil(root["reasoning_effort"])
            XCTAssertEqual(root["include_reasoning"] as? Bool, true)

            let reasoning = try XCTUnwrap(root["reasoning"] as? [String: Any])
            XCTAssertEqual(reasoning["effort"] as? String, "xhigh")

            let response: [String: Any] = [
                "id": "cmpl_or_deepseek_v4",
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
            modelID: "deepseek/deepseek-v4-pro",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .max)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenRouterAdapterClampsUnsupportedXHighEffortToHigh() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
            XCTAssertEqual(reasoning["effort"] as? String, "high")

            let response: [String: Any] = [
                "id": "cmpl_or_high",
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
            modelID: "openai/gpt-5",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .xhigh)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenRouterAdapterParsesReasoningDetailsWhenReasoningFieldIsMissing() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testOpenRouterImageGenerationModelBuildsModalitiesSeedAndParsesImages() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

            XCTAssertEqual(root["model"] as? String, "openai/gpt-5.4-image-2")
            XCTAssertEqual(root["stream"] as? Bool, false)
            XCTAssertEqual(root["seed"] as? Int, 42)
            XCTAssertNil(root["temperature"])
            XCTAssertNil(root["top_p"])
            XCTAssertNil(root["top_k"])
            XCTAssertNil(root["min_p"])
            XCTAssertNil(root["repetition_penalty"])
            XCTAssertNil(root["tools"])
            XCTAssertNil(root["plugins"])

            let modalities = try XCTUnwrap(root["modalities"] as? [String])
            XCTAssertEqual(modalities, ["image"])

            let response: [String: Any] = [
                "id": "cmpl_or_img_1",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "images": [
                                [
                                    "type": "image_url",
                                    "image_url": "data:image/png;base64,AQID"
                                ]
                            ]
                        ],
                        "finish_reason": "stop"
                    ]
                ],
                "usage": [
                    "prompt_tokens": 4,
                    "completion_tokens": 6,
                    "total_tokens": 10
                ]
            ]

            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenRouterAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("draw a lantern")])],
            modelID: "openai/gpt-5.4-image-2",
            controls: GenerationControls(
                temperature: 0.7,
                topP: 0.9,
                imageGeneration: ImageGenerationControls(
                    responseMode: .imageOnly,
                    aspectRatio: .ratio16x9,
                    seed: 42
                ),
                providerSpecific: [
                    "temperature": AnyCodable(0.3),
                    "top_p": AnyCodable(0.4),
                    "top_k": AnyCodable(50),
                    "min_p": AnyCodable(0.2),
                    "repetition_penalty": AnyCodable(1.1)
                ]
            ),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        guard events.count == 3 else {
            return XCTFail("Expected 3 events, got \(events.count)")
        }
        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "cmpl_or_img_1")

        guard case .contentDelta(.image(let image)) = events[1] else { return XCTFail("Expected image delta") }
        XCTAssertEqual(image.mimeType, "image/png")
        XCTAssertEqual(image.data, Data([0x01, 0x02, 0x03]))

        guard case .messageEnd(let usage) = events[2] else { return XCTFail("Expected messageEnd") }
        XCTAssertEqual(usage?.inputTokens, 4)
        XCTAssertEqual(usage?.outputTokens, 6)
    }

    func testOpenRouterImageGenerationModelStreamingParsesDeltaImages() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
            let modalities = try XCTUnwrap(root["modalities"] as? [String])
            XCTAssertEqual(modalities, ["text", "image"])

            let sse = """
            data: {"id":"cmpl_or_img_stream","choices":[{"index":0,"delta":{"content":"Rendered","images":[{"type":"image_url","image_url":"data:image/png;base64,BAUG"}]}}]}

            data: [DONE]
            """

            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!,
                Data(sse.utf8)
            )
        }

        let adapter = OpenRouterAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("draw a lantern")])],
            modelID: "openai/gpt-5.4-image-2",
            controls: GenerationControls(),
            tools: [],
            streaming: true
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        guard events.count == 4 else {
            return XCTFail("Expected 4 events, got \(events.count)")
        }
        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "cmpl_or_img_stream")

        guard case .contentDelta(.text(let text)) = events[1] else { return XCTFail("Expected text delta") }
        XCTAssertEqual(text, "Rendered")

        guard case .contentDelta(.image(let image)) = events[2] else { return XCTFail("Expected image delta") }
        XCTAssertEqual(image.mimeType, "image/png")
        XCTAssertEqual(image.data, Data([0x04, 0x05, 0x06]))

        guard case .messageEnd = events[3] else { return XCTFail("Expected messageEnd") }
    }

    func testOpenRouterImageGenerationModelRejectsNonHTTPRemoteImageURLSchemes() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "or",
            name: "OpenRouter",
            type: .openrouter,
            apiKey: "ignored",
            baseURL: "https://openrouter.ai/api/v1"
        )

        protocolType.requestHandler = { request in
            let response: [String: Any] = [
                "id": "cmpl_or_img_scheme",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "images": [
                                [
                                    "type": "image_url",
                                    "image_url": "file:///etc/passwd"
                                ]
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
            messages: [Message(role: .user, content: [.text("draw a lantern")])],
            modelID: "openai/gpt-5.4-image-2",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        guard events.count == 2 else {
            return XCTFail("Expected 2 events, got \(events.count)")
        }
        guard case .messageStart = events[0] else { return XCTFail("Expected messageStart") }
        guard case .messageEnd = events[1] else { return XCTFail("Expected messageEnd") }
    }

    func testOpenRouterImageGenerationModelParsesDataURLsWithoutExplicitMediaType() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "or",
            name: "OpenRouter",
            type: .openrouter,
            apiKey: "ignored",
            baseURL: "https://openrouter.ai/api/v1"
        )

        protocolType.requestHandler = { request in
            let response: [String: Any] = [
                "id": "cmpl_or_img_data_url",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "images": [
                                [
                                    "type": "image_url",
                                    "image_url": "data:;base64,AQID"
                                ],
                                [
                                    "type": "image_url",
                                    "image_url": "data:,hello%20world"
                                ]
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
            messages: [Message(role: .user, content: [.text("draw a lantern")])],
            modelID: "openai/gpt-5.4-image-2",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        guard events.count == 4 else {
            return XCTFail("Expected 4 events, got \(events.count)")
        }
        guard case .contentDelta(.image(let firstImage)) = events[1] else {
            return XCTFail("Expected first image delta")
        }
        XCTAssertEqual(firstImage.mimeType, "image/png")
        XCTAssertEqual(firstImage.data, Data([0x01, 0x02, 0x03]))

        guard case .contentDelta(.image(let secondImage)) = events[2] else {
            return XCTFail("Expected second image delta")
        }
        XCTAssertEqual(secondImage.mimeType, "image/png")
        XCTAssertEqual(secondImage.data, Data("hello world".utf8))
    }


    func testOpenAICompatibleAdapterNormalizesRootBaseURLAndParsesReasoningContent() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testOpenAICompatibleAdapterClampsUnsupportedXHighEffortToHigh() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
            XCTAssertEqual(reasoning["effort"] as? String, "high")

            let response: [String: Any] = [
                "id": "cmpl_oac_high",
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
            modelID: "openai/gpt-5",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .xhigh)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenAICompatibleAdapterDoesNotInferAnthropicShapeFromModelName() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testCloudflareAIGatewayAdapterDefaultsPromptCacheTTLToFiveMinutes() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "cf",
            name: "Cloudflare AI Gateway",
            type: .cloudflareAIGateway,
            apiKey: "ignored",
            baseURL: "https://gateway.ai.cloudflare.com/v1/account/gateway/compat"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://gateway.ai.cloudflare.com/v1/account/gateway/compat/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "cf-aig-cache-ttl"), "300")
            XCTAssertNil(request.value(forHTTPHeaderField: "cf-aig-skip-cache"))

            let response: [String: Any] = [
                "id": "cmpl_cf_default_ttl",
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
            modelID: "@cf/meta/llama-3.1-8b-instruct",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testCloudflareAIGatewayAdapterNormalizesLegacyProviderPlaceholderToCompat() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "cf",
            name: "Cloudflare AI Gateway",
            type: .cloudflareAIGateway,
            apiKey: "ignored",
            baseURL: "https://gateway.ai.cloudflare.com/v1/account/gateway/{provider}"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://gateway.ai.cloudflare.com/v1/account/gateway/compat/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "cf-aig-cache-ttl"), "300")

            let response: [String: Any] = [
                "id": "cmpl_cf_legacy_provider_placeholder",
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
            modelID: "@cf/meta/llama-3.1-8b-instruct",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testCloudflareAIGatewayAdapterMapsContextCacheTTLToHeader() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "cf",
            name: "Cloudflare AI Gateway",
            type: .cloudflareAIGateway,
            apiKey: "ignored",
            baseURL: "https://gateway.ai.cloudflare.com/v1/account/gateway/openai"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "cf-aig-cache-ttl"), "3600")
            XCTAssertNil(request.value(forHTTPHeaderField: "cf-aig-skip-cache"))

            let response: [String: Any] = [
                "id": "cmpl_cf_hour",
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
            modelID: "@cf/meta/llama-3.1-8b-instruct",
            controls: GenerationControls(
                contextCache: ContextCacheControls(mode: .implicit, ttl: .hour1)
            ),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testCloudflareAIGatewayAdapterUsesKimiK26ThinkingToggleWhenReasoningEnabled() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "cf",
            name: "Cloudflare AI Gateway",
            type: .cloudflareAIGateway,
            apiKey: "ignored",
            baseURL: "https://gateway.ai.cloudflare.com/v1/account/gateway/compat"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "@cf/moonshotai/kimi-k2.6")
            XCTAssertNil(root["reasoning"])
            XCTAssertEqual(root["reasoning_effort"] as? String, "medium")

            let template = try XCTUnwrap(root["chat_template_kwargs"] as? [String: Any])
            XCTAssertEqual(template["thinking"] as? Bool, true)
            XCTAssertEqual(template["existing"] as? String, "value")

            let response: [String: Any] = [
                "id": "cmpl_cf_k26_enabled",
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

        var controls = GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .medium))
        controls.providerSpecific = [
            "chat_template_kwargs": AnyCodable(["existing": "value"])
        ]

        let adapter = OpenAICompatibleAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "@cf/moonshotai/kimi-k2.6",
            controls: controls,
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testCloudflareAIGatewayAdapterUsesKimiK26ThinkingToggleWhenReasoningDisabled() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "cf",
            name: "Cloudflare AI Gateway",
            type: .cloudflareAIGateway,
            apiKey: "ignored",
            baseURL: "https://gateway.ai.cloudflare.com/v1/account/gateway/compat"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "@cf/moonshotai/kimi-k2.6")
            XCTAssertNil(root["reasoning"])
            XCTAssertNil(root["reasoning_effort"])

            let template = try XCTUnwrap(root["chat_template_kwargs"] as? [String: Any])
            XCTAssertEqual(template["thinking"] as? Bool, false)

            let response: [String: Any] = [
                "id": "cmpl_cf_k26_disabled",
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
            modelID: "@cf/moonshotai/kimi-k2.6",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: false)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testCloudflareAIGatewayAdapterParsesKimiK26ReasoningField() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "cf",
            name: "Cloudflare AI Gateway",
            type: .cloudflareAIGateway,
            apiKey: "ignored",
            baseURL: "https://gateway.ai.cloudflare.com/v1/account/gateway/compat"
        )

        protocolType.requestHandler = { request in
            let response: [String: Any] = [
                "id": "cmpl_cf_reasoning",
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
                    "prompt_tokens": 5,
                    "completion_tokens": 7,
                    "total_tokens": 12
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAICompatibleAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "@cf/moonshotai/kimi-k2.6",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 4)

        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "cmpl_cf_reasoning")

        guard case .thinkingDelta(.thinking(let reasoning, _)) = events[1] else {
            return XCTFail("Expected thinkingDelta")
        }
        XCTAssertEqual(reasoning, "R")

        guard case .contentDelta(.text(let content)) = events[2] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "OK")

        guard case .messageEnd(let usage) = events[3] else { return XCTFail("Expected messageEnd") }
        XCTAssertEqual(usage?.inputTokens, 5)
        XCTAssertEqual(usage?.outputTokens, 7)
    }

    func testCloudflareAIGatewayAdapterSendsSkipCacheHeaderWhenContextCacheOff() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "cf",
            name: "Cloudflare AI Gateway",
            type: .cloudflareAIGateway,
            apiKey: "ignored",
            baseURL: "https://gateway.ai.cloudflare.com/v1/account/gateway/openai"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "cf-aig-skip-cache"), "true")
            XCTAssertNil(request.value(forHTTPHeaderField: "cf-aig-cache-ttl"))

            let response: [String: Any] = [
                "id": "cmpl_cf_skip",
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
            modelID: "@cf/meta/llama-3.1-8b-instruct",
            controls: GenerationControls(
                contextCache: ContextCacheControls(mode: .off)
            ),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenAICompatibleAdapterFetchModelsNormalizesAPIBaseURL() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testOpenAICompatibleAdapterFetchModelsForVercelUsesCatalogWhenKnown() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "vercel",
            name: "Vercel AI Gateway",
            type: .vercelAIGateway,
            apiKey: "ignored",
            baseURL: "https://ai-gateway.vercel.sh"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://ai-gateway.vercel.sh/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let payload: [String: Any] = [
                "data": [
                    [
                        "id": "openai/gpt-5.2",
                        "name": "GPT 5.2 (Gateway)",
                        "context_window": 400_000,
                        "max_tokens": 128_000,
                        "type": "language",
                        "tags": ["tool-use", "reasoning", "vision", "implicit-caching"],
                    ],
                    [
                        "id": "moonshotai/kimi-k2.6",
                        "name": "Kimi K2.6 (Gateway)",
                        "context_window": 262_144,
                        "max_tokens": 262_144,
                        "type": "language",
                        "tags": ["tool-use", "reasoning", "vision", "implicit-caching"],
                    ],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAICompatibleAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        let model = try XCTUnwrap(byID["openai/gpt-5.2"])

        XCTAssertEqual(model.id, "openai/gpt-5.2")
        XCTAssertEqual(model.name, "GPT-5.2")
        XCTAssertEqual(model.contextWindow, 400_000)
        XCTAssertTrue(model.capabilities.contains(.reasoning))
        XCTAssertTrue(model.capabilities.contains(.promptCaching))
        XCTAssertEqual(model.reasoningConfig?.type, .effort)

        let kimi = try XCTUnwrap(byID["moonshotai/kimi-k2.6"])
        XCTAssertEqual(kimi.name, "Kimi K2.6")
        XCTAssertEqual(kimi.contextWindow, 262_144)
        XCTAssertEqual(kimi.maxOutputTokens, 262_144)
        XCTAssertTrue(kimi.capabilities.contains(.vision))
        XCTAssertTrue(kimi.capabilities.contains(.reasoning))
        XCTAssertTrue(kimi.capabilities.contains(.promptCaching))
        XCTAssertEqual(kimi.reasoningConfig?.defaultEffort, .medium)
    }

    func testOpenAICompatibleAdapterFetchModelsForDeepInfraUsesCatalogMetadataWhenKnown() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "deepinfra",
            name: "DeepInfra",
            type: .deepinfra,
            apiKey: "ignored",
            baseURL: "https://api.deepinfra.com/v1/openai"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.deepinfra.com/v1/openai/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let payload: [String: Any] = [
                "data": [
                    ["id": "zai-org/GLM-5.1"],
                    ["id": "Qwen/Qwen3.6-35B-A3B"],
                    ["id": "nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning"],
                    ["id": "zai-org/GLM-5"],
                    ["id": "Qwen/Qwen3.5-397B-A17B"],
                    ["id": "deepseek-ai/DeepSeek-V4-Flash"],
                    ["id": "deepseek-ai/DeepSeek-V4-Pro"],
                    ["id": "unknown-model"]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAICompatibleAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        let glm51 = try XCTUnwrap(byID["zai-org/GLM-5.1"])
        XCTAssertEqual(glm51.name, "GLM-5.1")
        XCTAssertEqual(glm51.contextWindow, 202_752)
        XCTAssertTrue(glm51.capabilities.contains(.toolCalling))
        XCTAssertTrue(glm51.capabilities.contains(.reasoning))

        let qwen36 = try XCTUnwrap(byID["Qwen/Qwen3.6-35B-A3B"])
        XCTAssertEqual(qwen36.name, "Qwen3.6 35B A3B")
        XCTAssertEqual(qwen36.contextWindow, 262_144)
        XCTAssertTrue(qwen36.capabilities.contains(.toolCalling))
        XCTAssertTrue(qwen36.capabilities.contains(.vision))
        XCTAssertTrue(qwen36.capabilities.contains(.reasoning))

        let nemotronOmni = try XCTUnwrap(byID["nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning"])
        XCTAssertEqual(nemotronOmni.name, "Nemotron 3 Nano Omni 30B A3B Reasoning")
        XCTAssertEqual(nemotronOmni.contextWindow, 262_144)
        XCTAssertTrue(nemotronOmni.capabilities.contains(.toolCalling))
        XCTAssertTrue(nemotronOmni.capabilities.contains(.vision))
        XCTAssertTrue(nemotronOmni.capabilities.contains(.audio))
        XCTAssertTrue(nemotronOmni.capabilities.contains(.videoInput))
        XCTAssertTrue(nemotronOmni.capabilities.contains(.reasoning))

        let glm5 = try XCTUnwrap(byID["zai-org/GLM-5"])
        XCTAssertEqual(glm5.name, "GLM-5")
        XCTAssertEqual(glm5.contextWindow, 202_752)
        XCTAssertTrue(glm5.capabilities.contains(.toolCalling))
        XCTAssertTrue(glm5.capabilities.contains(.reasoning))

        let qwen397 = try XCTUnwrap(byID["Qwen/Qwen3.5-397B-A17B"])
        XCTAssertEqual(qwen397.name, "Qwen3.5 397B A17B")
        XCTAssertEqual(qwen397.contextWindow, 262_144)
        XCTAssertTrue(qwen397.capabilities.contains(.toolCalling))
        XCTAssertTrue(qwen397.capabilities.contains(.vision))
        XCTAssertFalse(qwen397.capabilities.contains(.reasoning))

        let deepSeekV4Flash = try XCTUnwrap(byID["deepseek-ai/DeepSeek-V4-Flash"])
        XCTAssertEqual(deepSeekV4Flash.name, "DeepSeek V4 Flash")
        XCTAssertEqual(deepSeekV4Flash.contextWindow, 1_048_576)
        XCTAssertNil(deepSeekV4Flash.maxOutputTokens)
        XCTAssertEqual(deepSeekV4Flash.capabilities, [.streaming, .toolCalling, .reasoning, .promptCaching])
        XCTAssertEqual(deepSeekV4Flash.reasoningConfig?.type, .effort)
        XCTAssertEqual(deepSeekV4Flash.reasoningConfig?.defaultEffort, .high)

        let deepSeekV4Pro = try XCTUnwrap(byID["deepseek-ai/DeepSeek-V4-Pro"])
        XCTAssertEqual(deepSeekV4Pro.name, "DeepSeek V4 Pro")
        XCTAssertEqual(deepSeekV4Pro.contextWindow, 65_536)
        XCTAssertNil(deepSeekV4Pro.maxOutputTokens)
        XCTAssertEqual(deepSeekV4Pro.capabilities, [.streaming, .toolCalling, .reasoning, .promptCaching])
        XCTAssertEqual(deepSeekV4Pro.reasoningConfig?.type, .effort)
        XCTAssertEqual(deepSeekV4Pro.reasoningConfig?.defaultEffort, .high)

        let unknown = try XCTUnwrap(byID["unknown-model"])
        XCTAssertEqual(unknown.name, "unknown-model")
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.reasoningConfig)
    }

    func testOpenAICompatibleAdapterBuildsDeepInfraDeepSeekV4ReasoningRequest() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "deepinfra",
            name: "DeepInfra",
            type: .deepinfra,
            apiKey: "ignored",
            baseURL: "https://api.deepinfra.com/v1/openai"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.deepinfra.com/v1/openai/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "deepseek-ai/DeepSeek-V4-Flash")
            XCTAssertEqual(root["stream"] as? Bool, false)
            XCTAssertNil(root["reasoning_effort"])

            let reasoning = try XCTUnwrap(root["reasoning"] as? [String: Any])
            XCTAssertEqual(reasoning["effort"] as? String, "high")

            let toolObjects = try XCTUnwrap(root["tools"] as? [[String: Any]])
            XCTAssertEqual(toolObjects.count, 1)
            XCTAssertEqual(toolObjects[0]["type"] as? String, "function")

            let response: [String: Any] = [
                "id": "cmpl_deepinfra_deepseek_v4",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK",
                            "reasoning_content": "R"
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
            modelID: "deepseek-ai/DeepSeek-V4-Flash",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .max)),
            tools: [
                ToolDefinition(
                    id: "tool_1",
                    name: "lookup_status",
                    description: "Lookup a project status by ID.",
                    parameters: ParameterSchema(
                        properties: [
                            "id": PropertySchema(type: "string", description: "Project ID")
                        ],
                        required: ["id"]
                    ),
                    source: .builtin
                )
            ],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 4)
        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "cmpl_deepinfra_deepseek_v4")
        guard case .thinkingDelta(.thinking(let reasoning, _)) = events[1] else { return XCTFail("Expected thinkingDelta") }
        XCTAssertEqual(reasoning, "R")
        guard case .contentDelta(.text(let content)) = events[2] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "OK")
        guard case .messageEnd = events[3] else { return XCTFail("Expected messageEnd") }
    }

    func testOpenAICompatibleAdapterFetchModelsForVercelDerivesConservativeMetadataWhenUnknown() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "vercel",
            name: "Vercel AI Gateway",
            type: .vercelAIGateway,
            apiKey: "ignored",
            baseURL: "https://ai-gateway.vercel.sh/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://ai-gateway.vercel.sh/v1/models")

            let payload: [String: Any] = [
                "data": [
                    [
                        "id": "example/unknown-thinking-model",
                        "context_window": 321_000,
                        "type": "language",
                        "tags": ["reasoning", "implicit-caching"],
                    ],
                    [
                        "id": "example/unknown-image-model",
                        "name": "Unknown Image",
                        "context_window": 8_192,
                        "type": "image",
                        "tags": ["image-generation"],
                    ],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAICompatibleAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()

        XCTAssertEqual(models.map(\.id), ["example/unknown-thinking-model", "example/unknown-image-model"])

        let thinking = try XCTUnwrap(models.first(where: { $0.id == "example/unknown-thinking-model" }))
        XCTAssertEqual(thinking.name, "example/unknown-thinking-model")
        XCTAssertEqual(thinking.contextWindow, 321_000)
        XCTAssertTrue(thinking.capabilities.contains(.streaming))
        XCTAssertTrue(thinking.capabilities.contains(.toolCalling))
        XCTAssertTrue(thinking.capabilities.contains(.reasoning))
        XCTAssertTrue(thinking.capabilities.contains(.promptCaching))
        XCTAssertEqual(thinking.reasoningConfig?.type, .effort)

        let image = try XCTUnwrap(models.first(where: { $0.id == "example/unknown-image-model" }))
        XCTAssertEqual(image.name, "Unknown Image")
        XCTAssertEqual(image.contextWindow, 8_192)
        XCTAssertEqual(image.capabilities, [.imageGeneration])
        XCTAssertNil(image.reasoningConfig)
    }

    func testTogetherAdapterFetchModelsUsesArrayShapeWithoutFilteringByModelType() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "together",
            name: "Together AI",
            type: .together,
            apiKey: "ignored",
            baseURL: "https://api.together.xyz"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.together.xyz/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let payload: [[String: Any]] = [
                [
                    "id": "deepseek-ai/DeepSeek-V3.1",
                    "type": "chat",
                    "display_name": "DeepSeek V3.1",
                ],
                [
                    "id": "openai/gpt-oss-20b",
                    "type": "chat",
                    "display_name": "GPT-OSS 20B",
                ],
                [
                    "id": "Qwen/Qwen3-235B-A22B-Instruct-2507-tput",
                    "type": "chat",
                    "display_name": "Qwen3 235B A22B Instruct 2507",
                ],
                [
                    "id": "Qwen/Qwen3-Coder-Next-FP8",
                    "type": "chat",
                    "display_name": "Qwen3 Coder Next",
                ],
                [
                    "id": "black-forest-labs/flux",
                    "type": "image",
                    "display_name": "FLUX",
                ],
            ]

            let data = try JSONSerialization.data(withJSONObject: payload)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = TogetherAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()

        XCTAssertEqual(
            models.map(\.id),
            [
                "deepseek-ai/DeepSeek-V3.1",
                "openai/gpt-oss-20b",
                "Qwen/Qwen3-235B-A22B-Instruct-2507-tput",
                "Qwen/Qwen3-Coder-Next-FP8",
                "black-forest-labs/flux",
            ]
        )
        XCTAssertEqual(models[0].contextWindow, 128_000)
        XCTAssertTrue(models[0].capabilities.contains(.reasoning))
        XCTAssertEqual(models[0].reasoningConfig?.type, .toggle)
        XCTAssertEqual(models[1].reasoningConfig?.type, .effort)
        XCTAssertEqual(models[2].contextWindow, 262_144)
        XCTAssertFalse(models[2].capabilities.contains(.reasoning))
        XCTAssertEqual(models[3].contextWindow, 262_144)
        XCTAssertFalse(models[3].capabilities.contains(.reasoning))
        XCTAssertEqual(models[4].capabilities, [.streaming, .toolCalling])
    }

    func testTogetherAdapterAppliesReasoningTogglePayloadForToggleModels() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "together",
            name: "Together AI",
            type: .together,
            apiKey: "ignored",
            baseURL: "https://api.together.xyz/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.together.xyz/v1/chat/completions")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            let reasoning = try XCTUnwrap(root["reasoning"] as? [String: Any])
            XCTAssertEqual(reasoning["enabled"] as? Bool, false)
            XCTAssertNil(root["reasoning_effort"])

            let response: [String: Any] = [
                "id": "cmpl_together_toggle",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK",
                        ],
                        "finish_reason": "stop",
                    ],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = TogetherAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "zai-org/GLM-5",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: false)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testTogetherAdapterAppliesReasoningEffortPayloadForEffortModels() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "together",
            name: "Together AI",
            type: .together,
            apiKey: "ignored",
            baseURL: "https://api.together.xyz/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.together.xyz/v1/chat/completions")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["reasoning_effort"] as? String, "high")
            XCTAssertNil(root["reasoning"])

            let response: [String: Any] = [
                "id": "cmpl_together_effort",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK",
                        ],
                        "finish_reason": "stop",
                    ],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = TogetherAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "openai/gpt-oss-20b",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .xhigh)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testTogetherAdapterNormalizesDeepSeekV4ProReasoningEffort() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "together",
            name: "Together AI",
            type: .together,
            apiKey: "ignored",
            baseURL: "https://api.together.xyz/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.together.xyz/v1/chat/completions")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "deepseek-ai/DeepSeek-V4-Pro")
            XCTAssertEqual(root["reasoning_effort"] as? String, "high")
            XCTAssertNil(root["reasoning"])

            let response: [String: Any] = [
                "id": "cmpl_together_deepseek_v4",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK",
                        ],
                        "finish_reason": "stop",
                    ],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = TogetherAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "deepseek-ai/DeepSeek-V4-Pro",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .max)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testTogetherAdapterEncodesInputAudioInUserContent() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "together",
            name: "Together AI",
            type: .together,
            apiKey: "ignored",
            baseURL: "https://api.together.xyz/v1"
        )

        let audioData = Data([0x01, 0x02, 0x03, 0x04])
        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.together.xyz/v1/chat/completions")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            let first = try XCTUnwrap(messages.first)
            let content = try XCTUnwrap(first["content"] as? [[String: Any]])
            let audioPart = try XCTUnwrap(content.first(where: { ($0["type"] as? String) == "input_audio" }))
            let inputAudio = try XCTUnwrap(audioPart["input_audio"] as? [String: Any])

            XCTAssertEqual(inputAudio["format"] as? String, "wav")
            XCTAssertEqual(inputAudio["data"] as? String, audioData.base64EncodedString())

            let response: [String: Any] = [
                "id": "cmpl_together_audio",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK",
                        ],
                        "finish_reason": "stop",
                    ],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = TogetherAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [
                Message(
                    role: .user,
                    content: [
                        .text("Please transcribe this clip."),
                        .audio(AudioContent(mimeType: "audio/wav", data: audioData)),
                    ]
                )
            ],
            modelID: "qwen3-asr-4b",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testTogetherAdapterValidateAPIKeyRethrowsCancellation() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "together",
            name: "Together AI",
            type: .together,
            apiKey: "ignored",
            baseURL: "https://api.together.xyz/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.together.xyz/v1/models")
            throw URLError(.cancelled)
        }

        let adapter = TogetherAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        do {
            _ = try await adapter.validateAPIKey("test-key")
            XCTFail("Expected validateAPIKey to rethrow cancellation.")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error).")
        }
    }

    func testOpenRouterAdapterNormalizesRootBaseURLForKeyValidation() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testOpenRouterAdapterOmitsToolsForXAIGrok420MultiAgent() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "or",
            name: "OpenRouter",
            type: .openrouter,
            apiKey: "ignored",
            baseURL: "https://openrouter.ai/api/v1",
            models: [
                ModelCatalog.modelInfo(
                    for: "x-ai/grok-4.20-multi-agent",
                    provider: .openrouter
                )
            ]
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")

            let body = try XCTUnwrap(requestBodyData(request))
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(root["model"] as? String, "x-ai/grok-4.20-multi-agent")
            XCTAssertNil(root["tools"])

            let reasoning = try XCTUnwrap(root["reasoning"] as? [String: Any])
            XCTAssertEqual(reasoning["effort"] as? String, "xhigh")
            XCTAssertEqual(root["include_reasoning"] as? Bool, true)

            let response: [String: Any] = [
                "id": "cmpl_or_xai_multi",
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
        let tool = ToolDefinition(
            id: "tool_1",
            name: "lookup_status",
            description: "Lookup a project status.",
            parameters: ParameterSchema(
                properties: [
                    "id": PropertySchema(type: "string", description: "Project ID")
                ],
                required: ["id"]
            ),
            source: .builtin
        )

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: "x-ai/grok-4.20-multi-agent",
            controls: GenerationControls(
                reasoning: ReasoningControls(enabled: true, effort: .xhigh)
            ),
            tools: [tool],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenRouterAdapterOmitsToolsForUncataloguedXAIGrok420MultiAgentSnapshot() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let requestedModelID = "x-ai/grok-4.20-multi-agent-0309"

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
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(root["model"] as? String, requestedModelID)
            XCTAssertNil(root["tools"])

            let response: [String: Any] = [
                "id": "cmpl_or_xai_unknown_snapshot",
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
        let tool = ToolDefinition(
            id: "tool_1",
            name: "lookup_status",
            description: "Lookup a project status.",
            parameters: ParameterSchema(
                properties: [
                    "id": PropertySchema(type: "string", description: "Project ID")
                ],
                required: ["id"]
            ),
            source: .builtin
        )

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hello")])],
            modelID: requestedModelID,
            controls: GenerationControls(),
            tools: [tool],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenRouterAdapterOmitsReasoningWhenModelOverrideDisablesReasoning() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testOpenRouterVideoGenerationBuildsSeedanceRequestWithFrameControls() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "or",
            name: "OpenRouter",
            type: .openrouter,
            apiKey: "ignored",
            baseURL: "https://openrouter.ai/api/v1",
            models: [
                ModelCatalog.modelInfo(for: "bytedance/seedance-2.0", provider: .openrouter)
            ]
        )

        let imageOneURL = URL(fileURLWithPath: "/tmp/seedance-first.png")
        let imageTwoURL = URL(fileURLWithPath: "/tmp/seedance-last.png")
        try Data([0x01, 0x02, 0x03]).write(to: imageOneURL, options: .atomic)
        try Data([0x04, 0x05, 0x06]).write(to: imageTwoURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: imageOneURL)
            try? FileManager.default.removeItem(at: imageTwoURL)
        }

        var requestCount = 0
        protocolType.requestHandler = { request in
            requestCount += 1

            if requestCount == 1 {
                XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/videos")
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

                let body = try XCTUnwrap(requestBodyData(request))
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                let root = try XCTUnwrap(json)

                XCTAssertEqual(root["model"] as? String, "bytedance/seedance-2.0")
                XCTAssertEqual(root["prompt"] as? String, "Animate this character turnaround")
                XCTAssertEqual(root["duration"] as? Int, 8)
                XCTAssertEqual(root["aspect_ratio"] as? String, "16:9")
                XCTAssertEqual(root["resolution"] as? String, "720p")
                XCTAssertEqual(root["generate_audio"] as? Bool, true)

                let frameImages = try XCTUnwrap(root["frame_images"] as? [[String: Any]])
                XCTAssertEqual(frameImages.count, 2)
                XCTAssertEqual(frameImages[0]["type"] as? String, "image_url")
                XCTAssertEqual(frameImages[0]["frame_type"] as? String, "first_frame")
                let firstImageURL = try XCTUnwrap(frameImages[0]["image_url"] as? [String: Any])
                XCTAssertTrue((firstImageURL["url"] as? String)?.hasPrefix("data:image/png;base64,") == true)
                XCTAssertEqual(frameImages[1]["frame_type"] as? String, "last_frame")
                let secondImageURL = try XCTUnwrap(frameImages[1]["image_url"] as? [String: Any])
                XCTAssertTrue((secondImageURL["url"] as? String)?.hasPrefix("data:image/png;base64,") == true)

                let provider = try XCTUnwrap(root["provider"] as? [String: Any])
                let options = try XCTUnwrap(provider["options"] as? [String: Any])
                let seedOptions = try XCTUnwrap(options["seed"] as? [String: Any])
                let parameters = try XCTUnwrap(seedOptions["parameters"] as? [String: Any])
                XCTAssertEqual(parameters["watermark"] as? Bool, true)
                XCTAssertEqual(parameters["req_key"] as? String, "job-key-123")

                let response: [String: Any] = [
                    "id": "vid_seed_123",
                    "status": "pending",
                    "polling_url": "https://openrouter.ai/api/v1/videos/vid_seed_123"
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!, data)
            }

            let response: [String: Any] = [
                "status": "failed",
                "error": ["message": "stop after request inspection"]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenRouterAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [
                Message(
                    role: .user,
                    content: [
                        .image(ImageContent(mimeType: "image/png", data: nil, url: imageOneURL)),
                        .image(ImageContent(mimeType: "image/png", data: nil, url: imageTwoURL)),
                        .text("Animate this character turnaround")
                    ]
                )
            ],
            modelID: "bytedance/seedance-2.0",
            controls: GenerationControls(
                openRouterVideoGeneration: OpenRouterVideoGenerationControls(
                    durationSeconds: 8,
                    aspectRatio: .ratio16x9,
                    resolution: .res720p,
                    imageInputMode: .frameImages,
                    generateAudio: true,
                    watermark: true
                ),
                providerSpecific: ["req_key": AnyCodable("job-key-123")]
            ),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        do {
            for try await event in stream {
                events.append(event)
            }
        } catch let error as LLMError {
            guard case .providerError(let code, let message) = error else {
                return XCTFail("Expected provider error, got \(error)")
            }
            XCTAssertEqual(code, "video_generation_failed")
            XCTAssertEqual(message, "stop after request inspection")
        }

        guard case .messageStart(let id)? = events.first else {
            return XCTFail("Expected messageStart")
        }
        XCTAssertEqual(id, "vid_seed_123")
    }

    func testOpenRouterVideoGenerationDropsUnsupportedSeedanceControlsFromRequestBody() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "or",
            name: "OpenRouter",
            type: .openrouter,
            apiKey: "ignored",
            baseURL: "https://openrouter.ai/api/v1",
            models: [
                ModelCatalog.modelInfo(for: "bytedance/seedance-2.0-fast", provider: .openrouter)
            ]
        )

        var requestCount = 0
        protocolType.requestHandler = { request in
            requestCount += 1

            if requestCount == 1 {
                XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/videos")

                let body = try XCTUnwrap(requestBodyData(request))
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                let root = try XCTUnwrap(json)

                XCTAssertEqual(root["model"] as? String, "bytedance/seedance-2.0-fast")
                XCTAssertNil(root["duration"])
                XCTAssertEqual(root["aspect_ratio"] as? String, "9:16")
                XCTAssertNil(root["resolution"])
                XCTAssertEqual(root["generate_audio"] as? Bool, true)
                XCTAssertEqual(root["seed"] as? Int, 42)

                let response: [String: Any] = [
                    "id": "vid_seed_sanitized_1",
                    "status": "pending",
                    "polling_url": "https://openrouter.ai/api/v1/videos/vid_seed_sanitized_1"
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!, data)
            }

            let response: [String: Any] = [
                "status": "failed",
                "error": ["message": "stop after sanitized request inspection"]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenRouterAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("Animate a hovering hologram koi")])],
            modelID: "bytedance/seedance-2.0-fast",
            controls: GenerationControls(
                openRouterVideoGeneration: OpenRouterVideoGenerationControls(
                    durationSeconds: 16,
                    aspectRatio: .ratio9x16,
                    resolution: .res1080p,
                    generateAudio: true,
                    seed: 42
                )
            ),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        do {
            for try await event in stream {
                events.append(event)
            }
        } catch let error as LLMError {
            guard case .providerError(let code, let message) = error else {
                return XCTFail("Expected provider error, got \(error)")
            }
            XCTAssertEqual(code, "video_generation_failed")
            XCTAssertEqual(message, "stop after sanitized request inspection")
        }

        guard case .messageStart(let id)? = events.first else {
            return XCTFail("Expected messageStart")
        }
        XCTAssertEqual(id, "vid_seed_sanitized_1")
    }

    func testOpenRouterVideoGenerationIgnoresUntrustedPollingURL() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "or",
            name: "OpenRouter",
            type: .openrouter,
            apiKey: "ignored",
            baseURL: "https://proxy.example.com/openrouter/v1",
            models: [
                ModelCatalog.modelInfo(for: "bytedance/seedance-2.0", provider: .openrouter)
            ]
        )

        var requestCount = 0
        protocolType.requestHandler = { request in
            requestCount += 1

            if requestCount == 1 {
                XCTAssertEqual(request.url?.absoluteString, "https://proxy.example.com/openrouter/v1/videos")

                let response: [String: Any] = [
                    "id": "vid_seed_proxy_1",
                    "status": "pending",
                    "polling_url": "https://evil.example.com/api/v1/videos/vid_seed_proxy_1"
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!, data)
            }

            XCTAssertEqual(request.url?.absoluteString, "https://proxy.example.com/openrouter/v1/videos/vid_seed_proxy_1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let response: [String: Any] = [
                "status": "failed",
                "error": ["message": "stop after trusted-origin fallback"]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenRouterAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("Animate a chrome sparrow")])],
            modelID: "bytedance/seedance-2.0",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        do {
            for try await event in stream {
                events.append(event)
            }
        } catch let error as LLMError {
            guard case .providerError(let code, let message) = error else {
                return XCTFail("Expected provider error, got \(error)")
            }
            XCTAssertEqual(code, "video_generation_failed")
            XCTAssertEqual(message, "stop after trusted-origin fallback")
        }

        XCTAssertEqual(requestCount, 2)
        guard case .messageStart(let id)? = events.first else {
            return XCTFail("Expected messageStart")
        }
        XCTAssertEqual(id, "vid_seed_proxy_1")
    }

    func testOpenRouterVideoGenerationPollsUntilDoneAndPrefersAuthorizedContentEndpoint() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "or",
            name: "OpenRouter",
            type: .openrouter,
            apiKey: "ignored",
            baseURL: "https://openrouter.ai/api/v1",
            models: [
                ModelCatalog.modelInfo(for: "bytedance/seedance-2.0-fast", provider: .openrouter)
            ]
        )

        let fakeVideoBytes = Data([0x00, 0x00, 0x00, 0x1C, 0x66, 0x74, 0x79, 0x70])

        var requestCount = 0
        protocolType.requestHandler = { request in
            requestCount += 1

            if requestCount == 1 {
                XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/videos")
                let response: [String: Any] = [
                    "id": "vid_seed_done_1",
                    "status": "pending",
                    "polling_url": "https://openrouter.ai/api/v1/videos/vid_seed_done_1"
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!, data)
            } else if requestCount == 2 {
                XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/videos/vid_seed_done_1")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
                let response: [String: Any] = [
                    "id": "vid_seed_done_1",
                    "status": "completed",
                    "output": [["type": "video"]],
                    "unsigned_urls": ["https://openrouter.ai/api/v1/videos/vid_seed_done_1/content?index=0"]
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            } else {
                XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/videos/vid_seed_done_1/content?index=0")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "video/mp4"]
                    )!,
                    fakeVideoBytes
                )
            }
        }

        let adapter = OpenRouterAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("A neon city drive at night")])],
            modelID: "bytedance/seedance-2.0-fast",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(requestCount, 3)

        guard case .messageStart(let id) = events[0] else {
            return XCTFail("Expected messageStart")
        }
        XCTAssertEqual(id, "vid_seed_done_1")

        let videoEvent = events.first { event in
            if case .contentDelta(.video) = event { return true }
            return false
        }
        guard case .contentDelta(.video(let video)) = videoEvent else {
            return XCTFail("Expected contentDelta with video")
        }
        XCTAssertEqual(video.mimeType, "video/mp4")
        XCTAssertNotNil(video.url)
        XCTAssertTrue(video.url?.isFileURL == true)

        let localURL = try XCTUnwrap(video.url)
        let savedData = try Data(contentsOf: localURL)
        XCTAssertEqual(savedData, fakeVideoBytes)
        try? FileManager.default.removeItem(at: localURL)

        guard case .messageEnd(let usage)? = events.last else {
            return XCTFail("Expected messageEnd")
        }
        XCTAssertNil(usage)
    }

    func testOpenRouterVideoGenerationFallsBackToUnsignedURLWhenAuthorizedContentDownloadFails() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "or",
            name: "OpenRouter",
            type: .openrouter,
            apiKey: "ignored",
            baseURL: "https://openrouter.ai/api/v1",
            models: [
                ModelCatalog.modelInfo(for: "bytedance/seedance-2.0-fast", provider: .openrouter)
            ]
        )

        let fakeVideoBytes = Data([0x00, 0x00, 0x00, 0x1C, 0x66, 0x74, 0x79, 0x70])

        var requestCount = 0
        protocolType.requestHandler = { request in
            requestCount += 1

            if requestCount == 1 {
                XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/videos")
                let response: [String: Any] = [
                    "id": "vid_seed_unsigned_fallback_1",
                    "status": "pending",
                    "polling_url": "https://openrouter.ai/api/v1/videos/vid_seed_unsigned_fallback_1"
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!, data)
            } else if requestCount == 2 {
                XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/videos/vid_seed_unsigned_fallback_1")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
                let response: [String: Any] = [
                    "id": "vid_seed_unsigned_fallback_1",
                    "status": "completed",
                    "output": [["type": "video"]],
                    "unsigned_urls": ["https://cdn.example.com/seedance/video.mp4"]
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            } else if requestCount == 3 {
                XCTAssertEqual(
                    request.url?.absoluteString,
                    "https://openrouter.ai/api/v1/videos/vid_seed_unsigned_fallback_1/content?index=0"
                )
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
                let data = Data("{\"error\":\"not ready\"}".utf8)
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 404,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!,
                    data
                )
            }

            XCTAssertEqual(request.url?.absoluteString, "https://cdn.example.com/seedance/video.mp4")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "video/mp4"]
                )!,
                fakeVideoBytes
            )
        }

        let adapter = OpenRouterAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("A glowing jellyfish drifts over downtown")])],
            modelID: "bytedance/seedance-2.0-fast",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(requestCount, 4)

        let videoEvent = events.first { event in
            if case .contentDelta(.video) = event { return true }
            return false
        }
        guard case .contentDelta(.video(let video)) = videoEvent else {
            return XCTFail("Expected contentDelta with video")
        }
        XCTAssertEqual(video.mimeType, "video/mp4")

        let localURL = try XCTUnwrap(video.url)
        let savedData = try Data(contentsOf: localURL)
        XCTAssertEqual(savedData, fakeVideoBytes)
        try? FileManager.default.removeItem(at: localURL)
    }

    func testOpenRouterVideoGenerationUsesAuthorizedFallbackDownloadEndpoint() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "or",
            name: "OpenRouter",
            type: .openrouter,
            apiKey: "ignored",
            baseURL: "https://openrouter.ai/api/v1",
            models: [
                ModelCatalog.modelInfo(for: "bytedance/seedance-2.0-fast", provider: .openrouter)
            ]
        )

        let fakeVideoBytes = Data([0x00, 0x00, 0x00, 0x1C, 0x66, 0x74, 0x79, 0x70])

        var requestCount = 0
        protocolType.requestHandler = { request in
            requestCount += 1

            if requestCount == 1 {
                XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/videos")
                let response: [String: Any] = [
                    "id": "vid_seed_fallback_1",
                    "status": "pending",
                    "polling_url": "https://openrouter.ai/api/v1/videos/vid_seed_fallback_1"
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!, data)
            } else if requestCount == 2 {
                XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/videos/vid_seed_fallback_1")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
                let response: [String: Any] = [
                    "id": "vid_seed_fallback_1",
                    "status": "completed",
                    "output": [["type": "video"]]
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }

            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/videos/vid_seed_fallback_1/content?index=0")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "video/mp4"]
                )!,
                fakeVideoBytes
            )
        }

        let adapter = OpenRouterAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("A silver paper plane flies through rain")])],
            modelID: "bytedance/seedance-2.0-fast",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(requestCount, 3)

        let videoEvent = events.first { event in
            if case .contentDelta(.video) = event { return true }
            return false
        }
        guard case .contentDelta(.video(let video)) = videoEvent else {
            return XCTFail("Expected contentDelta with video")
        }
        XCTAssertEqual(video.mimeType, "video/mp4")

        let localURL = try XCTUnwrap(video.url)
        let savedData = try Data(contentsOf: localURL)
        XCTAssertEqual(savedData, fakeVideoBytes)
        try? FileManager.default.removeItem(at: localURL)
    }

    func testZhipuCodingPlanAdapterUsesDedicatedEndpointAndThinkingPayload() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "zhipu-coding-plan",
            name: "Zhipu Coding Plan",
            type: .zhipuCodingPlan,
            apiKey: "ignored",
            baseURL: "https://open.bigmodel.cn/api/coding/paas/v4",
            models: ModelCatalog.seededModels(for: .zhipuCodingPlan)
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["model"] as? String, "glm-5")

            let thinking = try XCTUnwrap(root["thinking"] as? [String: Any])
            XCTAssertEqual(thinking["type"] as? String, "enabled")
            XCTAssertNil(root["reasoning"])

            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 3)
            XCTAssertEqual(messages[1]["role"] as? String, "assistant")
            XCTAssertEqual(messages[1]["reasoning_content"] as? String, "previous-think")
            XCTAssertNil(messages[1]["reasoning"])

            let response: [String: Any] = [
                "id": "cmpl_zhipu",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": "OK",
                            "reasoning_content": "new-think"
                        ],
                        "finish_reason": "stop"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAICompatibleAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let messages: [Message] = [
            Message(role: .user, content: [.text("first")]),
            Message(role: .assistant, content: [.text("answer"), .thinking(ThinkingBlock(text: "previous-think"))]),
            Message(role: .user, content: [.text("second")]),
        ]
        let stream = try await adapter.sendMessage(
            messages: messages,
            modelID: "glm-5",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .high)),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 4)
        guard case .messageStart = events[0] else { return XCTFail("Expected messageStart") }
        guard case .thinkingDelta(.thinking(let reasoning, _)) = events[1] else { return XCTFail("Expected thinkingDelta") }
        XCTAssertEqual(reasoning, "new-think")
        guard case .contentDelta(.text(let content)) = events[2] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "OK")
        guard case .messageEnd = events[3] else { return XCTFail("Expected messageEnd") }
    }

    func testOpenAICompatibleMistralFetchModelsUsesMedium35CatalogMetadata() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "mistral",
            name: "Mistral",
            type: .mistral,
            apiKey: "ignored",
            baseURL: "https://example.com/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/models")
            let response: [String: Any] = [
                "data": [
                    ["id": "mistral-medium-3.5"],
                    ["id": "unknown-mistral-model"]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAICompatibleAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        let medium = try XCTUnwrap(byID["mistral-medium-3.5"])
        XCTAssertEqual(medium.name, "Mistral Medium 3.5")
        XCTAssertEqual(medium.contextWindow, 262_144)
        XCTAssertNil(medium.maxOutputTokens)
        XCTAssertEqual(medium.capabilities, [.streaming, .toolCalling, .vision, .reasoning])
        XCTAssertEqual(medium.reasoningConfig?.defaultEffort, .high)

        let unknown = try XCTUnwrap(byID["unknown-mistral-model"])
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.reasoningConfig)
    }

    func testOpenAICompatibleMistralMedium35UsesOfficialReasoningAndThinkingChunks() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "mistral",
            name: "Mistral",
            type: .mistral,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/chat/completions")
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "mistral-medium-3.5")
            XCTAssertEqual(root["reasoning_effort"] as? String, "high")
            XCTAssertNil(root["reasoning"])

            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 2)
            XCTAssertEqual(messages[0]["role"] as? String, "assistant")
            let assistantContent = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
            XCTAssertEqual(assistantContent.count, 2)
            XCTAssertEqual(assistantContent[0]["type"] as? String, "thinking")
            XCTAssertEqual(assistantContent[0]["closed"] as? Bool, true)
            let thinking = try XCTUnwrap(assistantContent[0]["thinking"] as? [[String: Any]])
            XCTAssertEqual(thinking[0]["type"] as? String, "text")
            XCTAssertEqual(thinking[0]["text"] as? String, "previous-think")
            XCTAssertEqual(assistantContent[1]["type"] as? String, "text")
            XCTAssertEqual(assistantContent[1]["text"] as? String, "previous-answer")

            let response: [String: Any] = [
                "id": "cmpl_mistral_medium_35",
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": [
                                [
                                    "type": "thinking",
                                    "thinking": [
                                        [
                                            "type": "text",
                                            "text": "new-think"
                                        ]
                                    ],
                                    "closed": true
                                ],
                                [
                                    "type": "text",
                                    "text": "new-answer"
                                ]
                            ]
                        ],
                        "finish_reason": "stop"
                    ]
                ],
                "usage": [
                    "prompt_tokens": 10,
                    "completion_tokens": 20,
                    "total_tokens": 30
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        var controls = GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .medium))
        controls.providerSpecific = [
            "reasoning": AnyCodable(["effort": "low"]),
            "reasoning_effort": AnyCodable("none")
        ]

        let adapter = OpenAICompatibleAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .assistant, content: [
                    .text("previous-answer"),
                    .thinking(ThinkingBlock(text: "previous-think"))
                ]),
                Message(role: .user, content: [.text("next")])
            ],
            modelID: "mistral-medium-3.5",
            controls: controls,
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 4)
        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "cmpl_mistral_medium_35")
        guard case .thinkingDelta(.thinking(let reasoning, _)) = events[1] else { return XCTFail("Expected thinkingDelta") }
        XCTAssertEqual(reasoning, "new-think")
        guard case .contentDelta(.text(let content)) = events[2] else { return XCTFail("Expected contentDelta") }
        XCTAssertEqual(content, "new-answer")
        guard case .messageEnd(let usage) = events[3] else { return XCTFail("Expected messageEnd") }
        XCTAssertEqual(usage?.inputTokens, 10)
        XCTAssertEqual(usage?.outputTokens, 20)
    }

    func testOpenAICompatibleMistralMedium35ReasoningOffUsesNone() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "mistral",
            name: "Mistral",
            type: .mistral,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            XCTAssertEqual(root["reasoning_effort"] as? String, "none")
            XCTAssertNil(root["reasoning"])

            let response: [String: Any] = [
                "id": "cmpl_mistral_off",
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
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "mistral-medium-3.5",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: false)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testZhipuCodingPlanAdapterKeepsThinkingEnabledWhenEffortIsNil() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "zhipu-coding-plan",
            name: "Zhipu Coding Plan",
            type: .zhipuCodingPlan,
            apiKey: "ignored",
            baseURL: "https://open.bigmodel.cn/api/coding/paas/v4",
            models: ModelCatalog.seededModels(for: .zhipuCodingPlan)
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions")
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            let thinking = try XCTUnwrap(root["thinking"] as? [String: Any])
            XCTAssertEqual(thinking["type"] as? String, "enabled")
            XCTAssertNil(root["reasoning"])

            let response: [String: Any] = [
                "id": "cmpl_zhipu_nil_effort",
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
            modelID: "glm-5",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testCohereAdapterBuildsChatRequestAndParsesToolCalls() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

private func makeMockedSessionConfiguration() -> (URLSessionConfiguration, MockURLProtocol.Type) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return (config, MockURLProtocol.self)
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
