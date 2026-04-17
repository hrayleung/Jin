import Foundation
import XCTest
@testable import Jin

final class AnthropicAdapterTests: XCTestCase {
    func testAnthropicAdapterDefaultsMaxTokensToClaude45ModelLimitWhenMissing() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testAnthropicOpus46ForcesAdaptiveThinkingEvenWhenBudgetTokensIsSet() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

            // Even though budgetTokens was set, 4.6 should use adaptive thinking
            let thinking = try XCTUnwrap(root["thinking"] as? [String: Any])
            XCTAssertEqual(thinking["type"] as? String, "adaptive")
            XCTAssertNil(thinking["budget_tokens"], "budget_tokens is deprecated on 4.6 models")

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        // Simulate leftover budgetTokens from a model switch (e.g. Opus 4.5 → Opus 4.6)
        let controls = GenerationControls(
            reasoning: ReasoningControls(enabled: true, effort: .high, budgetTokens: 8192)
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

    func testAnthropicOpus46BuildsAdaptiveThinkingAndEffortRequest() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testAnthropicOpus47OmitsSamplingParametersWithoutReasoning() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

            XCTAssertEqual(root["model"] as? String, "claude-opus-4-7")
            XCTAssertEqual(root["max_tokens"] as? Int, 128_000)
            XCTAssertNil(root["thinking"])
            XCTAssertNil(root["temperature"])
            XCTAssertNil(root["top_p"])
            XCTAssertNil(root["top_k"])

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let controls = GenerationControls(
            temperature: 0.3,
            topP: 0.8,
            reasoning: ReasoningControls(enabled: false),
            providerSpecific: [
                "temperature": AnyCodable(0.2),
                "top_p": AnyCodable(0.7),
                "top_k": AnyCodable(5)
            ]
        )

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "claude-opus-4-7",
            controls: controls,
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicOpus47NormalizesLegacyThinkingConfigToAdaptiveSummarized() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

            XCTAssertEqual(root["model"] as? String, "claude-opus-4-7")
            XCTAssertEqual(root["max_tokens"] as? Int, 128_000)

            let thinking = try XCTUnwrap(root["thinking"] as? [String: Any])
            XCTAssertEqual(thinking["type"] as? String, "adaptive")
            XCTAssertEqual(thinking["display"] as? String, "summarized")
            XCTAssertNil(thinking["budget_tokens"])

            let outputConfig = try XCTUnwrap(root["output_config"] as? [String: Any])
            XCTAssertEqual(outputConfig["effort"] as? String, "xhigh")

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let controls = GenerationControls(
            reasoning: ReasoningControls(enabled: true, effort: .xhigh, budgetTokens: 2048),
            providerSpecific: [
                "thinking": AnyCodable([
                    "type": "enabled",
                    "budget_tokens": 2048
                ])
            ]
        )

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "claude-opus-4-7",
            controls: controls,
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicOpus47IgnoresMalformedProviderSpecificThinkingAndStillSendsDefaultThinking() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

            let thinking = try XCTUnwrap(root["thinking"] as? [String: Any])
            XCTAssertEqual(thinking["type"] as? String, "adaptive")
            XCTAssertEqual(thinking["display"] as? String, "summarized")
            XCTAssertNil(thinking["budget_tokens"])

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let controls = GenerationControls(
            reasoning: ReasoningControls(enabled: true, effort: .high),
            providerSpecific: [
                "thinking": AnyCodable("invalid-thinking-value")
            ]
        )

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "claude-opus-4-7",
            controls: controls,
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicOpus47HonorsExplicitOmittedThinkingDisplaySelection() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

            let thinking = try XCTUnwrap(root["thinking"] as? [String: Any])
            XCTAssertEqual(thinking["type"] as? String, "adaptive")
            XCTAssertEqual(thinking["display"] as? String, "omitted")
            XCTAssertNil(thinking["budget_tokens"])

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let controls = GenerationControls(
            reasoning: ReasoningControls(
                enabled: true,
                effort: .xhigh,
                anthropicThinkingDisplay: .omitted
            )
        )

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "claude-opus-4-7",
            controls: controls,
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicSonnet46BuildsAdaptiveThinkingWithoutMaxEffort() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testAnthropicOpus45BuildsBudgetThinkingWithoutEffortWhenNoEffortSet() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testAnthropicOpus45BuildsBudgetThinkingWithEffortWhenEffortSet() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
            reasoning: ReasoningControls(enabled: true, effort: .high, budgetTokens: 4096)
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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testAnthropicAdapterUploadsPDFViaFilesAPIAndUsesFileSource() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        var uploadCount = 0

        protocolType.requestHandler = { request in
            switch request.url?.path {
            case "/files":
                uploadCount += 1
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
                XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

                let body = try XCTUnwrap(requestBodyData(request))
                let bodyString = String(decoding: body, as: UTF8.self)
                XCTAssertTrue(bodyString.contains("name=\"purpose\""))
                XCTAssertTrue(bodyString.contains("user_data"))
                XCTAssertTrue(bodyString.contains("filename=\"paper.pdf\""))

                let response: [String: Any] = [
                    "id": "file_ant_123",
                    "filename": "paper.pdf",
                    "mime_type": "application/pdf"
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data
                )

            case "/messages":
                let body = try XCTUnwrap(requestBodyData(request))
                let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
                let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
                let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
                let document = try XCTUnwrap(content.first(where: { ($0["type"] as? String) == "document" }))
                let source = try XCTUnwrap(document["source"] as? [String: Any])
                XCTAssertEqual(source["type"] as? String, "file")
                XCTAssertEqual(source["file_id"] as? String, "file_ant_123")

                let response = Data("data: [DONE]\n\n".utf8)
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    response
                )

            default:
                XCTFail("Unexpected request: \(request.url?.absoluteString ?? "<nil>")")
                return (
                    HTTPURLResponse(url: request.url ?? URL(string: "https://example.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [
                Message(
                    role: .user,
                    content: [
                        .file(FileContent(
                            mimeType: "application/pdf",
                            filename: "paper.pdf",
                            data: Data([0x25, 0x50, 0x44, 0x46]),
                            url: nil,
                            extractedText: "PDF"
                        ))
                    ]
                )
            ],
            modelID: "claude-opus-4-6",
            controls: GenerationControls(pdfProcessingMode: .native),
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
        XCTAssertEqual(uploadCount, 1)
    }

    func testAnthropicPrefixWindowUsesTopLevelCacheControl() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

            let topLevelCache = try XCTUnwrap(root["cache_control"] as? [String: Any])
            XCTAssertEqual(topLevelCache["type"] as? String, "ephemeral")
            XCTAssertEqual(topLevelCache["ttl"] as? String, "1h")

            let system = try XCTUnwrap(root["system"] as? [[String: Any]])
            XCTAssertNil(system.first?["cache_control"])

            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            let firstContent = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
            XCTAssertNil(firstContent.first?["cache_control"])

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let controls = GenerationControls(
            contextCache: ContextCacheControls(
                mode: .implicit,
                strategy: .prefixWindow,
                ttl: .hour1
            )
        )

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .system, content: [.text("You are helpful.")]),
                Message(role: .user, content: [.text("hi")])
            ],
            modelID: "claude-sonnet-4-6",
            controls: controls,
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicCacheControlsDoNotUseOpenAIPromptCacheFields() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

            let topLevelCache = try XCTUnwrap(root["cache_control"] as? [String: Any])
            XCTAssertEqual(topLevelCache["type"] as? String, "ephemeral")
            XCTAssertEqual(topLevelCache["ttl"] as? String, "1h")

            XCTAssertNil(root["prompt_cache_key"])
            XCTAssertNil(root["prompt_cache_retention"])
            XCTAssertNil(root["prompt_cache_min_tokens"])

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let controls = GenerationControls(
            contextCache: ContextCacheControls(
                mode: .implicit,
                strategy: .prefixWindow,
                ttl: .hour1,
                cacheKey: "stable-prefix",
                minTokensThreshold: 1024
            )
        )

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .system, content: [.text("You are helpful.")]),
                Message(role: .user, content: [.text("hi")])
            ],
            modelID: "claude-sonnet-4-6",
            controls: controls,
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicSystemOnlyUsesBlockLevelCacheControl() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

            XCTAssertNil(root["cache_control"])

            let system = try XCTUnwrap(root["system"] as? [[String: Any]])
            let systemCache = try XCTUnwrap(system.first?["cache_control"] as? [String: Any])
            XCTAssertEqual(systemCache["type"] as? String, "ephemeral")
            XCTAssertEqual(systemCache["ttl"] as? String, "5m")

            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
            let firstContent = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
            XCTAssertNil(firstContent.first?["cache_control"])

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let controls = GenerationControls(
            contextCache: ContextCacheControls(
                mode: .implicit,
                strategy: .systemOnly,
                ttl: .minutes5
            )
        )

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .system, content: [.text("You are helpful.")]),
                Message(role: .user, content: [.text("hi")])
            ],
            modelID: "claude-sonnet-4-6",
            controls: controls,
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicStreamingUsageParsingIncludesInputOutputAndCacheRead() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testAnthropicStreamingSkipsMalformedEventsInsteadOfFailing() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
            data: {"type":"message_start","message":{}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"ok"}}

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

        var sawMessageEnd = false
        for try await event in stream {
            if case .messageEnd = event {
                sawMessageEnd = true
            }
        }

        XCTAssertTrue(sawMessageEnd)
    }

    func testAnthropicStreamingEmitsServerToolUseAsSearchActivity() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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

    func testAnthropicStreamingReassemblesFragmentedServerToolInputJSONDelta() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
            data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"url\\":\\"https://example.com/swift\\","}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\\"result_count\\":3}"}}

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

        let completed = try XCTUnwrap(searchEvents.last(where: { $0.status == .completed }))
        XCTAssertEqual(completed.id, "srv_1")
        XCTAssertEqual(completed.arguments["query"]?.value as? String, "swift structured concurrency")
        XCTAssertEqual(completed.arguments["url"]?.value as? String, "https://example.com/swift")
        XCTAssertEqual(completed.arguments["result_count"]?.value as? Int, 3)
    }

    func testAnthropicStreamingEmitsWebSearchToolResultURLs() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        XCTAssertEqual(AnthropicModelLimits.maxOutputTokens(for: "claude-opus-4-7"), 128000)
        XCTAssertEqual(AnthropicModelLimits.maxOutputTokens(for: "claude-opus-4-6"), 128000)
        XCTAssertEqual(AnthropicModelLimits.maxOutputTokens(for: "claude-sonnet-4-6"), 64000)
        XCTAssertEqual(AnthropicModelLimits.maxOutputTokens(for: "claude-opus-4-5-20251101"), 64000)
        XCTAssertEqual(AnthropicModelLimits.maxOutputTokens(for: "claude-sonnet-4-5-20250929"), 64000)
        XCTAssertEqual(AnthropicModelLimits.maxOutputTokens(for: "claude-haiku-4-5-20251001"), 64000)
        XCTAssertNil(AnthropicModelLimits.maxOutputTokens(for: "beta-claude-opus-4-6-variant"))
        XCTAssertNil(AnthropicModelLimits.maxOutputTokens(for: "claude-3-5-sonnet-20241022"))
    }

    func testAnthropicThinkingCapabilitiesSplit46From45Series() {
        XCTAssertTrue(AnthropicModelLimits.supportsAdaptiveThinking(for: "claude-opus-4-7"))
        XCTAssertTrue(AnthropicModelLimits.supportsEffort(for: "claude-opus-4-7"))
        XCTAssertTrue(AnthropicModelLimits.supportsXHighEffort(for: "claude-opus-4-7"))
        XCTAssertTrue(AnthropicModelLimits.supportsMaxEffort(for: "claude-opus-4-7"))
        XCTAssertFalse(AnthropicModelLimits.supportsSamplingParameters(for: "claude-opus-4-7"))
        XCTAssertTrue(AnthropicModelLimits.requiresExplicitThinkingDisplay(for: "claude-opus-4-7"))

        XCTAssertTrue(AnthropicModelLimits.supportsAdaptiveThinking(for: "claude-opus-4-6"))
        XCTAssertTrue(AnthropicModelLimits.supportsEffort(for: "claude-opus-4-6"))
        XCTAssertFalse(AnthropicModelLimits.supportsXHighEffort(for: "claude-opus-4-6"))
        XCTAssertTrue(AnthropicModelLimits.supportsMaxEffort(for: "claude-opus-4-6"))

        XCTAssertTrue(AnthropicModelLimits.supportsAdaptiveThinking(for: "claude-sonnet-4-6"))
        XCTAssertTrue(AnthropicModelLimits.supportsEffort(for: "claude-sonnet-4-6"))
        XCTAssertFalse(AnthropicModelLimits.supportsMaxEffort(for: "claude-sonnet-4-6"))

        XCTAssertFalse(AnthropicModelLimits.supportsAdaptiveThinking(for: "claude-opus-4-5-20251101"))
        XCTAssertTrue(AnthropicModelLimits.supportsEffort(for: "claude-opus-4-5-20251101"))
        XCTAssertFalse(AnthropicModelLimits.supportsMaxEffort(for: "claude-opus-4-5-20251101"))

        XCTAssertFalse(AnthropicModelLimits.supportsAdaptiveThinking(for: "claude-opus-4-1-20250805"))
        XCTAssertTrue(AnthropicModelLimits.supportsEffort(for: "claude-opus-4-1-20250805"))
        XCTAssertFalse(AnthropicModelLimits.supportsMaxEffort(for: "claude-opus-4-1-20250805"))

        // Sonnet 4.5 and Haiku 4.5 do NOT support effort
        XCTAssertFalse(AnthropicModelLimits.supportsEffort(for: "claude-sonnet-4-5-20250929"))
        XCTAssertFalse(AnthropicModelLimits.supportsEffort(for: "claude-haiku-4-5-20251001"))
    }

    // MARK: - Thinking Block Filtering

    func testAnthropicDropsThinkingBlocksWithNilSignature() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])

            let assistantMsg = try XCTUnwrap(messages.first { $0["role"] as? String == "assistant" })
            let content = try XCTUnwrap(assistantMsg["content"] as? [[String: Any]])

            // Thinking block with nil signature should be dropped
            let thinkingBlocks = content.filter { $0["type"] as? String == "thinking" }
            XCTAssertTrue(thinkingBlocks.isEmpty, "Thinking blocks without signatures should be dropped")

            // Text block should still be present
            let textBlocks = content.filter { $0["type"] as? String == "text" }
            XCTAssertEqual(textBlocks.count, 1)

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        // Simulate OpenAI-originated thinking (no signature)
        let messages: [Message] = [
            Message(role: .user, content: [.text("hi")]),
            Message(role: .assistant, content: [
                .thinking(ThinkingBlock(text: "OpenAI reasoning", signature: nil)),
                .text("visible response")
            ]),
            Message(role: .user, content: [.text("follow up")])
        ]

        let stream = try await adapter.sendMessage(
            messages: messages,
            modelID: "claude-opus-4-6",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true)),
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicDropsThinkingBlocksWithEmptySignature() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])

            let assistantMsg = try XCTUnwrap(messages.first { $0["role"] as? String == "assistant" })
            let content = try XCTUnwrap(assistantMsg["content"] as? [[String: Any]])

            let thinkingBlocks = content.filter { $0["type"] as? String == "thinking" }
            XCTAssertTrue(thinkingBlocks.isEmpty, "Thinking blocks with empty signatures should be dropped")

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let messages: [Message] = [
            Message(role: .user, content: [.text("hi")]),
            Message(role: .assistant, content: [
                .thinking(ThinkingBlock(text: "some reasoning", signature: "")),
                .text("visible")
            ]),
            Message(role: .user, content: [.text("follow up")])
        ]

        let stream = try await adapter.sendMessage(
            messages: messages,
            modelID: "claude-opus-4-6",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true)),
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicPreservesThinkingBlocksWithValidSignature() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])

            let assistantMsg = try XCTUnwrap(messages.first { $0["role"] as? String == "assistant" })
            let content = try XCTUnwrap(assistantMsg["content"] as? [[String: Any]])

            let thinkingBlocks = content.filter { $0["type"] as? String == "thinking" }
            XCTAssertEqual(thinkingBlocks.count, 1, "Thinking blocks with valid signatures should be preserved")
            XCTAssertEqual(thinkingBlocks.first?["thinking"] as? String, "Anthropic reasoning")
            XCTAssertEqual(thinkingBlocks.first?["signature"] as? String, "valid-anthropic-sig")

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let messages: [Message] = [
            Message(role: .user, content: [.text("hi")]),
            Message(role: .assistant, content: [
                .thinking(ThinkingBlock(text: "Anthropic reasoning", signature: "valid-anthropic-sig", provider: "anthropic")),
                .text("visible")
            ]),
            Message(role: .user, content: [.text("follow up")])
        ]

        let stream = try await adapter.sendMessage(
            messages: messages,
            modelID: "claude-opus-4-6",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true)),
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicDropsEmptyRedactedThinkingBlocks() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])

            let assistantMsg = try XCTUnwrap(messages.first { $0["role"] as? String == "assistant" })
            let content = try XCTUnwrap(assistantMsg["content"] as? [[String: Any]])

            let redactedBlocks = content.filter { $0["type"] as? String == "redacted_thinking" }
            XCTAssertTrue(redactedBlocks.isEmpty, "Redacted thinking blocks with empty data should be dropped")

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let messages: [Message] = [
            Message(role: .user, content: [.text("hi")]),
            Message(role: .assistant, content: [
                .redactedThinking(RedactedThinkingBlock(data: "")),
                .text("visible")
            ]),
            Message(role: .user, content: [.text("follow up")])
        ]

        let stream = try await adapter.sendMessage(
            messages: messages,
            modelID: "claude-opus-4-6",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true)),
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicPreservesValidRedactedThinkingBlocks() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])

            let assistantMsg = try XCTUnwrap(messages.first { $0["role"] as? String == "assistant" })
            let content = try XCTUnwrap(assistantMsg["content"] as? [[String: Any]])

            let redactedBlocks = content.filter { $0["type"] as? String == "redacted_thinking" }
            XCTAssertEqual(redactedBlocks.count, 1, "Valid Anthropic redacted thinking blocks should be preserved")
            XCTAssertEqual(redactedBlocks.first?["data"] as? String, "opaque-anthropic-redacted")

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let messages: [Message] = [
            Message(role: .user, content: [.text("hi")]),
            Message(role: .assistant, content: [
                .redactedThinking(RedactedThinkingBlock(
                    data: "opaque-anthropic-redacted",
                    provider: ProviderType.anthropic.rawValue
                )),
                .text("visible")
            ]),
            Message(role: .user, content: [.text("follow up")])
        ]

        let stream = try await adapter.sendMessage(
            messages: messages,
            modelID: "claude-opus-4-6",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true)),
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicMixedProviderThinkingBlocksOnlyKeepsAnthropicOnes() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])

            // First assistant message (from OpenAI — no signature) should have thinking dropped
            let firstAssistant = try XCTUnwrap(messages.first { $0["role"] as? String == "assistant" })
            let firstContent = try XCTUnwrap(firstAssistant["content"] as? [[String: Any]])
            let firstThinking = firstContent.filter { $0["type"] as? String == "thinking" }
            XCTAssertTrue(firstThinking.isEmpty, "OpenAI thinking should be dropped")

            // Second assistant message (from Anthropic — has signature) should keep thinking
            let assistants = messages.filter { $0["role"] as? String == "assistant" }
            let secondAssistant = try XCTUnwrap(assistants.last)
            let secondContent = try XCTUnwrap(secondAssistant["content"] as? [[String: Any]])
            let secondThinking = secondContent.filter { $0["type"] as? String == "thinking" }
            XCTAssertEqual(secondThinking.count, 1, "Anthropic thinking should be preserved")

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let messages: [Message] = [
            Message(role: .user, content: [.text("hi")]),
            // First response was from OpenAI (no signature)
            Message(role: .assistant, content: [
                .thinking(ThinkingBlock(text: "OpenAI reasoning", signature: nil, provider: "openai")),
                .text("first response")
            ]),
            Message(role: .user, content: [.text("switching to anthropic")]),
            // Second response was from Anthropic (has signature)
            Message(role: .assistant, content: [
                .thinking(ThinkingBlock(text: "Anthropic reasoning", signature: "real-sig", provider: "anthropic")),
                .text("second response")
            ]),
            Message(role: .user, content: [.text("follow up")])
        ]

        let stream = try await adapter.sendMessage(
            messages: messages,
            modelID: "claude-opus-4-6",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true)),
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicDropsGeminiThinkingBlocksWithForeignSignature() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])

            for msg in messages where msg["role"] as? String == "assistant" {
                let content = msg["content"] as? [[String: Any]] ?? []
                let thinkingBlocks = content.filter { $0["type"] as? String == "thinking" }
                let redactedBlocks = content.filter { $0["type"] as? String == "redacted_thinking" }
                XCTAssertTrue(thinkingBlocks.isEmpty, "Gemini thinking with foreign signature should be dropped")
                XCTAssertTrue(redactedBlocks.isEmpty, "Gemini redacted thinking should be dropped")
            }

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        // Gemini produces thoughtSignature which gets stored as signature
        let messages: [Message] = [
            Message(role: .user, content: [.text("hi")]),
            Message(role: .assistant, content: [
                .thinking(ThinkingBlock(text: "Gemini reasoning", signature: "gemini-thought-sig-abc123", provider: "gemini")),
                .redactedThinking(RedactedThinkingBlock(data: "gemini-opaque-data", provider: "gemini")),
                .text("visible")
            ]),
            Message(role: .user, content: [.text("follow up")])
        ]

        let stream = try await adapter.sendMessage(
            messages: messages,
            modelID: "claude-opus-4-6",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true)),
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicDropsVertexAIThinkingBlocksWithForeignSignature() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])

            for msg in messages where msg["role"] as? String == "assistant" {
                let content = msg["content"] as? [[String: Any]] ?? []
                let thinkingBlocks = content.filter { $0["type"] as? String == "thinking" }
                XCTAssertTrue(thinkingBlocks.isEmpty, "Vertex AI thinking with foreign signature should be dropped")
            }

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let messages: [Message] = [
            Message(role: .user, content: [.text("hi")]),
            Message(role: .assistant, content: [
                .thinking(ThinkingBlock(text: "Vertex reasoning", signature: "vertex-thought-sig-xyz", provider: "vertexai")),
                .text("visible")
            ]),
            Message(role: .user, content: [.text("follow up")])
        ]

        let stream = try await adapter.sendMessage(
            messages: messages,
            modelID: "claude-opus-4-6",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true)),
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicDropsThinkingBlocksWithNilProvider() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])

            let assistantMsg = try XCTUnwrap(messages.first { $0["role"] as? String == "assistant" })
            let content = try XCTUnwrap(assistantMsg["content"] as? [[String: Any]])

            let thinkingBlocks = content.filter { $0["type"] as? String == "thinking" }
            XCTAssertTrue(thinkingBlocks.isEmpty, "Pre-tagging thinking blocks (provider=nil) should be dropped")

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        // Simulates old persisted data without provider tag
        let messages: [Message] = [
            Message(role: .user, content: [.text("hi")]),
            Message(role: .assistant, content: [
                .thinking(ThinkingBlock(text: "old thinking", signature: "some-sig", provider: nil)),
                .text("visible")
            ]),
            Message(role: .user, content: [.text("follow up")])
        ]

        let stream = try await adapter.sendMessage(
            messages: messages,
            modelID: "claude-opus-4-6",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true)),
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testAnthropicPassesThroughCorruptedAnthropicSignature() async throws {
        // Anthropic signatures are opaque — we intentionally do NOT validate format client-side.
        // If a persisted Anthropic signature is truncated/corrupted, we pass it through and let
        // the API return a 400. This is the correct behavior: the user sees an error and can
        // retry (generating fresh thinking blocks). Adding a client-side format heuristic would
        // risk false positives when Anthropic changes their signature format.
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])

            let assistantMsg = try XCTUnwrap(messages.first { $0["role"] as? String == "assistant" })
            let content = try XCTUnwrap(assistantMsg["content"] as? [[String: Any]])

            // Corrupted signature IS sent through — Anthropic API will reject it
            let thinkingBlocks = content.filter { $0["type"] as? String == "thinking" }
            XCTAssertEqual(thinkingBlocks.count, 1, "Corrupted Anthropic signature should be passed through")
            XCTAssertEqual(thinkingBlocks.first?["signature"] as? String, "trunca")

            let response = Data("data: [DONE]\n\n".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let messages: [Message] = [
            Message(role: .user, content: [.text("hi")]),
            Message(role: .assistant, content: [
                .thinking(ThinkingBlock(text: "reasoning", signature: "trunca", provider: "anthropic")),
                .text("visible")
            ]),
            Message(role: .user, content: [.text("follow up")])
        ]

        let stream = try await adapter.sendMessage(
            messages: messages,
            modelID: "claude-opus-4-6",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true)),
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
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
