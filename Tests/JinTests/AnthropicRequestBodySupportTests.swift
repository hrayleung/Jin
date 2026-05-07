import XCTest
@testable import Jin

final class AnthropicRequestBodySupportTests: XCTestCase {
    func testApplySystemPromptAddsTextBlockWithCacheControl() throws {
        var body: [String: Any] = [:]

        AnthropicRequestBodySupport.applySystemPrompt(
            to: &body,
            from: [
                Message(role: .system, content: [.text("System rules")]),
                Message(role: .user, content: [.text("Hi")])
            ],
            cacheControl: ["type": "ephemeral", "ttl": "1h"]
        )

        let system = try XCTUnwrap(body["system"] as? [[String: Any]])
        XCTAssertEqual(system.count, 1)
        XCTAssertEqual(system[0]["type"] as? String, "text")
        XCTAssertEqual(system[0]["text"] as? String, "System rules")

        let cacheControl = try XCTUnwrap(system[0]["cache_control"] as? [String: Any])
        XCTAssertEqual(cacheControl["type"] as? String, "ephemeral")
        XCTAssertEqual(cacheControl["ttl"] as? String, "1h")
    }

    func testApplyThinkingConfigBuildsAdaptiveThinkingAndEffort() throws {
        var body: [String: Any] = [:]

        AnthropicRequestBodySupport.applyThinkingConfig(
            to: &body,
            controls: GenerationControls(
                reasoning: ReasoningControls(
                    enabled: true,
                    effort: .xhigh,
                    budgetTokens: 8192,
                    anthropicThinkingDisplay: .omitted
                )
            ),
            providerType: .anthropic,
            modelID: "claude-opus-4-7"
        )

        let thinking = try XCTUnwrap(body["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "adaptive")
        XCTAssertEqual(thinking["display"] as? String, "omitted")
        XCTAssertNil(thinking["budget_tokens"])

        let outputConfig = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(outputConfig["effort"] as? String, "xhigh")
    }

    func testApplyThinkingConfigForMimoAddsSamplingAndSimpleThinkingState() throws {
        var body: [String: Any] = [:]

        AnthropicRequestBodySupport.applyThinkingConfig(
            to: &body,
            controls: GenerationControls(
                temperature: 0.4,
                topP: 0.8,
                reasoning: ReasoningControls(enabled: false)
            ),
            providerType: .mimoTokenPlanAnthropic,
            modelID: "mimo-v2.5-pro"
        )

        let thinking = try XCTUnwrap(body["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "disabled")
        XCTAssertEqual(body["temperature"] as? Double, 0.4)
        XCTAssertEqual(body["top_p"] as? Double, 0.8)
    }

    func testApplyProviderSpecificOverridesFiltersSamplingWhenUnsupportedAndMergesOutputConfig() throws {
        var body: [String: Any] = [
            "output_config": ["effort": "xhigh"]
        ]

        AnthropicRequestBodySupport.applyProviderSpecificOverrides(
            to: &body,
            controls: GenerationControls(
                reasoning: ReasoningControls(enabled: true),
                providerSpecific: [
                    "anthropic_beta": AnyCodable("files-api-2025-04-14"),
                    "temperature": AnyCodable(0.2),
                    "top_p": AnyCodable(0.7),
                    "top_k": AnyCodable(5),
                    "output_format": AnyCodable(["type": "json_schema"]),
                    "output_config": AnyCodable(["reasoning_budget": 1024]),
                    "custom": AnyCodable("value")
                ]
            ),
            modelID: "claude-opus-4-7",
            supportsDynamicFiltering: true
        )

        XCTAssertNil(body["anthropic_beta"])
        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["top_p"])
        XCTAssertNil(body["top_k"])
        XCTAssertEqual(body["custom"] as? String, "value")

        let outputConfig = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(outputConfig["effort"] as? String, "xhigh")
        XCTAssertEqual(outputConfig["reasoning_budget"] as? Int, 1024)

        let format = try XCTUnwrap(outputConfig["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
    }

    func testApplyToolSpecsIncludesBuiltInsAndCustomTools() throws {
        var body: [String: Any] = [:]

        AnthropicRequestBodySupport.applyToolSpecs(
            to: &body,
            controls: GenerationControls(
                webSearch: WebSearchControls(
                    enabled: true,
                    maxUses: 2,
                    dynamicFiltering: true
                )
            ),
            customTools: [["name": "lookup", "input_schema": ["type": "object"]]],
            supportsWebSearch: true,
            supportsDynamicFiltering: true,
            codeExecutionEnabled: true
        )

        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 3)
        XCTAssertEqual(tools[0]["type"] as? String, "web_search_20260209")
        XCTAssertEqual(tools[0]["max_uses"] as? Int, 2)
        XCTAssertEqual(tools[1]["type"] as? String, "code_execution_20250825")
        XCTAssertEqual(tools[2]["name"] as? String, "lookup")
    }

    func testCacheControlHelpersRespectPrefixWindowStrategyAndOffMode() throws {
        let contextCache = ContextCacheControls(mode: .implicit, strategy: .prefixWindow, ttl: .hour1)

        XCTAssertNil(
            AnthropicRequestBodySupport.blockCacheControl(
                from: contextCache,
                strategy: .prefixWindow
            )
        )

        let topLevel = try XCTUnwrap(
            AnthropicRequestBodySupport.topLevelCacheControl(
                from: contextCache,
                strategy: .prefixWindow
            )
        )
        XCTAssertEqual(topLevel["type"] as? String, "ephemeral")
        XCTAssertEqual(topLevel["ttl"] as? String, "1h")

        XCTAssertNil(
            AnthropicRequestBodySupport.topLevelCacheControl(
                from: ContextCacheControls(mode: .off, strategy: .prefixWindow, ttl: .hour1),
                strategy: .prefixWindow
            )
        )
    }
}
