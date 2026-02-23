import XCTest
@testable import Jin

final class ProviderParamsJSONSyncTests: XCTestCase {
    func testAnthropicDraftUsesDynamicWebSearchOnlyForSupported46Models() throws {
        let controls = GenerationControls(
            webSearch: WebSearchControls(enabled: true, dynamicFiltering: true)
        )

        let supportedDraft = ProviderParamsJSONSync.makeDraft(
            providerType: .anthropic,
            modelID: "claude-sonnet-4-6",
            controls: controls
        )
        let supportedTools = try XCTUnwrap(supportedDraft["tools"]?.value as? [[String: Any]])
        XCTAssertEqual(supportedTools.first?["type"] as? String, "web_search_20260209")

        let unsupportedDraft = ProviderParamsJSONSync.makeDraft(
            providerType: .anthropic,
            modelID: "claude-sonnet-4-5-20250929",
            controls: controls
        )
        let unsupportedTools = try XCTUnwrap(unsupportedDraft["tools"]?.value as? [[String: Any]])
        XCTAssertEqual(unsupportedTools.first?["type"] as? String, "web_search_20250305")
    }

    func testAnthropicDraftPrefersAllowedDomainsWhenBothListsPresent() throws {
        let controls = GenerationControls(
            webSearch: WebSearchControls(
                enabled: true,
                allowedDomains: [" example.com ", "Example.com"],
                blockedDomains: ["blocked.example.com"]
            )
        )

        let draft = ProviderParamsJSONSync.makeDraft(
            providerType: .anthropic,
            modelID: "claude-sonnet-4-6",
            controls: controls
        )
        let tools = try XCTUnwrap(draft["tools"]?.value as? [[String: Any]])
        let spec = try XCTUnwrap(tools.first)

        XCTAssertEqual(spec["allowed_domains"] as? [String], ["example.com"])
        XCTAssertNil(spec["blocked_domains"])
    }

    func testApplyAnthropicDraftWithConflictingDomainFiltersKeepsMutualExclusionInControls() throws {
        var controls = GenerationControls()
        let draft: [String: AnyCodable] = [
            "tools": AnyCodable([
                [
                    "type": "web_search_20250305",
                    "name": "web_search",
                    "allowed_domains": ["example.com"],
                    "blocked_domains": ["blocked.example.com"]
                ]
            ])
        ]

        let providerSpecific = ProviderParamsJSONSync.applyDraft(
            providerType: .anthropic,
            modelID: "claude-sonnet-4-6",
            draft: draft,
            controls: &controls
        )

        XCTAssertEqual(controls.webSearch?.allowedDomains, ["example.com"])
        XCTAssertNil(controls.webSearch?.blockedDomains)
        XCTAssertNotNil(providerSpecific["tools"])
    }

    func testVertexGemini3ProImageDraftOmitsThinkingConfigWhenReasoningConfigured() throws {
        let controls = GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .high))

        let draft = ProviderParamsJSONSync.makeDraft(
            providerType: .vertexai,
            modelID: "gemini-3-pro-image-preview",
            controls: controls
        )

        if let generationConfig = draft["generationConfig"]?.value as? [String: Any] {
            XCTAssertNil(generationConfig["thinkingConfig"])
        } else {
            XCTAssertNil(draft["generationConfig"])
        }
    }

    func testVertexGemini3ProDraftKeepsThinkingLevelWhenEffortConfigured() throws {
        let controls = GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .high))

        let draft = ProviderParamsJSONSync.makeDraft(
            providerType: .vertexai,
            modelID: "gemini-3-pro-preview",
            controls: controls
        )

        let generationConfig = try XCTUnwrap(draft["generationConfig"]?.value as? [String: Any])
        let thinkingConfig = try XCTUnwrap(generationConfig["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(thinkingConfig["includeThoughts"] as? Bool, true)
        XCTAssertEqual(thinkingConfig["thinkingLevel"] as? String, "HIGH")
    }

    func testOpenAIDraftClampsUnsupportedXHighEffortToHigh() throws {
        let controls = GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .xhigh))

        let unsupportedDraft = ProviderParamsJSONSync.makeDraft(
            providerType: .openai,
            modelID: "gpt-5",
            controls: controls
        )
        let unsupportedReasoning = try XCTUnwrap(unsupportedDraft["reasoning"]?.value as? [String: Any])
        XCTAssertEqual(unsupportedReasoning["effort"] as? String, "high")

        let supportedDraft = ProviderParamsJSONSync.makeDraft(
            providerType: .openai,
            modelID: "gpt-5.2-pro",
            controls: controls
        )
        let supportedReasoning = try XCTUnwrap(supportedDraft["reasoning"]?.value as? [String: Any])
        XCTAssertEqual(supportedReasoning["effort"] as? String, "xhigh")

        let sparkDraft = ProviderParamsJSONSync.makeDraft(
            providerType: .openai,
            modelID: "gpt-5.3-codex-spark",
            controls: controls
        )
        let sparkReasoning = try XCTUnwrap(sparkDraft["reasoning"]?.value as? [String: Any])
        XCTAssertEqual(sparkReasoning["effort"] as? String, "xhigh")
    }

    func testApplyOpenAIDraftClampsUnsupportedXHighEffortToHigh() throws {
        let draft: [String: AnyCodable] = [
            "reasoning": AnyCodable([
                "effort": "xhigh",
                "summary": "auto"
            ])
        ]

        var unsupportedControls = GenerationControls()
        _ = ProviderParamsJSONSync.applyDraft(
            providerType: .openai,
            modelID: "gpt-5",
            draft: draft,
            controls: &unsupportedControls
        )
        XCTAssertEqual(unsupportedControls.reasoning?.effort, .high)

        var supportedControls = GenerationControls()
        _ = ProviderParamsJSONSync.applyDraft(
            providerType: .openai,
            modelID: "gpt-5.2-codex",
            draft: draft,
            controls: &supportedControls
        )
        XCTAssertEqual(supportedControls.reasoning?.effort, .xhigh)

        var sparkControls = GenerationControls()
        _ = ProviderParamsJSONSync.applyDraft(
            providerType: .openai,
            modelID: "gpt-5.3-codex-spark",
            draft: draft,
            controls: &sparkControls
        )
        XCTAssertEqual(sparkControls.reasoning?.effort, .xhigh)
    }
}
