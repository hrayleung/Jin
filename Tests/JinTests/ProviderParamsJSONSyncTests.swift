import XCTest
@testable import Jin

final class ProviderParamsJSONSyncTests: XCTestCase {
    func testOpenAIDraftAndApplySyncsReasoningAndWebSearch() {
        var controls = GenerationControls()
        controls.temperature = 0.7
        controls.topP = 0.9
        controls.maxTokens = 2048
        controls.reasoning = ReasoningControls(enabled: true, effort: .high, budgetTokens: nil, summary: .detailed)
        controls.webSearch = WebSearchControls(enabled: true, contextSize: .high, sources: nil)
        controls.providerSpecific = [
            "custom_flag": AnyCodable(true)
        ]

        let draft = ProviderParamsJSONSync.makeDraft(providerType: .openai, modelID: "gpt-5.2", controls: controls)

        XCTAssertEqual(draft["temperature"]?.value as? Double, 0.7)
        XCTAssertEqual(draft["top_p"]?.value as? Double, 0.9)
        XCTAssertEqual(draft["max_output_tokens"]?.value as? Int, 2048)
        XCTAssertEqual(draft["custom_flag"]?.value as? Bool, true)

        let reasoning = draft["reasoning"]?.value as? [String: Any]
        XCTAssertEqual(reasoning?["effort"] as? String, "high")
        XCTAssertEqual(reasoning?["summary"] as? String, "detailed")

        let tools = draft["tools"]?.value as? [Any]
        XCTAssertEqual(tools?.count, 1)
        let tool0 = tools?.first as? [String: Any]
        XCTAssertEqual(tool0?["type"] as? String, "web_search")
        XCTAssertEqual(tool0?["search_context_size"] as? String, "high")

        var appliedControls = GenerationControls()
        let remainder = ProviderParamsJSONSync.applyDraft(
            providerType: .openai,
            modelID: "gpt-5.2",
            draft: draft,
            controls: &appliedControls
        )
        appliedControls.providerSpecific = remainder

        XCTAssertEqual(appliedControls.temperature, 0.7)
        XCTAssertEqual(appliedControls.topP, 0.9)
        XCTAssertEqual(appliedControls.maxTokens, 2048)
        XCTAssertEqual(appliedControls.reasoning?.enabled, true)
        XCTAssertEqual(appliedControls.reasoning?.effort, .high)
        XCTAssertEqual(appliedControls.reasoning?.summary, .detailed)
        XCTAssertEqual(appliedControls.webSearch?.enabled, true)
        XCTAssertEqual(appliedControls.webSearch?.contextSize, .high)
        XCTAssertEqual(appliedControls.providerSpecific["custom_flag"]?.value as? Bool, true)
        XCTAssertNil(appliedControls.providerSpecific["temperature"])
        XCTAssertNil(appliedControls.providerSpecific["top_p"])
        XCTAssertNil(appliedControls.providerSpecific["reasoning"])
        XCTAssertNil(appliedControls.providerSpecific["tools"])
    }

    func testOpenAIApplyKeepsReasoningOverrideWhenEffortUnrecognized() {
        let draft: [String: AnyCodable] = [
            "reasoning": AnyCodable([
                "effort": "banana",
                "summary": "auto"
            ])
        ]

        var appliedControls = GenerationControls()
        let remainder = ProviderParamsJSONSync.applyDraft(
            providerType: .openai,
            modelID: "gpt-5.2",
            draft: draft,
            controls: &appliedControls
        )

        XCTAssertNil(appliedControls.reasoning)
        XCTAssertNotNil(remainder["reasoning"])
    }

    func testOpenAIWebSearchContextSizeParsesCaseInsensitive() {
        let draft: [String: AnyCodable] = [
            "tools": AnyCodable([
                [
                    "type": "web_search",
                    "search_context_size": "HIGH"
                ]
            ])
        ]

        var appliedControls = GenerationControls()
        let remainder = ProviderParamsJSONSync.applyDraft(
            providerType: .openai,
            modelID: "gpt-5.2",
            draft: draft,
            controls: &appliedControls
        )

        XCTAssertEqual(appliedControls.webSearch?.enabled, true)
        XCTAssertEqual(appliedControls.webSearch?.contextSize, .high)
        XCTAssertNil(remainder["tools"])
    }

    func testAnthropicClaude45BudgetThinkingDraftAndApply() {
        var controls = GenerationControls()
        controls.maxTokens = 8192
        controls.reasoning = ReasoningControls(enabled: true, effort: nil, budgetTokens: 4096, summary: nil)
        controls.webSearch = WebSearchControls(enabled: true)

        let modelID = "claude-sonnet-4-5"
        let draft = ProviderParamsJSONSync.makeDraft(providerType: .anthropic, modelID: modelID, controls: controls)

        XCTAssertEqual(draft["max_tokens"]?.value as? Int, 8192)
        let thinking = draft["thinking"]?.value as? [String: Any]
        XCTAssertEqual(thinking?["type"] as? String, "enabled")
        XCTAssertEqual(thinking?["budget_tokens"] as? Int, 4096)

        let tools = draft["tools"]?.value as? [Any]
        XCTAssertEqual(tools?.count, 1)
        let tool0 = tools?.first as? [String: Any]
        XCTAssertEqual(tool0?["type"] as? String, "web_search_20250305")
        XCTAssertEqual(tool0?["name"] as? String, "web_search")

        var applied = GenerationControls()
        let remainder = ProviderParamsJSONSync.applyDraft(providerType: .anthropic, modelID: modelID, draft: draft, controls: &applied)
        applied.providerSpecific = remainder

        XCTAssertEqual(applied.maxTokens, 8192)
        XCTAssertEqual(applied.reasoning?.enabled, true)
        XCTAssertEqual(applied.reasoning?.budgetTokens, 4096)
        XCTAssertNil(applied.reasoning?.effort)
        XCTAssertEqual(applied.webSearch?.enabled, true)
        XCTAssertNil(applied.providerSpecific["thinking"])
        XCTAssertNil(applied.providerSpecific["tools"])
    }

    func testAnthropicThinkingWithExtraKeysIsPreservedAsOverride() {
        let draft: [String: AnyCodable] = [
            "thinking": AnyCodable([
                "type": "enabled",
                "budget_tokens": 4096,
                "extra": "keep-me"
            ])
        ]

        var applied = GenerationControls()
        let remainder = ProviderParamsJSONSync.applyDraft(
            providerType: .anthropic,
            modelID: "claude-sonnet-4-5",
            draft: draft,
            controls: &applied
        )

        XCTAssertEqual(applied.reasoning?.enabled, true)
        XCTAssertEqual(applied.reasoning?.budgetTokens, 4096)
        XCTAssertNotNil(remainder["thinking"])
    }

    func testAnthropicOpus46AdaptiveThinkingDraftAndApply() {
        var controls = GenerationControls()
        controls.maxTokens = 4096
        controls.reasoning = ReasoningControls(enabled: true, effort: .xhigh, budgetTokens: nil, summary: nil)
        controls.webSearch = WebSearchControls(enabled: true)

        let modelID = "claude-opus-4-6"
        let draft = ProviderParamsJSONSync.makeDraft(providerType: .anthropic, modelID: modelID, controls: controls)

        let thinking = draft["thinking"]?.value as? [String: Any]
        XCTAssertEqual(thinking?["type"] as? String, "adaptive")

        let outputConfig = draft["output_config"]?.value as? [String: Any]
        XCTAssertEqual(outputConfig?["effort"] as? String, "max")

        var applied = GenerationControls()
        let remainder = ProviderParamsJSONSync.applyDraft(providerType: .anthropic, modelID: modelID, draft: draft, controls: &applied)
        applied.providerSpecific = remainder

        XCTAssertEqual(applied.maxTokens, 4096)
        XCTAssertEqual(applied.reasoning?.enabled, true)
        XCTAssertEqual(applied.reasoning?.effort, .xhigh)
        XCTAssertNil(applied.reasoning?.budgetTokens)
        XCTAssertEqual(applied.webSearch?.enabled, true)
        XCTAssertNil(applied.providerSpecific["thinking"])
    }

    func testGeminiThinkingAndGoogleSearchDraftAndApply() {
        var controls = GenerationControls()
        controls.reasoning = ReasoningControls(enabled: true, effort: .high, budgetTokens: nil, summary: nil)
        controls.webSearch = WebSearchControls(enabled: true)

        let modelID = "gemini-3-pro"
        let draft = ProviderParamsJSONSync.makeDraft(providerType: .gemini, modelID: modelID, controls: controls)

        let gen = draft["generationConfig"]?.value as? [String: Any]
        let thinking = gen?["thinkingConfig"] as? [String: Any]
        XCTAssertEqual(thinking?["includeThoughts"] as? Bool, true)
        XCTAssertEqual(thinking?["thinkingLevel"] as? String, "HIGH")

        let tools = draft["tools"]?.value as? [Any]
        XCTAssertEqual(tools?.count, 1)
        let tool0 = tools?.first as? [String: Any]
        XCTAssertNotNil(tool0?["google_search"])

        var applied = GenerationControls()
        let remainder = ProviderParamsJSONSync.applyDraft(providerType: .gemini, modelID: modelID, draft: draft, controls: &applied)
        applied.providerSpecific = remainder

        XCTAssertEqual(applied.reasoning?.enabled, true)
        XCTAssertEqual(applied.reasoning?.effort, .high)
        XCTAssertEqual(applied.webSearch?.enabled, true)
        XCTAssertNil(applied.providerSpecific["tools"])
    }

    func testVertexThinkingAndGoogleSearchDraftAndApply() {
        var controls = GenerationControls()
        controls.reasoning = ReasoningControls(enabled: true, effort: .medium, budgetTokens: nil, summary: nil)
        controls.webSearch = WebSearchControls(enabled: true)

        let modelID = "gemini-3-pro"
        let draft = ProviderParamsJSONSync.makeDraft(providerType: .vertexai, modelID: modelID, controls: controls)

        let gen = draft["generationConfig"]?.value as? [String: Any]
        let thinking = gen?["thinkingConfig"] as? [String: Any]
        XCTAssertEqual(thinking?["includeThoughts"] as? Bool, true)
        XCTAssertEqual(thinking?["thinkingLevel"] as? String, "MEDIUM")

        let tools = draft["tools"]?.value as? [Any]
        XCTAssertEqual(tools?.count, 1)
        let tool0 = tools?.first as? [String: Any]
        XCTAssertNotNil(tool0?["googleSearch"])

        var applied = GenerationControls()
        let remainder = ProviderParamsJSONSync.applyDraft(providerType: .vertexai, modelID: modelID, draft: draft, controls: &applied)
        applied.providerSpecific = remainder

        XCTAssertEqual(applied.reasoning?.enabled, true)
        XCTAssertEqual(applied.reasoning?.effort, .medium)
        XCTAssertEqual(applied.webSearch?.enabled, true)
        XCTAssertNil(applied.providerSpecific["tools"])
    }

    func testCerebrasReasoningToggleDraftAndApply() {
        var controls = GenerationControls()
        controls.reasoning = ReasoningControls(enabled: true)
        controls.maxTokens = 1024

        let draft = ProviderParamsJSONSync.makeDraft(providerType: .cerebras, modelID: "zai-glm-4.7", controls: controls)

        XCTAssertEqual(draft["max_completion_tokens"]?.value as? Int, 1024)
        XCTAssertEqual(draft["disable_reasoning"]?.value as? Bool, false)
        XCTAssertEqual(draft["reasoning_format"]?.value as? String, "parsed")

        var applied = GenerationControls()
        let remainder = ProviderParamsJSONSync.applyDraft(providerType: .cerebras, modelID: "zai-glm-4.7", draft: draft, controls: &applied)
        applied.providerSpecific = remainder

        XCTAssertEqual(applied.maxTokens, 1024)
        XCTAssertEqual(applied.reasoning?.enabled, true)
        XCTAssertNil(applied.providerSpecific["disable_reasoning"])
        XCTAssertNil(applied.providerSpecific["reasoning_format"])
    }

    func testCerebrasReasoningFormatRawIsPreservedAsOverride() {
        let draft: [String: AnyCodable] = [
            "disable_reasoning": AnyCodable(false),
            "reasoning_format": AnyCodable("raw")
        ]

        var applied = GenerationControls()
        let remainder = ProviderParamsJSONSync.applyDraft(
            providerType: .cerebras,
            modelID: "zai-glm-4.7",
            draft: draft,
            controls: &applied
        )
        applied.providerSpecific = remainder

        XCTAssertEqual(applied.reasoning?.enabled, true)
        XCTAssertNil(applied.providerSpecific["disable_reasoning"])
        XCTAssertEqual(applied.providerSpecific["reasoning_format"]?.value as? String, "raw")
    }

    func testFireworksReasoningEffortDraftAndApply() {
        var controls = GenerationControls()
        controls.reasoning = ReasoningControls(enabled: true, effort: .medium)
        controls.providerSpecific = ["reasoning_history": AnyCodable("preserved")]

        let draft = ProviderParamsJSONSync.makeDraft(providerType: .fireworks, modelID: "fireworks/glm-4p7", controls: controls)

        XCTAssertEqual(draft["reasoning_effort"]?.value as? String, "medium")
        XCTAssertEqual(draft["reasoning_history"]?.value as? String, "preserved")

        var applied = GenerationControls()
        let remainder = ProviderParamsJSONSync.applyDraft(providerType: .fireworks, modelID: "fireworks/glm-4p7", draft: draft, controls: &applied)
        applied.providerSpecific = remainder

        XCTAssertEqual(applied.reasoning?.enabled, true)
        XCTAssertEqual(applied.reasoning?.effort, .medium)
        XCTAssertEqual(applied.providerSpecific["reasoning_history"]?.value as? String, "preserved")
        XCTAssertNil(applied.providerSpecific["reasoning_effort"])
    }

    func testPerplexityDraftAndApplySyncsCoreParams() {
        var controls = GenerationControls()
        controls.temperature = 0.4
        controls.topP = 0.85
        controls.maxTokens = 4096
        controls.reasoning = ReasoningControls(enabled: true, effort: .high, budgetTokens: nil, summary: nil)
        controls.webSearch = WebSearchControls(enabled: true, contextSize: .medium, sources: nil)
        controls.providerSpecific = [
            "return_images": AnyCodable(true),
            "search_recency_filter": AnyCodable("week")
        ]

        let draft = ProviderParamsJSONSync.makeDraft(providerType: .perplexity, modelID: "sonar-pro", controls: controls)

        XCTAssertEqual(draft["temperature"]?.value as? Double, 0.4)
        XCTAssertEqual(draft["top_p"]?.value as? Double, 0.85)
        XCTAssertEqual(draft["max_tokens"]?.value as? Int, 4096)
        XCTAssertEqual(draft["reasoning_effort"]?.value as? String, "high")

        let webOptions = draft["web_search_options"]?.value as? [String: Any]
        XCTAssertEqual(webOptions?["search_context_size"] as? String, "medium")

        var applied = GenerationControls()
        let remainder = ProviderParamsJSONSync.applyDraft(
            providerType: .perplexity,
            modelID: "sonar-pro",
            draft: draft,
            controls: &applied
        )
        applied.providerSpecific = remainder

        XCTAssertEqual(applied.temperature, 0.4)
        XCTAssertEqual(applied.topP, 0.85)
        XCTAssertEqual(applied.maxTokens, 4096)
        XCTAssertEqual(applied.reasoning?.enabled, true)
        XCTAssertEqual(applied.reasoning?.effort, .high)
        XCTAssertEqual(applied.webSearch?.enabled, true)
        XCTAssertEqual(applied.webSearch?.contextSize, .medium)
        XCTAssertEqual(applied.providerSpecific["return_images"]?.value as? Bool, true)
        XCTAssertEqual(applied.providerSpecific["search_recency_filter"]?.value as? String, "week")
        XCTAssertNil(applied.providerSpecific["max_tokens"])
        XCTAssertNil(applied.providerSpecific["reasoning_effort"])
        XCTAssertNil(applied.providerSpecific["web_search_options"])
    }

    func testPerplexityDisableSearchDraftAndApply() {
        var controls = GenerationControls()
        controls.webSearch = WebSearchControls(enabled: false, contextSize: nil, sources: nil)

        let draft = ProviderParamsJSONSync.makeDraft(providerType: .perplexity, modelID: "sonar", controls: controls)

        XCTAssertEqual(draft["disable_search"]?.value as? Bool, true)
        XCTAssertNil(draft["web_search_options"])

        var applied = GenerationControls()
        let remainder = ProviderParamsJSONSync.applyDraft(
            providerType: .perplexity,
            modelID: "sonar",
            draft: draft,
            controls: &applied
        )
        applied.providerSpecific = remainder

        XCTAssertEqual(applied.webSearch?.enabled, false)
        XCTAssertNil(applied.providerSpecific["disable_search"])
        XCTAssertNil(applied.providerSpecific["web_search_options"])
    }
}
