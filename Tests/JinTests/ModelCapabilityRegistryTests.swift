import XCTest
@testable import Jin

final class ModelCapabilityRegistryTests: XCTestCase {
    func testMistralMedium35ReasoningAndToolCapabilitiesUseExactID() {
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .mistral, modelID: "mistral-medium-3.5"),
            [.high]
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.medium, for: .mistral, modelID: "mistral-medium-3.5"),
            .high
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.xhigh, for: .mistral, modelID: "mistral-medium-3.5"),
            .high
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.max, for: .mistral, modelID: "mistral-medium-3.5"),
            .high
        )
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .mistral, modelID: "mistral-medium-3.5"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .mistral, modelID: "mistral-medium-3.5"))
    }

    func testOpenAICodeExecutionUsesExactDocumentedModelIDs() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-4.1"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-5"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-5.5"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-5.5-pro"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-5.2"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-5.4"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "o3"))

        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-5.4-pro"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-4o"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-4o-audio-preview"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-realtime"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "o4"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .openaiWebSocket, modelID: "gpt-realtime"))
    }

    func testXAICodeExecutionUsesExactCatalogModelsConservatively() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .xai, modelID: "grok-4.3"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .xai, modelID: "grok-4.20"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .xai, modelID: "grok-4.20-multi-agent"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .xai, modelID: "grok-4.20-multi-agent-0309"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .xai, modelID: "grok-4.3-custom"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .xai, modelID: "grok-4.20-multi-agent-0310"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .xai, modelID: "grok-imagine-image"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .xai, modelID: "grok-imagine-video"))
    }

    func testAnthropicCodeExecutionUsesExactDocumentedModelIDs() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-opus-4-8"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-opus-4-7"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-opus-4-6"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-sonnet-4-6"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-sonnet-4-5-20250929"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-haiku-4-5-20251001"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-3-7-sonnet-20250219"))

        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-haiku-4"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-sonnet-4-5"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-opus-4-6-20260128"))
    }

    func testAnthropicReasoningEffortsAndDynamicFilteringDistinguishClaude47FromClaude46() {
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .anthropic, modelID: "claude-opus-4-8"),
            [.low, .medium, .high, .xhigh, .max]
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .anthropic, modelID: "claude-opus-4-7"),
            [.low, .medium, .high, .xhigh, .max]
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .anthropic, modelID: "claude-opus-4-6"),
            [.low, .medium, .high, .max]
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .anthropic, modelID: "claude-opus-4-5-20251101"),
            [.low, .medium, .high]
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.xhigh, for: .anthropic, modelID: "claude-opus-4-8"),
            .xhigh
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.xhigh, for: .anthropic, modelID: "claude-opus-4-7"),
            .xhigh
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.xhigh, for: .anthropic, modelID: "claude-opus-4-6"),
            .max
        )
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(for: .anthropic, modelID: "claude-opus-4-8")
        )
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(for: .anthropic, modelID: "claude-opus-4-7")
        )
        XCTAssertFalse(
            ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(for: .anthropic, modelID: "claude-opus-4-8-20260528")
        )
    }

    func testFableMythos5SupportEffortButNotServerSideTools() {
        // Effort spans low…max (adaptive-thinking-only, xhigh + max), same as Opus 4.8/4.7.
        for modelID in ["claude-fable-5", "claude-mythos-5"] {
            XCTAssertEqual(
                ModelCapabilityRegistry.supportedReasoningEfforts(for: .anthropic, modelID: modelID),
                [.low, .medium, .high, .xhigh, .max],
                "\(modelID) should expose the full effort range"
            )
            XCTAssertEqual(
                ModelCapabilityRegistry.normalizedReasoningEffort(.xhigh, for: .anthropic, modelID: modelID),
                .xhigh,
                "\(modelID) supports xhigh natively"
            )

            // Per Anthropic's launch docs, Fable 5 / Mythos 5 do NOT support server-side
            // web search, web fetch, or code execution at launch.
            XCTAssertFalse(
                ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: modelID),
                "\(modelID) does not support code execution at launch"
            )
            XCTAssertFalse(
                ModelCapabilityRegistry.supportsWebSearch(for: .anthropic, modelID: modelID),
                "\(modelID) does not support the web search tool at launch"
            )
            XCTAssertFalse(
                ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(for: .anthropic, modelID: modelID),
                "\(modelID) is not on the dynamic-filtering list (only Mythos Preview is, not Mythos 5)"
            )
        }

        // Positive control: narrowing the .anthropic web-search heuristic must not affect Opus.
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .anthropic, modelID: "claude-opus-4-8"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .anthropic, modelID: "claude-sonnet-4-6"))
        // `claude-mythos-preview` is a different (older) model and is NOT gated off here.
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .anthropic, modelID: "claude-mythos-preview"))
    }

    func testSonnet5SupportsFullEffortRangeAndServerSideTools() {
        // Unlike Fable 5 / Mythos 5, Sonnet 5 DOES support server-side code execution and web
        // search (including dynamic filtering) at launch per Anthropic's Sonnet 5 docs.
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .anthropic, modelID: "claude-sonnet-5"),
            [.low, .medium, .high, .xhigh, .max],
            "Sonnet 5 should expose the full effort range (first Sonnet-tier model with xhigh)"
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.xhigh, for: .anthropic, modelID: "claude-sonnet-5"),
            .xhigh,
            "Sonnet 5 supports xhigh natively"
        )
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-sonnet-5"),
            "Sonnet 5 supports code execution at launch"
        )
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsWebSearch(for: .anthropic, modelID: "claude-sonnet-5"),
            "Sonnet 5 supports the web search tool at launch"
        )
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(for: .anthropic, modelID: "claude-sonnet-5"),
            "Sonnet 5 is on the dynamic-filtering (web_search_20260209) list"
        )
    }

    func testGeminiCodeExecutionUsesExactDocumentedModelIDs() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-3-pro"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-3.1-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-3-flash-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-3.1-flash-lite-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-3.1-flash-lite"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-2.5-flash-lite"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-2.0-flash-001"))

        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-3"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-3-pro-image-preview"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-2.5-flash-image"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-2.0-flash-lite"))
    }

    func testVertexCodeExecutionUsesExactDocumentedModelIDs() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-3-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-3.1-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-3-flash-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-3.1-flash-lite-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-2.5-flash-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-2.5-flash-lite-preview"))

        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-3.1-flash-lite"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-3"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-3-pro-image-preview"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-2.5-flash-image"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-2.0-flash-lite"))
    }

    func testGeminiWebSearchUsesExactDocumentedModelIDs() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3.1-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3-flash-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3-pro-image-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3.1-flash-image-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3.1-flash-lite-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3.1-flash-lite"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-2.5-flash-lite"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-2.0-flash"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemma-4-26b-a4b-it"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemma-4-31b-it"))

        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-2.5-flash-image"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-2.0-flash-lite"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "veo-3"))
    }

    func testVertexWebSearchUsesExactSupportedModelIDs() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemini-3.1-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemini-3-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemini-3-flash-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemini-3-pro-image-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemini-3.1-flash-image-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemini-3.1-flash-lite-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemini-2.5-flash-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemini-2.5-flash-lite-preview"))

        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemini-3.1-flash-lite"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemini-2.0-flash-lite"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "veo-2"))
    }

    func testOpenCodeGoWebSearchUsesExactSupportedModelIDs() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .opencodeGo, modelID: "mimo-v2.5-pro"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .opencodeGo, modelID: "mimo-v2.5"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .opencodeGo, modelID: "mimo-v2-pro"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .opencodeGo, modelID: "mimo-v2-omni"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .opencodeGo, modelID: "mimo-v2-flash"))

        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .opencodeGo, modelID: "kimi-k2.6"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .opencodeGo, modelID: "mimo-v2.5-preview"))
    }

    func testMiMoTokenPlanWebSearchUsesExactSupportedModelIDs() {
        let supportedIDs = [
            "mimo-v2.5-pro",
            "mimo-v2.5",
            "mimo-v2-pro",
            "mimo-v2-omni",
            "mimo-v2-flash",
        ]

        for modelID in supportedIDs {
            XCTAssertTrue(
                ModelCapabilityRegistry.supportsWebSearch(for: .mimoTokenPlanOpenAI, modelID: modelID),
                modelID
            )
        }

        for modelID in supportedIDs {
            XCTAssertFalse(
                ModelCapabilityRegistry.supportsWebSearch(for: .mimoTokenPlanAnthropic, modelID: modelID),
                modelID
            )
        }

        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .mimoTokenPlanOpenAI, modelID: "mimo-v2.5-preview"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .mimoTokenPlanAnthropic, modelID: "mimo-v2.5-preview"))
    }

    func testGoogleMapsSupportUsesExactDocumentedModelIDs() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .gemini, modelID: "gemini-3.5-flash"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .gemini, modelID: "gemini-3.1-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .gemini, modelID: "gemini-3.1-flash-lite"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .gemini, modelID: "gemini-3.1-flash-lite-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .gemini, modelID: "gemini-3-flash-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .gemini, modelID: "gemini-2.5-pro"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .gemini, modelID: "gemini-2.5-flash"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .gemini, modelID: "gemini-2.0-flash-001"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsGoogleMaps(for: .gemini, modelID: "gemini-3-pro-preview"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsGoogleMaps(for: .gemini, modelID: "gemini-2.0-flash-lite"))

        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-3-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-3-pro-image-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-2.5-flash"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-2.5-flash-preview-09-2025"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-2.5-flash-lite-preview-09-2025"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-live-2.5-flash-native-audio"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-live-2.5-flash-preview-native-audio-09-2025"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-2.0-flash-live-preview-04-09"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-2.0-flash-001"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-3-flash-preview"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-3.5-flash"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-3.1-pro-preview"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsGoogleMaps(for: .openai, modelID: "gpt-5"))
    }

    func testOpenRouterGoogleModelsUseCanonicalAllowlist() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "google/gemini-3-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "google/gemini-3.1-pro-preview"))

        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "google/veo-3"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "google/gemini-2.0-flash-lite"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "google/gemma-4-31b-it"))
    }

    func testTogetherWebSearchDefaultsToDisabled() {
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .together, modelID: "moonshotai/Kimi-K2.5"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .together, modelID: "zai-org/GLM-5"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .together, modelID: "deepseek-ai/DeepSeek-V3.1"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .together, modelID: "openai/gpt-oss-120b"))
    }

    func testVercelAIGatewayWebSearchDefaultsToDisabledForNativeControls() {
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .vercelAIGateway, modelID: "openai/gpt-5.2"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .vercelAIGateway, modelID: "anthropic/claude-sonnet-4.6"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .vercelAIGateway, modelID: "google/gemini-3.1-pro-preview"))
    }

    func testOpenRouterTildeAliasesShareCanonicalWebSearchPolicy() {
        // The `~`-prefixed "latest"-family aliases must resolve to the same web-search
        // policy as their canonical twins (the `~` is stripped before the prefix checks).
        let aliasPairs = [
            ("~openai/gpt-latest", "openai/gpt-latest"),
            ("~openai/gpt-mini-latest", "openai/gpt-mini-latest"),
            ("~anthropic/claude-opus-latest", "anthropic/claude-opus-latest"),
            ("~anthropic/claude-sonnet-latest", "anthropic/claude-sonnet-latest"),
            ("~anthropic/claude-haiku-latest", "anthropic/claude-haiku-latest"),
            ("~google/gemini-pro-latest", "google/gemini-pro-latest"),
            ("~google/gemini-flash-latest", "google/gemini-flash-latest"),
            ("~moonshotai/kimi-latest", "moonshotai/kimi-latest"),
        ]
        for (alias, canonical) in aliasPairs {
            XCTAssertEqual(
                ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: alias),
                ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: canonical),
                "\(alias) should share \(canonical)'s web-search policy"
            )
        }

        // OpenAI- and Anthropic-family aliases enable OpenRouter web search (the point of the `~` fix).
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "~openai/gpt-latest"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "~openai/gpt-mini-latest"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "~anthropic/claude-opus-latest"))

        // A vendor outside the web-search allowlist stays disabled, matching its canonical id.
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "~moonshotai/kimi-latest"))
    }
}
