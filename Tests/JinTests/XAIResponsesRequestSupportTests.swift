import XCTest
@testable import Jin

final class XAIResponsesRequestSupportTests: XCTestCase {
    func testContextCacheControlsAndHeadersNormalizeInputs() {
        var body: [String: Any] = [:]
        let controls = GenerationControls(
            contextCache: ContextCacheControls(
                mode: .implicit,
                ttl: .hour1,
                cacheKey: " stable-prefix ",
                conversationID: " conv-123 ",
                minTokensThreshold: 1024
            )
        )

        XAIResponsesRequestSupport.applyContextCacheControls(to: &body, controls: controls)

        XCTAssertEqual(body["prompt_cache_key"] as? String, "stable-prefix")
        XCTAssertEqual(body["prompt_cache_retention"] as? String, "1h")
        XCTAssertEqual(body["prompt_cache_min_tokens"] as? Int, 1024)
        XCTAssertEqual(
            XAIResponsesRequestSupport.additionalHeaders(controls: controls),
            ["x-grok-conv-id": "conv-123"]
        )
    }

    func testContextCacheOffOmitsCacheFieldsAndHeaders() {
        var body: [String: Any] = [:]
        let controls = GenerationControls(
            contextCache: ContextCacheControls(
                mode: .off,
                ttl: .hour1,
                cacheKey: "stable-prefix",
                conversationID: "conv-123",
                minTokensThreshold: 1024
            )
        )

        XAIResponsesRequestSupport.applyContextCacheControls(to: &body, controls: controls)

        XCTAssertTrue(body.isEmpty)
        XCTAssertTrue(XAIResponsesRequestSupport.additionalHeaders(controls: controls).isEmpty)
    }

    func testMultiAgentBodyUsesReasoningObjectAndOmitsUnsupportedFunctionToolsAndMaxTokens() throws {
        let body = XAIResponsesRequestSupport.responsesBody(
            modelID: "grok-4.20-multi-agent-0309",
            input: [["role": "user", "content": []]],
            streaming: false,
            controls: GenerationControls(
                maxTokens: 2048,
                reasoning: ReasoningControls(enabled: true, effort: .xhigh),
                webSearch: WebSearchControls(enabled: true, sources: [.web, .x]),
                codeExecution: CodeExecutionControls(enabled: true),
                providerSpecific: [
                    "max_output_tokens": AnyCodable(4096),
                    "max_tokens": AnyCodable(4096)
                ]
            ),
            functionTools: [["type": "function", "name": "lookup_status"]],
            supportsWebSearch: true,
            supportsClientFunctionTools: false
        )

        XCTAssertEqual(body["model"] as? String, "grok-4.20-multi-agent-0309")
        XCTAssertNil(body["reasoning_effort"])
        XCTAssertNil(body["max_output_tokens"])
        XCTAssertNil(body["max_tokens"])

        let reasoning = try XCTUnwrap(body["reasoning"] as? [String: Any])
        // high/xhigh both select the 16-agent band; xhigh is preserved on the wire.
        XCTAssertEqual(reasoning["effort"] as? String, "xhigh")

        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertTrue(tools.contains { ($0["type"] as? String) == "web_search" })
        XCTAssertTrue(tools.contains { ($0["type"] as? String) == "x_search" })
        XCTAssertTrue(tools.contains { ($0["type"] as? String) == "code_interpreter" })
        XCTAssertFalse(tools.contains { ($0["type"] as? String) == "function" })
        XCTAssertEqual(body["include"] as? [String], ["code_interpreter_call.outputs"])
    }

    func testMultiAgentReasoningEffortMapsAllDocumentedValues() {
        let cases: [(ReasoningEffort, String)] = [
            (.low, "low"),
            (.medium, "medium"),
            (.high, "high"),
            (.xhigh, "xhigh"),
            (.max, "xhigh"),
            (.minimal, "low"),
            (.none, "low"),
        ]
        for (effort, expected) in cases {
            XCTAssertEqual(
                XAIResponsesRequestSupport.mapMultiAgentReasoningEffort(effort),
                expected,
                "effort \(effort)"
            )
        }
    }

    func testWebAndXSearchToolParamsAreEncoded() throws {
        let body = XAIResponsesRequestSupport.responsesBody(
            modelID: "grok-4.5",
            input: [["role": "user", "content": []]],
            streaming: false,
            controls: GenerationControls(
                reasoning: ReasoningControls(enabled: true, effort: .low),
                webSearch: WebSearchControls(
                    enabled: true,
                    sources: [.web, .x],
                    allowedDomains: ["docs.x.ai", "example.com"],
                    enableImageUnderstanding: true,
                    enableImageSearch: true,
                    enableVideoUnderstanding: true,
                    allowedXHandles: ["@elonmusk", "xai"],
                    xSearchFromDate: "2025-10-01",
                    xSearchToDate: "2025-10-10"
                )
            ),
            functionTools: [],
            supportsWebSearch: true,
            supportsClientFunctionTools: true
        )

        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        let web = try XCTUnwrap(tools.first { ($0["type"] as? String) == "web_search" })
        let filters = try XCTUnwrap(web["filters"] as? [String: Any])
        XCTAssertEqual(filters["allowed_domains"] as? [String], ["docs.x.ai", "example.com"])
        XCTAssertEqual(web["enable_image_understanding"] as? Bool, true)
        XCTAssertEqual(web["enable_image_search"] as? Bool, true)

        let xSearch = try XCTUnwrap(tools.first { ($0["type"] as? String) == "x_search" })
        XCTAssertEqual(xSearch["allowed_x_handles"] as? [String], ["elonmusk", "xai"])
        XCTAssertEqual(xSearch["from_date"] as? String, "2025-10-01")
        XCTAssertEqual(xSearch["to_date"] as? String, "2025-10-10")
        XCTAssertEqual(xSearch["enable_image_understanding"] as? Bool, true)
        XCTAssertEqual(xSearch["enable_video_understanding"] as? Bool, true)
    }

    func testGrok43SendsNoneEffortWhenSelected() throws {
        let body = XAIResponsesRequestSupport.responsesBody(
            modelID: "grok-4.3",
            input: [["role": "user", "content": []]],
            streaming: false,
            controls: GenerationControls(
                reasoning: ReasoningControls(enabled: true, effort: .none)
            ),
            functionTools: [],
            supportsWebSearch: false,
            supportsClientFunctionTools: true
        )

        let reasoning = try XCTUnwrap(body["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["effort"] as? String, "none")
    }

    func testGrok45EmitsDefaultHighWhenReasoningControlsMissing() throws {
        let body = XAIResponsesRequestSupport.responsesBody(
            modelID: "grok-4.5",
            input: [["role": "user", "content": []]],
            streaming: false,
            controls: GenerationControls(),
            functionTools: [],
            supportsWebSearch: false,
            supportsClientFunctionTools: true
        )

        let reasoning = try XCTUnwrap(body["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["effort"] as? String, "high")
    }

    func testSupportedExactModelIncludesMaxTokensAndFunctionTools() throws {
        let body = XAIResponsesRequestSupport.responsesBody(
            modelID: "grok-4-1",
            input: [["role": "user", "content": []]],
            streaming: true,
            controls: GenerationControls(
                temperature: 0.7,
                maxTokens: 2048,
                topP: 0.9,
                providerSpecific: [
                    "max_output_tokens": AnyCodable(4096),
                    "max_tokens": AnyCodable(8192),
                    "custom": AnyCodable("value")
                ]
            ),
            functionTools: [["type": "function", "name": "lookup_status"]],
            supportsWebSearch: false,
            supportsClientFunctionTools: true
        )

        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["temperature"] as? Double, 0.7)
        XCTAssertEqual(body["top_p"] as? Double, 0.9)
        XCTAssertEqual(body["max_output_tokens"] as? Int, 4096)
        XCTAssertEqual(body["max_tokens"] as? Int, 8192)
        XCTAssertEqual(body["custom"] as? String, "value")

        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?["type"] as? String, "function")
        XCTAssertEqual(tools.first?["name"] as? String, "lookup_status")
    }

    func testUnknownNearMatchDoesNotInheritExactModelSupport() {
        let body = XAIResponsesRequestSupport.responsesBody(
            modelID: "grok-4.20-multi-agent-0310",
            input: [["role": "user", "content": []]],
            streaming: false,
            controls: GenerationControls(
                maxTokens: 2048,
                providerSpecific: [
                    "max_output_tokens": AnyCodable(4096),
                    "max_tokens": AnyCodable(8192)
                ]
            ),
            functionTools: [["type": "function", "name": "lookup_status"]],
            supportsWebSearch: false,
            supportsClientFunctionTools: false
        )

        XCTAssertFalse(XAIResponsesRequestSupport.supportsMaxOutputTokens(modelID: "grok-4.20-multi-agent-0310"))
        XCTAssertFalse(XAIResponsesRequestSupport.supportsClientFunctionTools(modelID: "grok-4.20-multi-agent-0310"))
        XCTAssertNil(body["max_output_tokens"])
        XCTAssertNil(body["max_tokens"])
        XCTAssertNil(body["tools"])
    }

    func testReasoningEffortModelUsesLegacyReasoningEffortField() {
        let body = XAIResponsesRequestSupport.responsesBody(
            modelID: "grok-3-mini",
            input: [["role": "user", "content": []]],
            streaming: false,
            controls: GenerationControls(
                reasoning: ReasoningControls(enabled: true, effort: .max)
            ),
            functionTools: [],
            supportsWebSearch: false,
            supportsClientFunctionTools: false
        )

        XCTAssertEqual(body["reasoning_effort"] as? String, "high")
        XCTAssertNil(body["reasoning"])
    }

    func testProviderSpecificIncludeStillOverridesCodeInterpreterInclude() {
        let body = XAIResponsesRequestSupport.responsesBody(
            modelID: "grok-4-1",
            input: [["role": "user", "content": []]],
            streaming: false,
            controls: GenerationControls(
                codeExecution: CodeExecutionControls(enabled: true),
                providerSpecific: [
                    "include": AnyCodable(["custom.include"])
                ]
            ),
            functionTools: [],
            supportsWebSearch: false,
            supportsClientFunctionTools: true
        )

        XCTAssertEqual(body["include"] as? [String], ["custom.include"])
    }

    func testToolChoiceRequiredWhenXIsSoleTool() {
        let body = XAIResponsesRequestSupport.responsesBody(
            modelID: "grok-4.3",
            input: [["role": "user", "content": []]],
            streaming: false,
            controls: GenerationControls(
                webSearch: WebSearchControls(enabled: true, sources: [.x])
            ),
            functionTools: [],
            supportsWebSearch: true,
            supportsClientFunctionTools: true
        )

        let tools = body["tools"] as? [[String: Any]] ?? []
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?["type"] as? String, "x_search")
        XCTAssertEqual(body["tool_choice"] as? String, "required")
    }

    func testToolChoiceOmittedWhenBothWebAndXSourcesEnabled() {
        let body = XAIResponsesRequestSupport.responsesBody(
            modelID: "grok-4.3",
            input: [["role": "user", "content": []]],
            streaming: false,
            controls: GenerationControls(
                webSearch: WebSearchControls(enabled: true, sources: [.web, .x])
            ),
            functionTools: [],
            supportsWebSearch: true,
            supportsClientFunctionTools: true
        )

        XCTAssertNil(body["tool_choice"])
    }

    func testToolChoiceOmittedWhenXOnlyButFunctionToolsPresent() {
        let body = XAIResponsesRequestSupport.responsesBody(
            modelID: "grok-4.3",
            input: [["role": "user", "content": []]],
            streaming: false,
            controls: GenerationControls(
                webSearch: WebSearchControls(enabled: true, sources: [.x])
            ),
            functionTools: [["type": "function", "name": "lookup_status"]],
            supportsWebSearch: true,
            supportsClientFunctionTools: true
        )

        let tools = body["tools"] as? [[String: Any]] ?? []
        XCTAssertEqual(tools.count, 2)
        XCTAssertNil(body["tool_choice"])
    }

    func testToolChoiceOmittedWhenXOnlyButCodeExecutionEnabled() {
        let body = XAIResponsesRequestSupport.responsesBody(
            modelID: "grok-4.3",
            input: [["role": "user", "content": []]],
            streaming: false,
            controls: GenerationControls(
                webSearch: WebSearchControls(enabled: true, sources: [.x]),
                codeExecution: CodeExecutionControls(enabled: true)
            ),
            functionTools: [],
            supportsWebSearch: true,
            supportsClientFunctionTools: true
        )

        XCTAssertNil(body["tool_choice"])
    }

    func testToolChoiceOmittedWhenWebOnly() {
        let body = XAIResponsesRequestSupport.responsesBody(
            modelID: "grok-4.3",
            input: [["role": "user", "content": []]],
            streaming: false,
            controls: GenerationControls(
                webSearch: WebSearchControls(enabled: true, sources: [.web])
            ),
            functionTools: [],
            supportsWebSearch: true,
            supportsClientFunctionTools: true
        )

        XCTAssertNil(body["tool_choice"])
    }

    // MARK: - Grok 4.5

    func testGrok45SendsDocumentedReasoningObjectWithToolsAndMaxTokens() throws {
        let body = XAIResponsesRequestSupport.responsesBody(
            modelID: "grok-4.5",
            input: [["role": "user", "content": []]],
            streaming: true,
            controls: GenerationControls(
                maxTokens: 2_048,
                reasoning: ReasoningControls(enabled: true, effort: .medium)
            ),
            functionTools: [["type": "function", "name": "lookup_status"]],
            supportsWebSearch: false,
            supportsClientFunctionTools: true
        )

        XCTAssertTrue(XAIResponsesRequestSupport.supportsStandardReasoningEffort(modelID: "grok-4.5"))
        XCTAssertTrue(XAIResponsesRequestSupport.supportsClientFunctionTools(modelID: "grok-4.5"))
        XCTAssertTrue(XAIResponsesRequestSupport.supportsMaxOutputTokens(modelID: "grok-4.5"))

        let reasoning = try XCTUnwrap(body["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["effort"] as? String, "medium")
        XCTAssertNil(body["reasoning_effort"])
        XCTAssertEqual(body["max_output_tokens"] as? Int, 2_048)

        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?["name"] as? String, "lookup_status")
    }

    func testGrok45ClampsEffortsToDocumentedLowMediumHighBand() throws {
        // grok-4.5 accepts exactly low/medium/high (docs.x.ai reasoning guide).
        let clampCases: [(ReasoningEffort, String)] = [
            (.minimal, "low"),
            (.low, "low"),
            (.medium, "medium"),
            (.high, "high"),
            (.xhigh, "high"),
            (.max, "high"),
        ]

        for (effort, expected) in clampCases {
            let body = XAIResponsesRequestSupport.responsesBody(
                modelID: "grok-4.5",
                input: [["role": "user", "content": []]],
                streaming: false,
                controls: GenerationControls(
                    reasoning: ReasoningControls(enabled: true, effort: effort)
                ),
                functionTools: [],
                supportsWebSearch: false,
                supportsClientFunctionTools: false
            )
            let reasoning = try XCTUnwrap(body["reasoning"] as? [String: Any], "effort \(effort)")
            XCTAssertEqual(reasoning["effort"] as? String, expected, "effort \(effort)")
        }
    }

    func testGrok45NearMissDoesNotInheritExactModelSupport() {
        XCTAssertFalse(XAIResponsesRequestSupport.supportsStandardReasoningEffort(modelID: "grok-4.5-custom"))
        XCTAssertFalse(XAIResponsesRequestSupport.supportsClientFunctionTools(modelID: "grok-4.5-custom"))
        XCTAssertFalse(XAIResponsesRequestSupport.supportsMaxOutputTokens(modelID: "grok-4.5-custom"))
    }
}
