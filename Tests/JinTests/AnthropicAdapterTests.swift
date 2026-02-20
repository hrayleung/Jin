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

    func testAnthropicWebSearchDynamicFilteringRequires46Model() async throws {
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
            let tools = try XCTUnwrap(root["tools"] as? [[String: Any]])
            let spec = try XCTUnwrap(tools.first)

            XCTAssertEqual(root["model"] as? String, "claude-sonnet-4-5-20250929")
            XCTAssertEqual(spec["type"] as? String, "web_search_20250305")

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let controls = GenerationControls(
            webSearch: WebSearchControls(enabled: true, dynamicFiltering: true)
        )

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "claude-sonnet-4-5-20250929",
            controls: controls,
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicWebSearchPayloadKeepsDomainFiltersMutuallyExclusive() async throws {
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
            let tools = try XCTUnwrap(root["tools"] as? [[String: Any]])
            let spec = try XCTUnwrap(tools.first)

            XCTAssertEqual(spec["allowed_domains"] as? [String], ["example.com"])
            XCTAssertNil(spec["blocked_domains"])

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let controls = GenerationControls(
            webSearch: WebSearchControls(
                enabled: true,
                allowedDomains: [" example.com ", "Example.com"],
                blockedDomains: ["blocked.example.com"]
            )
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

    func testAnthropicProviderSpecificToolsAreSanitizedForWebSearchConstraints() async throws {
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
            let tools = try XCTUnwrap(root["tools"] as? [[String: Any]])
            let webSearch = try XCTUnwrap(tools.first)

            XCTAssertEqual(webSearch["type"] as? String, "web_search_20250305")
            XCTAssertEqual(webSearch["allowed_domains"] as? [String], ["example.com"])
            XCTAssertNil(webSearch["blocked_domains"])
            XCTAssertNil(webSearch["max_uses"])

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        var controls = GenerationControls(webSearch: WebSearchControls(enabled: false))
        controls.providerSpecific["tools"] = AnyCodable([
            [
                "type": "web_search_20260209",
                "name": "web_search",
                "max_uses": 0,
                "allowed_domains": [" example.com ", "Example.com"],
                "blocked_domains": ["blocked.example.com"]
            ]
        ])

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "claude-sonnet-4-5-20250929",
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

    func testAnthropicStreamingEmitsServerToolUseAsSearchActivity() async throws {
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
            data: {"type":"message_start","message":{"id":"msg_server_tool","type":"message","role":"assistant","model":"claude-sonnet-4-6"}}

            event: content_block_start
            data: {"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use","id":"srv_1","name":"web_search","input":{"query":"swift structured concurrency"}}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"url\\":\\"https://example.com/swift\\"}"}}

            event: content_block_stop
            data: {"type":"content_block_stop","index":0}

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
            modelID: "claude-sonnet-4-6",
            controls: GenerationControls(),
            tools: [],
            streaming: true
        )

        var searchEvents: [SearchActivity] = []
        for try await event in stream {
            if case .searchActivity(let activity) = event {
                searchEvents.append(activity)
            }
        }

        XCTAssertGreaterThanOrEqual(searchEvents.count, 2)
        XCTAssertEqual(searchEvents.first?.id, "srv_1")
        XCTAssertEqual(searchEvents.first?.type, "web_search")
        XCTAssertEqual(searchEvents.first?.arguments["query"]?.value as? String, "swift structured concurrency")
        XCTAssertTrue(searchEvents.contains { $0.status == .completed })
    }

    func testAnthropicStreamingEmitsWebSearchToolResultURLs() async throws {
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
            data: {"type":"message_start","message":{"id":"msg_server_tool","type":"message","role":"assistant","model":"claude-sonnet-4-6"}}

            event: content_block_start
            data: {"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use","id":"srv_1","name":"web_search","input":{"query":"swift structured concurrency"}}}

            event: content_block_stop
            data: {"type":"content_block_stop","index":0}

            event: content_block_start
            data: {"type":"content_block_start","index":1,"content_block":{"type":"web_search_tool_result","tool_use_id":"srv_1","content":[{"type":"web_search_result","title":"Swift Concurrency Guide","url":"https://example.com/swift"},{"type":"web_search_result","title":"Structured Concurrency","url":"https://swift.org/documentation/" }]}}

            event: content_block_stop
            data: {"type":"content_block_stop","index":1}

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
            modelID: "claude-sonnet-4-6",
            controls: GenerationControls(),
            tools: [],
            streaming: true
        )

        var searchEvents: [SearchActivity] = []
        for try await event in stream {
            if case .searchActivity(let activity) = event {
                searchEvents.append(activity)
            }
        }

        let sourceEvent = try XCTUnwrap(searchEvents.first(where: { !$0.sourceURLs.isEmpty }))
        XCTAssertEqual(sourceEvent.id, "srv_1")
        XCTAssertTrue(sourceEvent.sourceURLs.contains("https://example.com/swift"))
        XCTAssertTrue(sourceEvent.sourceURLs.contains("https://swift.org/documentation/"))
    }

    func testAnthropicStreamingEmitsCitationSnippetFromCitedText() async throws {
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
            data: {"type":"message_start","message":{"id":"msg_cited_text","type":"message","role":"assistant","model":"claude-sonnet-4-6"}}

            event: content_block_start
            data: {"type":"content_block_start","index":0,"content_block":{"type":"text","citations":[{"type":"web_search_result_location","url":"https://example.com/swift","title":"Swift 6.2","cited_text":"Swift 6.2 improves actor isolation diagnostics."}]}}

            event: content_block_stop
            data: {"type":"content_block_stop","index":0}

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
            modelID: "claude-sonnet-4-6",
            controls: GenerationControls(),
            tools: [],
            streaming: true
        )

        var citationEvent: SearchActivity?
        for try await event in stream {
            guard case .searchActivity(let activity) = event,
                  activity.type == "url_citation" else {
                continue
            }
            citationEvent = activity
            break
        }

        let event = try XCTUnwrap(citationEvent)
        guard let rawSources = event.arguments["sources"]?.value as? [[String: Any]] else {
            return XCTFail("Expected sources payload")
        }
        let snippet = rawSources.first?["snippet"] as? String
        XCTAssertTrue((snippet ?? "").contains("actor isolation diagnostics"))
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

private extension SearchActivity {
    var sourceURLs: [String] {
        guard let value = arguments["sources"]?.value else { return [] }

        let rows: [[String: Any]]
        if let dicts = value as? [[String: Any]] {
            rows = dicts
        } else if let array = value as? [Any] {
            rows = array.compactMap { $0 as? [String: Any] }
        } else {
            rows = []
        }

        return rows.compactMap { $0["url"] as? String }
    }
}
