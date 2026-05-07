import XCTest
@testable import Jin

final class OpenAIResponsesRequestSupportTests: XCTestCase {
    func testApplyContextCacheControlsTrimsKeyAndSkipsMinTokens() {
        var body: [String: Any] = [:]

        OpenAIResponsesRequestSupport.applyContextCacheControls(
            to: &body,
            controls: GenerationControls(
                contextCache: ContextCacheControls(
                    mode: .implicit,
                    ttl: .hour1,
                    cacheKey: " stable-prefix ",
                    minTokensThreshold: 1024
                )
            )
        )

        XCTAssertEqual(body["prompt_cache_key"] as? String, "stable-prefix")
        XCTAssertEqual(body["prompt_cache_retention"] as? String, "1h")
        XCTAssertNil(body["prompt_cache_min_tokens"])
    }

    func testApplyContextCacheControlsSkipsWhenModeIsOff() {
        var body: [String: Any] = [:]

        OpenAIResponsesRequestSupport.applyContextCacheControls(
            to: &body,
            controls: GenerationControls(
                contextCache: ContextCacheControls(
                    mode: .off,
                    ttl: .hour1,
                    cacheKey: "stable-prefix"
                )
            )
        )

        XCTAssertTrue(body.isEmpty)
    }

    func testApplySamplingControlsOmitsSamplingWhenUnsupported() {
        var body: [String: Any] = [
            "temperature": 0.2,
            "top_p": 0.3
        ]

        OpenAIResponsesRequestSupport.applyProviderSpecificOverrides(
            to: &body,
            controls: GenerationControls(
                providerSpecific: [
                    "temperature": AnyCodable(0.7),
                    "top_p": AnyCodable(0.9),
                    "service_tier": AnyCodable("priority"),
                    "custom": AnyCodable("value")
                ]
            ),
            supportsSamplingParameters: false
        )

        XCTAssertEqual(body["temperature"] as? Double, 0.2)
        XCTAssertEqual(body["top_p"] as? Double, 0.3)
        XCTAssertNil(body["service_tier"])
        XCTAssertEqual(body["custom"] as? String, "value")
    }

    func testApplySamplingControlsIncludesTemperatureAndTopPWhenSupported() {
        var body: [String: Any] = [:]

        OpenAIResponsesRequestSupport.applySamplingControls(
            to: &body,
            controls: GenerationControls(temperature: 0.7, topP: 0.9),
            supportsSamplingParameters: true
        )

        XCTAssertEqual(body["temperature"] as? Double, 0.7)
        XCTAssertEqual(body["top_p"] as? Double, 0.9)
    }

    func testApplyReasoningConfigMapsEffortAndSummary() throws {
        var body: [String: Any] = [:]

        OpenAIResponsesRequestSupport.applyReasoningConfig(
            to: &body,
            controls: GenerationControls(
                reasoning: ReasoningControls(
                    enabled: true,
                    effort: .xhigh,
                    summary: .detailed
                )
            ),
            providerType: .openai,
            modelID: "gpt-5",
            reasoningEnabled: true,
            reasoningEffort: .xhigh
        )

        let reasoning = try XCTUnwrap(body["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["effort"] as? String, "high")
        XCTAssertEqual(reasoning["summary"] as? String, "detailed")
    }

    func testToolObjectsBuildsWebSearchCodeInterpreterAndFunctionTools() throws {
        let controls = GenerationControls(
            webSearch: WebSearchControls(enabled: true, contextSize: .high),
            codeExecution: CodeExecutionControls(
                enabled: true,
                openAI: OpenAICodeExecutionOptions(
                    container: CodeExecutionContainer(
                        type: "auto",
                        memoryLimit: "4g",
                        fileIDs: [" file_alpha ", "file_beta", "file_alpha"]
                    )
                )
            )
        )

        let tools = OpenAIResponsesRequestSupport.toolObjects(
            controls: controls,
            functionTools: [["type": "function", "name": "lookup"]],
            supportsWebSearch: true,
            codeExecutionEnabled: true
        )

        XCTAssertEqual(tools.count, 3)
        XCTAssertEqual(tools[0]["type"] as? String, "web_search")
        XCTAssertEqual(tools[0]["search_context_size"] as? String, "high")

        let codeInterpreter = try XCTUnwrap(tools[1]["container"] as? [String: Any])
        XCTAssertEqual(codeInterpreter["type"] as? String, "auto")
        XCTAssertEqual(codeInterpreter["memory_limit"] as? String, "4g")
        XCTAssertEqual(codeInterpreter["file_ids"] as? [String], ["file_alpha", "file_beta"])

        XCTAssertEqual(tools[2]["type"] as? String, "function")
        XCTAssertEqual(tools[2]["name"] as? String, "lookup")
    }

    func testCodeInterpreterToolUsesExistingContainerIDWhenConfigured() {
        let tool = OpenAIResponsesRequestSupport.codeInterpreterTool(
            from: CodeExecutionControls(
                enabled: true,
                openAI: OpenAICodeExecutionOptions(existingContainerID: " cntr_existing ")
            )
        )

        XCTAssertEqual(tool["type"] as? String, "code_interpreter")
        XCTAssertEqual(tool["container"] as? String, "cntr_existing")
    }

    func testApplyRequiredIncludeFieldsMergesAndDeduplicates() {
        var body: [String: Any] = [
            "include": [
                " web_search_call.action.sources ",
                "",
                "custom.include"
            ]
        ]

        OpenAIResponsesRequestSupport.applyRequiredIncludeFields(
            to: &body,
            webSearchEnabled: true,
            codeExecutionEnabled: true
        )

        XCTAssertEqual(
            body["include"] as? [String],
            [
                "web_search_call.action.sources",
                "custom.include",
                "code_interpreter_call.outputs"
            ]
        )
    }
}
