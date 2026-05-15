import XCTest
@testable import Jin

final class ChatAuxiliaryControlSupportTests: XCTestCase {
    func testEffectiveContextCacheModeUsesStoredModeAndProviderDefaults() {
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.effectiveContextCacheMode(
                controls: GenerationControls(contextCache: ContextCacheControls(mode: .explicit)),
                providerType: .anthropic
            ),
            .explicit
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.effectiveContextCacheMode(
                controls: GenerationControls(),
                providerType: .claudeManagedAgents
            ),
            .implicit
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.effectiveContextCacheMode(
                controls: GenerationControls(),
                providerType: .openai
            ),
            .off
        )
    }

    func testContextCachePresentationTextMatchesProviderFamilies() {
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.contextCacheSummaryText(providerType: .gemini),
            "Use implicit caching for normal chats, or explicit caching with a cached content resource for long reusable context."
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.contextCacheSummaryText(providerType: .anthropic),
            "Anthropic caches tagged prompt blocks. Keep stable system/tool prefixes to improve cache hit rates."
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.contextCacheSummaryText(providerType: .openai),
            "OpenAI uses prompt cache hints. A stable key and retention hint can improve reuse across similar prompts."
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.contextCacheSummaryText(providerType: .xai),
            "xAI supports prompt cache hints and optional conversation scoping for continuity across related turns."
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.contextCacheSummaryText(providerType: .openrouter),
            "Context cache controls are only available for providers with native prompt caching support."
        )

        XCTAssertEqual(
            ChatAuxiliaryControlSupport.contextCacheGuidanceText(providerType: .vertexai),
            "Explicit mode requires a valid cached content resource name. Keep it stable across requests to reuse cached tokens."
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.contextCacheGuidanceText(providerType: .xai),
            "Use a stable cache key when your prompt prefix is consistent."
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.contextCacheGuidanceText(providerType: .claudeManagedAgents),
            "For best results, keep system prompts and tool descriptions stable so Anthropic can reuse cacheable blocks."
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.contextCacheGuidanceText(providerType: .openrouter),
            "Use explicit mode for Gemini/Vertex cached content resources. Other providers use implicit cache hints."
        )
    }

    func testContextCacheLabelBadgeAndHelpTextMatchModeState() {
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.contextCacheLabel(mode: .off, controls: nil),
            "Off"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.contextCacheLabel(mode: .implicit, controls: nil),
            "Implicit"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.contextCacheLabel(
                mode: .explicit,
                controls: ContextCacheControls(mode: .explicit, cachedContentName: "  cachedContents/abc  ")
            ),
            "Explicit (cachedContents/abc)"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.contextCacheLabel(
                mode: .explicit,
                controls: ContextCacheControls(mode: .explicit, cachedContentName: " ")
            ),
            "Explicit"
        )

        XCTAssertNil(
            ChatAuxiliaryControlSupport.contextCacheBadgeText(
                supportsContextCacheControl: false,
                mode: .implicit
            )
        )
        XCTAssertNil(
            ChatAuxiliaryControlSupport.contextCacheBadgeText(
                supportsContextCacheControl: true,
                mode: .off
            )
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.contextCacheBadgeText(
                supportsContextCacheControl: true,
                mode: .implicit
            ),
            "I"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.contextCacheBadgeText(
                supportsContextCacheControl: true,
                mode: .explicit
            ),
            "E"
        )

        XCTAssertEqual(
            ChatAuxiliaryControlSupport.contextCacheHelpText(
                supportsContextCacheControl: false,
                mode: .implicit,
                label: "Implicit"
            ),
            "Context Cache: Not supported"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.contextCacheHelpText(
                supportsContextCacheControl: true,
                mode: .off,
                label: "Off"
            ),
            "Context Cache: Off"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.contextCacheHelpText(
                supportsContextCacheControl: true,
                mode: .explicit,
                label: "Explicit (cachedContents/abc)"
            ),
            "Context Cache: Explicit (cachedContents/abc)"
        )
    }

    func testContextCacheCapabilityPredicatesMatchProviderFamilies() {
        for providerType in ProviderType.allCases {
            let expectsExplicitMode = providerType == .gemini || providerType == .vertexai
            let expectsStrategy = providerType == .anthropic || providerType == .claudeManagedAgents
            let expectsTTL = providerType == .openai
                || providerType == .openaiWebSocket
                || providerType == .anthropic
                || providerType == .claudeManagedAgents
                || providerType == .xai
            let expectsAdvancedOptions = expectsTTL || providerType == .openai || providerType == .xai

            XCTAssertEqual(
                ChatAuxiliaryControlSupport.supportsExplicitContextCacheMode(providerType: providerType),
                expectsExplicitMode,
                "\(providerType.rawValue) explicit context cache support changed"
            )
            XCTAssertEqual(
                ChatAuxiliaryControlSupport.supportsContextCacheStrategy(providerType: providerType),
                expectsStrategy,
                "\(providerType.rawValue) context cache strategy support changed"
            )
            XCTAssertEqual(
                ChatAuxiliaryControlSupport.supportsContextCacheTTL(providerType: providerType),
                expectsTTL,
                "\(providerType.rawValue) context cache TTL support changed"
            )
            XCTAssertEqual(
                ChatAuxiliaryControlSupport.contextCacheSupportsAdvancedOptions(
                    providerType: providerType,
                    supportsContextCacheTTL: expectsTTL
                ),
                expectsAdvancedOptions,
                "\(providerType.rawValue) context cache advanced option support changed"
            )
        }

        XCTAssertFalse(ChatAuxiliaryControlSupport.supportsExplicitContextCacheMode(providerType: nil))
        XCTAssertFalse(ChatAuxiliaryControlSupport.supportsContextCacheStrategy(providerType: nil))
        XCTAssertFalse(ChatAuxiliaryControlSupport.supportsContextCacheTTL(providerType: nil))
        XCTAssertFalse(
            ChatAuxiliaryControlSupport.contextCacheSupportsAdvancedOptions(
                providerType: nil,
                supportsContextCacheTTL: false
            )
        )
    }

    func testContextCacheMenuMutatorsCreateAndResetModeState() {
        let offControls = ChatAuxiliaryControlSupport.turnOffContextCache(
            controls: GenerationControls()
        )
        XCTAssertEqual(offControls.contextCache, ContextCacheControls(mode: .off))

        let implicitControls = ChatAuxiliaryControlSupport.setImplicitContextCache(
            controls: GenerationControls(),
            providerType: .openai
        )
        XCTAssertEqual(implicitControls.contextCache?.mode, .implicit)

        let explicitControls = ChatAuxiliaryControlSupport.setExplicitContextCache(
            controls: GenerationControls()
        )
        XCTAssertEqual(explicitControls.contextCache?.mode, .explicit)

        let resetControls = ChatAuxiliaryControlSupport.resetContextCache(
            controls: explicitControls
        )
        XCTAssertNil(resetControls.contextCache)
    }

    func testContextCacheMenuMutatorsPreserveExistingFieldsWhenChangingModes() {
        let originalCache = ContextCacheControls(
            mode: .implicit,
            strategy: .prefixWindow,
            ttl: .hour1,
            cacheKey: "cache-key",
            conversationID: "conversation-id",
            cachedContentName: "cachedContents/cache-123",
            minTokensThreshold: 1_024
        )
        let originalControls = GenerationControls(contextCache: originalCache)

        let explicitControls = ChatAuxiliaryControlSupport.setExplicitContextCache(
            controls: originalControls
        )
        XCTAssertEqual(explicitControls.contextCache?.mode, .explicit)
        XCTAssertEqual(explicitControls.contextCache?.strategy, .prefixWindow)
        XCTAssertEqual(explicitControls.contextCache?.ttl, .hour1)
        XCTAssertEqual(explicitControls.contextCache?.cacheKey, "cache-key")
        XCTAssertEqual(explicitControls.contextCache?.conversationID, "conversation-id")
        XCTAssertEqual(explicitControls.contextCache?.cachedContentName, "cachedContents/cache-123")
        XCTAssertEqual(explicitControls.contextCache?.minTokensThreshold, 1_024)

        let implicitControls = ChatAuxiliaryControlSupport.setImplicitContextCache(
            controls: explicitControls,
            providerType: .xai
        )
        XCTAssertEqual(implicitControls.contextCache?.mode, .implicit)
        XCTAssertEqual(implicitControls.contextCache?.ttl, .hour1)
        XCTAssertEqual(implicitControls.contextCache?.cacheKey, "cache-key")
        XCTAssertEqual(implicitControls.contextCache?.conversationID, "conversation-id")
        XCTAssertEqual(implicitControls.contextCache?.minTokensThreshold, 1_024)
        XCTAssertNil(implicitControls.contextCache?.strategy)
        XCTAssertNil(implicitControls.contextCache?.cachedContentName)
    }

    func testSetImplicitContextCacheClearsProviderInapplicableFields() {
        let cache = ContextCacheControls(
            mode: .explicit,
            strategy: .prefixWindow,
            ttl: .hour1,
            cacheKey: "cache-key",
            conversationID: "conversation-id",
            cachedContentName: "cachedContents/cache-123",
            minTokensThreshold: 1_024
        )

        let openAIControls = ChatAuxiliaryControlSupport.setImplicitContextCache(
            controls: GenerationControls(contextCache: cache),
            providerType: .openai
        )
        XCTAssertEqual(openAIControls.contextCache?.mode, .implicit)
        XCTAssertEqual(openAIControls.contextCache?.cacheKey, "cache-key")
        XCTAssertEqual(openAIControls.contextCache?.ttl, .hour1)
        XCTAssertNil(openAIControls.contextCache?.strategy)
        XCTAssertNil(openAIControls.contextCache?.conversationID)
        XCTAssertNil(openAIControls.contextCache?.cachedContentName)
        XCTAssertNil(openAIControls.contextCache?.minTokensThreshold)

        let anthropicControls = ChatAuxiliaryControlSupport.setImplicitContextCache(
            controls: GenerationControls(contextCache: cache),
            providerType: .anthropic
        )
        XCTAssertEqual(anthropicControls.contextCache?.strategy, .prefixWindow)
        XCTAssertEqual(anthropicControls.contextCache?.ttl, .hour1)
        XCTAssertNil(anthropicControls.contextCache?.cacheKey)
        XCTAssertNil(anthropicControls.contextCache?.conversationID)
        XCTAssertNil(anthropicControls.contextCache?.cachedContentName)
        XCTAssertNil(anthropicControls.contextCache?.minTokensThreshold)

        let geminiControls = ChatAuxiliaryControlSupport.setImplicitContextCache(
            controls: GenerationControls(contextCache: cache),
            providerType: .gemini
        )
        XCTAssertEqual(geminiControls.contextCache?.cachedContentName, "cachedContents/cache-123")
        XCTAssertEqual(geminiControls.contextCache?.ttl, .hour1)
        XCTAssertNil(geminiControls.contextCache?.strategy)
        XCTAssertNil(geminiControls.contextCache?.cacheKey)
        XCTAssertNil(geminiControls.contextCache?.conversationID)
        XCTAssertNil(geminiControls.contextCache?.minTokensThreshold)

        let unsupportedControls = ChatAuxiliaryControlSupport.setImplicitContextCache(
            controls: GenerationControls(contextCache: cache),
            providerType: .openrouter
        )
        XCTAssertEqual(unsupportedControls.contextCache?.ttl, .hour1)
        XCTAssertNil(unsupportedControls.contextCache?.strategy)
        XCTAssertNil(unsupportedControls.contextCache?.cacheKey)
        XCTAssertNil(unsupportedControls.contextCache?.conversationID)
        XCTAssertNil(unsupportedControls.contextCache?.cachedContentName)
        XCTAssertNil(unsupportedControls.contextCache?.minTokensThreshold)
    }

    func testPrepareContextCacheEditorDraftUsesProviderDefaultAndExpansionState() {
        let anthropicDraft = ChatAuxiliaryControlSupport.prepareContextCacheEditorDraft(
            current: nil,
            providerType: .anthropic,
            supportsContextCacheTTL: true
        )

        XCTAssertEqual(anthropicDraft.draft, ContextCacheControls(mode: .implicit))
        XCTAssertEqual(anthropicDraft.ttlPreset, .providerDefault)
        XCTAssertEqual(anthropicDraft.customTTLDraft, "")
        XCTAssertEqual(anthropicDraft.minTokensDraft, "")
        XCTAssertFalse(anthropicDraft.advancedExpanded)

        let xaiDraft = ChatAuxiliaryControlSupport.prepareContextCacheEditorDraft(
            current: ContextCacheControls(
                mode: .implicit,
                ttl: .customSeconds(90),
                cacheKey: "  cache-key  ",
                conversationID: " conversation-id ",
                minTokensThreshold: 2_048
            ),
            providerType: .xai,
            supportsContextCacheTTL: true
        )

        XCTAssertEqual(xaiDraft.draft.ttl, .customSeconds(90))
        XCTAssertEqual(xaiDraft.ttlPreset, .custom)
        XCTAssertEqual(xaiDraft.customTTLDraft, "90")
        XCTAssertEqual(xaiDraft.minTokensDraft, "2048")
        XCTAssertTrue(xaiDraft.advancedExpanded)
    }

    func testApplyContextCacheDraftRemovesProviderUnsupportedFields() throws {
        let applied = try ChatAuxiliaryControlSupport.applyContextCacheDraft(
            draft: ContextCacheControls(
                mode: .explicit,
                strategy: .prefixWindow,
                ttl: .providerDefault,
                cacheKey: "  cache-key  ",
                conversationID: "  conversation-id  ",
                cachedContentName: "  cachedContents/cache-123  ",
                minTokensThreshold: 1_024
            ),
            ttlPreset: .hour1,
            customTTLDraft: "",
            minTokensDraft: " 2048 ",
            supportsContextCacheTTL: true,
            supportsContextCacheStrategy: false,
            supportsExplicitContextCacheMode: false,
            providerType: .openai
        ).get()

        XCTAssertEqual(applied?.mode, .implicit)
        XCTAssertEqual(applied?.ttl, .hour1)
        XCTAssertEqual(applied?.cacheKey, "cache-key")
        XCTAssertNil(applied?.strategy)
        XCTAssertNil(applied?.conversationID)
        XCTAssertNil(applied?.cachedContentName)
        XCTAssertNil(applied?.minTokensThreshold)
    }

    func testApplyContextCacheDraftWritesNormalizedResultIntoGenerationControls() throws {
        let originalControls = GenerationControls(
            temperature: 0.3,
            contextCache: ContextCacheControls(mode: .off)
        )

        let applied = try ChatAuxiliaryControlSupport.applyContextCacheDraft(
            draft: ContextCacheControls(
                mode: .implicit,
                ttl: .providerDefault,
                cacheKey: "  cache-key  ",
                conversationID: "  conversation-id  ",
                minTokensThreshold: nil
            ),
            ttlPreset: .custom,
            customTTLDraft: "120",
            minTokensDraft: " 2048 ",
            supportsContextCacheTTL: true,
            supportsContextCacheStrategy: false,
            supportsExplicitContextCacheMode: false,
            providerType: .xai,
            controls: originalControls
        ).get()

        XCTAssertEqual(applied.controls.temperature, 0.3)
        XCTAssertEqual(applied.contextCache?.mode, .implicit)
        XCTAssertEqual(applied.contextCache?.ttl, .customSeconds(120))
        XCTAssertEqual(applied.contextCache?.cacheKey, "cache-key")
        XCTAssertEqual(applied.contextCache?.conversationID, "conversation-id")
        XCTAssertEqual(applied.contextCache?.minTokensThreshold, 2_048)
        XCTAssertEqual(applied.controls.contextCache?.ttl, .customSeconds(120))
        XCTAssertEqual(applied.controls.contextCache?.cacheKey, "cache-key")
    }

    func testApplyContextCacheDraftDropsBlankTextFields() throws {
        let applied = try ChatAuxiliaryControlSupport.applyContextCacheDraft(
            draft: ContextCacheControls(
                mode: .implicit,
                ttl: .providerDefault,
                cacheKey: "  \n",
                conversationID: "\t ",
                minTokensThreshold: 256
            ),
            ttlPreset: .providerDefault,
            customTTLDraft: "",
            minTokensDraft: " ",
            supportsContextCacheTTL: true,
            supportsContextCacheStrategy: false,
            supportsExplicitContextCacheMode: false,
            providerType: .xai
        ).get()

        XCTAssertEqual(applied?.mode, .implicit)
        XCTAssertNil(applied?.cacheKey)
        XCTAssertNil(applied?.conversationID)
        XCTAssertNil(applied?.minTokensThreshold)
    }

    func testContextCacheDraftValidationUsesTrimmedExplicitName() {
        XCTAssertTrue(
            ChatAuxiliaryControlSupport.isContextCacheDraftValid(
                contextCacheDraft: ContextCacheControls(
                    mode: .explicit,
                    cachedContentName: "  cachedContents/cache-123  "
                ),
                ttlPreset: .providerDefault,
                customTTLDraft: "",
                minTokensDraft: "",
                supportsExplicitContextCacheMode: true
            )
        )

        XCTAssertFalse(
            ChatAuxiliaryControlSupport.isContextCacheDraftValid(
                contextCacheDraft: ContextCacheControls(
                    mode: .explicit,
                    cachedContentName: " \n "
                ),
                ttlPreset: .providerDefault,
                customTTLDraft: "",
                minTokensDraft: "",
                supportsExplicitContextCacheMode: true
            )
        )
    }

    func testApplyContextCacheDraftWithGenerationControlsPropagatesValidationFailure() {
        let result = ChatAuxiliaryControlSupport.applyContextCacheDraft(
            draft: ContextCacheControls(mode: .implicit),
            ttlPreset: .custom,
            customTTLDraft: "0",
            minTokensDraft: "",
            supportsContextCacheTTL: true,
            supportsContextCacheStrategy: false,
            supportsExplicitContextCacheMode: false,
            providerType: .openai,
            controls: GenerationControls(
                contextCache: ContextCacheControls(mode: .implicit, ttl: .hour1)
            )
        )

        switch result {
        case .success:
            XCTFail("Expected validation failure")
        case .failure(let error):
            XCTAssertEqual(error.localizedDescription, "Custom TTL must be a positive integer (seconds).")
        }
    }

    func testSessionControlSupportAndBadgesMatchProviderAndOverrideState() {
        XCTAssertTrue(ChatAuxiliaryControlSupport.supportsClaudeManagedAgentSessionControl(providerType: .claudeManagedAgents))
        XCTAssertFalse(ChatAuxiliaryControlSupport.supportsClaudeManagedAgentSessionControl(providerType: .anthropic))

        XCTAssertTrue(
            ChatAuxiliaryControlSupport.supportsOpenAIServiceTierControl(
                providerType: .openai,
                supportsMediaGenerationControl: false
            )
        )
        XCTAssertTrue(
            ChatAuxiliaryControlSupport.supportsOpenAIServiceTierControl(
                providerType: .openaiWebSocket,
                supportsMediaGenerationControl: false
            )
        )
        XCTAssertFalse(
            ChatAuxiliaryControlSupport.supportsOpenAIServiceTierControl(
                providerType: .openai,
                supportsMediaGenerationControl: true
            )
        )
        XCTAssertFalse(
            ChatAuxiliaryControlSupport.supportsOpenAIServiceTierControl(
                providerType: .xai,
                supportsMediaGenerationControl: false
            )
        )

        var claudeControls = GenerationControls()
        XCTAssertNil(ChatAuxiliaryControlSupport.claudeManagedAgentSessionBadgeText(controls: claudeControls))
        claudeControls.claudeManagedAgentID = "agent-1"
        XCTAssertEqual(ChatAuxiliaryControlSupport.claudeManagedAgentSessionBadgeText(controls: claudeControls), "1")
        claudeControls.claudeManagedEnvironmentID = "env-1"
        XCTAssertEqual(ChatAuxiliaryControlSupport.claudeManagedAgentSessionBadgeText(controls: claudeControls), "2")
    }

    func testClaudeManagedAgentSessionHelpTextMatchesResolvedState() {
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.claudeManagedAgentSessionHelpText(
                supportsClaudeManagedAgentSessionControl: false,
                resolvedControls: GenerationControls(),
                agentDisplayName: nil,
                environmentDisplayName: nil
            ),
            "Claude Managed Agent: Not supported"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.claudeManagedAgentSessionHelpText(
                supportsClaudeManagedAgentSessionControl: true,
                resolvedControls: GenerationControls(),
                agentDisplayName: nil,
                environmentDisplayName: nil
            ),
            "Claude Managed Agent: Agent: not configured \u{00B7} Environment: not configured"
        )

        var controls = GenerationControls()
        controls.claudeManagedAgentID = "agent-1"
        controls.claudeManagedEnvironmentID = "env-1"
        controls.claudeManagedSessionID = "session-1"

        XCTAssertEqual(
            ChatAuxiliaryControlSupport.claudeManagedAgentSessionHelpText(
                supportsClaudeManagedAgentSessionControl: true,
                resolvedControls: controls,
                agentDisplayName: "Swift Agent",
                environmentDisplayName: "Xcode Lab"
            ),
            "Claude Managed Agent: Agent: Swift Agent \u{00B7} Environment: Xcode Lab \u{00B7} Session: session-1"
        )
    }

    func testOpenAIServiceTierPresentationMatchesSupportAndSelection() {
        let defaults = GenerationControls()
        XCTAssertEqual(ChatAuxiliaryControlSupport.openAIServiceTierLabel(controls: defaults), "Auto")
        XCTAssertNil(
            ChatAuxiliaryControlSupport.openAIServiceTierBadgeText(
                supportsOpenAIServiceTierControl: true,
                controls: defaults
            )
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.openAIServiceTierHelpText(
                supportsOpenAIServiceTierControl: true,
                label: "Auto"
            ),
            "Service Tier: Auto"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.openAIServiceTierHelpText(
                supportsOpenAIServiceTierControl: false,
                label: "Priority"
            ),
            "Service Tier: Not supported"
        )

        let priority = GenerationControls(openAIServiceTier: .priority)
        XCTAssertEqual(ChatAuxiliaryControlSupport.openAIServiceTierLabel(controls: priority), "Priority")
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.openAIServiceTierBadgeText(
                supportsOpenAIServiceTierControl: true,
                controls: priority
            ),
            "P"
        )
        XCTAssertNil(
            ChatAuxiliaryControlSupport.openAIServiceTierBadgeText(
                supportsOpenAIServiceTierControl: false,
                controls: priority
            )
        )
    }

    func testSetOpenAIServiceTierStoresSelectionAndClearsToAuto() {
        let selected = ChatAuxiliaryControlSupport.setOpenAIServiceTier(
            .priority,
            controls: GenerationControls()
        )
        XCTAssertEqual(selected.openAIServiceTier, .priority)

        let auto = ChatAuxiliaryControlSupport.setOpenAIServiceTier(
            nil,
            controls: selected
        )
        XCTAssertNil(auto.openAIServiceTier)
    }

    func testSetCodeExecutionEnabledCreatesControls() {
        let enabled = ChatAuxiliaryControlSupport.setCodeExecutionEnabled(
            true,
            controls: GenerationControls()
        )

        XCTAssertEqual(enabled.codeExecution?.enabled, true)
        XCTAssertNil(enabled.codeExecution?.openAI)
        XCTAssertNil(enabled.codeExecution?.anthropic)
    }

    func testSetCodeExecutionEnabledPreservesProviderConfiguration() {
        let original = GenerationControls(
            codeExecution: CodeExecutionControls(
                enabled: true,
                openAI: OpenAICodeExecutionOptions(
                    container: CodeExecutionContainer(
                        type: "auto",
                        memoryLimit: "4g",
                        fileIDs: ["file-a"]
                    )
                ),
                anthropic: AnthropicCodeExecutionOptions(containerID: "container-abc")
            )
        )

        let disabled = ChatAuxiliaryControlSupport.setCodeExecutionEnabled(
            false,
            controls: original
        )

        XCTAssertEqual(disabled.codeExecution?.enabled, false)
        XCTAssertEqual(disabled.codeExecution?.openAI?.container?.type, "auto")
        XCTAssertEqual(disabled.codeExecution?.openAI?.container?.memoryLimit, "4g")
        XCTAssertEqual(disabled.codeExecution?.openAI?.container?.fileIDs, ["file-a"])
        XCTAssertEqual(disabled.codeExecution?.anthropic?.containerID, "container-abc")
    }

    func testMCPToolsPresentationMatchesSupportEnabledAndSelectionCount() {
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.mcpToolsHelpText(
                supportsMCPToolsControl: false,
                isMCPToolsEnabled: true,
                selectedServerCount: 2
            ),
            "MCP Tools: Not supported"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.mcpToolsHelpText(
                supportsMCPToolsControl: true,
                isMCPToolsEnabled: false,
                selectedServerCount: 2
            ),
            "MCP Tools: Off"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.mcpToolsHelpText(
                supportsMCPToolsControl: true,
                isMCPToolsEnabled: true,
                selectedServerCount: 0
            ),
            "MCP Tools: On (no servers)"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.mcpToolsHelpText(
                supportsMCPToolsControl: true,
                isMCPToolsEnabled: true,
                selectedServerCount: 1
            ),
            "MCP Tools: On (1 server)"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.mcpToolsHelpText(
                supportsMCPToolsControl: true,
                isMCPToolsEnabled: true,
                selectedServerCount: 3
            ),
            "MCP Tools: On (3 servers)"
        )

        XCTAssertNil(
            ChatAuxiliaryControlSupport.mcpToolsBadgeText(
                supportsMCPToolsControl: false,
                isMCPToolsEnabled: true,
                selectedServerCount: 1
            )
        )
        XCTAssertNil(
            ChatAuxiliaryControlSupport.mcpToolsBadgeText(
                supportsMCPToolsControl: true,
                isMCPToolsEnabled: false,
                selectedServerCount: 1
            )
        )
        XCTAssertNil(
            ChatAuxiliaryControlSupport.mcpToolsBadgeText(
                supportsMCPToolsControl: true,
                isMCPToolsEnabled: true,
                selectedServerCount: 0
            )
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.mcpToolsBadgeText(
                supportsMCPToolsControl: true,
                isMCPToolsEnabled: true,
                selectedServerCount: 3
            ),
            "3"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.mcpToolsBadgeText(
                supportsMCPToolsControl: true,
                isMCPToolsEnabled: true,
                selectedServerCount: 100
            ),
            "99+"
        )
    }

    func testSetMCPToolsEnabledCreatesControlsAndPreservesSelection() {
        let createdDisabled = ChatAuxiliaryControlSupport.setMCPToolsEnabled(
            false,
            controls: GenerationControls()
        )
        XCTAssertEqual(createdDisabled.mcpTools?.enabled, false)
        XCTAssertNil(createdDisabled.mcpTools?.enabledServerIDs)
        XCTAssertFalse(ChatAuxiliaryControlSupport.mcpToolsEnabledValue(controls: createdDisabled))
        XCTAssertFalse(ChatAuxiliaryControlSupport.usesCustomMCPServerSelection(controls: createdDisabled))

        var controls = GenerationControls(
            mcpTools: MCPToolsControls(enabled: false, enabledServerIDs: ["beta", "alpha"])
        )
        controls = ChatAuxiliaryControlSupport.setMCPToolsEnabled(true, controls: controls)
        XCTAssertEqual(controls.mcpTools?.enabled, true)
        XCTAssertEqual(controls.mcpTools?.enabledServerIDs, ["beta", "alpha"])
        XCTAssertTrue(ChatAuxiliaryControlSupport.mcpToolsEnabledValue(controls: controls))
        XCTAssertTrue(ChatAuxiliaryControlSupport.usesCustomMCPServerSelection(controls: controls))

        controls = ChatAuxiliaryControlSupport.setMCPToolsEnabled(false, controls: controls)
        XCTAssertEqual(controls.mcpTools?.enabled, false)
        XCTAssertEqual(controls.mcpTools?.enabledServerIDs, ["beta", "alpha"])
        XCTAssertFalse(ChatAuxiliaryControlSupport.mcpToolsEnabledValue(controls: controls))
        XCTAssertTrue(ChatAuxiliaryControlSupport.usesCustomMCPServerSelection(controls: controls))
    }

    func testBuiltinSearchIncludeRawValueDefaultsFalseAndStoresTrueOnly() {
        let defaults = GenerationControls()
        XCTAssertFalse(ChatAuxiliaryControlSupport.builtinSearchIncludeRawValue(controls: defaults))

        let enabled = ChatAuxiliaryControlSupport.setBuiltinSearchIncludeRaw(
            true,
            controls: defaults
        )
        XCTAssertEqual(enabled.searchPlugin?.includeRawContent, true)

        let disabled = ChatAuxiliaryControlSupport.setBuiltinSearchIncludeRaw(
            false,
            controls: enabled
        )
        XCTAssertNil(disabled.searchPlugin?.includeRawContent)
    }

    func testBuiltinSearchFetchPageValueFallsBackToSettingsAndStoresExplicitValue() {
        let settings = makeWebSearchPluginSettings(jinaReadPages: true)

        let defaults = GenerationControls()
        XCTAssertTrue(
            ChatAuxiliaryControlSupport.builtinSearchFetchPageValue(
                controls: defaults,
                settings: settings
            )
        )

        let disabled = ChatAuxiliaryControlSupport.setBuiltinSearchFetchPage(
            false,
            controls: defaults
        )
        XCTAssertFalse(
            ChatAuxiliaryControlSupport.builtinSearchFetchPageValue(
                controls: disabled,
                settings: settings
            )
        )
        XCTAssertEqual(disabled.searchPlugin?.fetchPageContent, false)
    }

    func testBuiltinSearchFirecrawlExtractValueFallsBackToSettingsAndStoresExplicitValue() {
        let settings = makeWebSearchPluginSettings(firecrawlExtractContent: true)

        let defaults = GenerationControls()
        XCTAssertTrue(
            ChatAuxiliaryControlSupport.builtinSearchFirecrawlExtractValue(
                controls: defaults,
                settings: settings
            )
        )

        let disabled = ChatAuxiliaryControlSupport.setBuiltinSearchFirecrawlExtract(
            false,
            controls: defaults
        )
        XCTAssertFalse(
            ChatAuxiliaryControlSupport.builtinSearchFirecrawlExtractValue(
                controls: disabled,
                settings: settings
            )
        )
        XCTAssertEqual(disabled.searchPlugin?.firecrawlExtractContent, false)
    }

    func testBuiltinSearchMenuValuesFallBackToSettingsAndStoredControls() {
        let settings = makeWebSearchPluginSettings()

        XCTAssertEqual(
            ChatAuxiliaryControlSupport.builtinSearchMaxResultsValue(
                controls: GenerationControls(),
                settings: settings
            ),
            8
        )
        XCTAssertNil(
            ChatAuxiliaryControlSupport.builtinSearchRecencyDaysValue(
                controls: GenerationControls()
            )
        )

        let controls = GenerationControls(
            searchPlugin: SearchPluginControls(
                maxResults: 12,
                recencyDays: 30
            )
        )

        XCTAssertEqual(
            ChatAuxiliaryControlSupport.builtinSearchMaxResultsValue(
                controls: controls,
                settings: settings
            ),
            12
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.builtinSearchRecencyDaysValue(
                controls: controls
            ),
            30
        )
    }

    func testSearchPluginMutatorsCreateControlsAndPreserveExistingFields() {
        var controls = GenerationControls()

        controls = ChatAuxiliaryControlSupport.setSearchPluginProvider(.brave, controls: controls)
        XCTAssertEqual(controls.searchPlugin?.provider, .brave)

        controls = ChatAuxiliaryControlSupport.setSearchPluginMaxResults(9, controls: controls)
        XCTAssertEqual(controls.searchPlugin?.provider, .brave)
        XCTAssertEqual(controls.searchPlugin?.maxResults, 9)

        controls = ChatAuxiliaryControlSupport.setSearchPluginRecencyDays(7, controls: controls)
        XCTAssertEqual(controls.searchPlugin?.provider, .brave)
        XCTAssertEqual(controls.searchPlugin?.maxResults, 9)
        XCTAssertEqual(controls.searchPlugin?.recencyDays, 7)

        controls = ChatAuxiliaryControlSupport.setSearchEnginePreference(
            useJinSearch: true,
            controls: controls
        )
        XCTAssertEqual(controls.searchPlugin?.provider, .brave)
        XCTAssertEqual(controls.searchPlugin?.maxResults, 9)
        XCTAssertEqual(controls.searchPlugin?.recencyDays, 7)
        XCTAssertEqual(controls.searchPlugin?.preferJinSearch, true)

        controls = ChatAuxiliaryControlSupport.setSearchPluginRecencyDays(nil, controls: controls)
        XCTAssertNil(controls.searchPlugin?.recencyDays)
        XCTAssertEqual(controls.searchPlugin?.provider, .brave)
        XCTAssertEqual(controls.searchPlugin?.maxResults, 9)
        XCTAssertEqual(controls.searchPlugin?.preferJinSearch, true)
    }

    func testSetWebSearchSourceUpdatesExistingSourcesInStableOrder() {
        var controls = GenerationControls(webSearch: WebSearchControls(enabled: true, sources: [.x]))

        controls = ChatAuxiliaryControlSupport.setWebSearchSource(
            .web,
            isOn: true,
            controls: controls
        )

        XCTAssertEqual(controls.webSearch?.sources, [.web, .x])
        XCTAssertTrue(ChatAuxiliaryControlSupport.webSearchSourceIsSelected(.web, controls: controls))
        XCTAssertTrue(ChatAuxiliaryControlSupport.webSearchSourceIsSelected(.x, controls: controls))

        controls = ChatAuxiliaryControlSupport.setWebSearchSource(
            .x,
            isOn: false,
            controls: controls
        )

        XCTAssertEqual(controls.webSearch?.sources, [.web])
        XCTAssertFalse(ChatAuxiliaryControlSupport.webSearchSourceIsSelected(.x, controls: controls))
    }

    func testSetWebSearchSourceLeavesMissingWebSearchControlsMissing() {
        let controls = ChatAuxiliaryControlSupport.setWebSearchSource(
            .web,
            isOn: true,
            controls: GenerationControls()
        )

        XCTAssertNil(controls.webSearch)
    }

    func testWebSearchEnabledMutatorCreatesProviderDefaultsAndNormalizesExistingControls() {
        XCTAssertTrue(
            ChatAuxiliaryControlSupport.webSearchEnabledValue(
                providerType: .perplexity,
                controls: GenerationControls()
            )
        )
        XCTAssertFalse(
            ChatAuxiliaryControlSupport.webSearchEnabledValue(
                providerType: .openai,
                controls: GenerationControls()
            )
        )

        let created = ChatAuxiliaryControlSupport.setWebSearchEnabled(
            true,
            controls: GenerationControls(),
            providerType: .xai
        )
        XCTAssertEqual(created.webSearch?.enabled, true)
        XCTAssertEqual(created.webSearch?.sources, [.web, .x])

        var existing = GenerationControls(webSearch: WebSearchControls(enabled: false, contextSize: nil, sources: [.x]))
        existing = ChatAuxiliaryControlSupport.setWebSearchEnabled(
            true,
            controls: existing,
            providerType: .openai
        )
        XCTAssertEqual(existing.webSearch?.enabled, true)
        XCTAssertEqual(existing.webSearch?.contextSize, .medium)
        XCTAssertNil(existing.webSearch?.sources)

        let disabled = ChatAuxiliaryControlSupport.setWebSearchEnabled(
            false,
            controls: existing,
            providerType: .openai
        )
        XCTAssertEqual(disabled.webSearch?.enabled, false)
        XCTAssertEqual(disabled.webSearch?.contextSize, .medium)
    }

    func testWebSearchProviderSpecificMutatorsPreserveOptionalChainingBehavior() {
        let missingControls = GenerationControls()
        XCTAssertNil(
            ChatAuxiliaryControlSupport.setAnthropicDynamicFiltering(
                true,
                controls: missingControls
            ).webSearch
        )
        XCTAssertNil(
            ChatAuxiliaryControlSupport.setExistingWebSearchContextSize(
                .high,
                controls: missingControls
            ).webSearch
        )
        XCTAssertNil(
            ChatAuxiliaryControlSupport.setAnthropicWebSearchMaxUses(
                5,
                controls: missingControls
            ).webSearch
        )

        var controls = GenerationControls(webSearch: WebSearchControls(enabled: true))
        XCTAssertFalse(ChatAuxiliaryControlSupport.anthropicDynamicFilteringValue(controls: controls))
        XCTAssertEqual(ChatAuxiliaryControlSupport.openAIWebSearchContextSizeValue(controls: controls), .medium)
        XCTAssertEqual(ChatAuxiliaryControlSupport.perplexityWebSearchContextSizeValue(controls: controls), .low)
        XCTAssertTrue(ChatAuxiliaryControlSupport.xaiWebSearchSourcesAreEmpty(controls: controls))
        XCTAssertNil(ChatAuxiliaryControlSupport.anthropicWebSearchMaxUsesValue(controls: controls))

        controls = ChatAuxiliaryControlSupport.setAnthropicDynamicFiltering(true, controls: controls)
        XCTAssertTrue(ChatAuxiliaryControlSupport.anthropicDynamicFilteringValue(controls: controls))
        XCTAssertEqual(controls.webSearch?.dynamicFiltering, true)
        controls = ChatAuxiliaryControlSupport.setAnthropicDynamicFiltering(false, controls: controls)
        XCTAssertFalse(ChatAuxiliaryControlSupport.anthropicDynamicFilteringValue(controls: controls))
        XCTAssertNil(controls.webSearch?.dynamicFiltering)

        controls = ChatAuxiliaryControlSupport.setExistingWebSearchContextSize(.high, controls: controls)
        XCTAssertEqual(ChatAuxiliaryControlSupport.openAIWebSearchContextSizeValue(controls: controls), .high)
        XCTAssertEqual(ChatAuxiliaryControlSupport.perplexityWebSearchContextSizeValue(controls: controls), .high)
        XCTAssertEqual(controls.webSearch?.contextSize, .high)

        controls = ChatAuxiliaryControlSupport.setWebSearchSource(.web, isOn: true, controls: controls)
        XCTAssertFalse(ChatAuxiliaryControlSupport.xaiWebSearchSourcesAreEmpty(controls: controls))

        controls = ChatAuxiliaryControlSupport.setAnthropicWebSearchMaxUses(4, controls: controls)
        XCTAssertEqual(ChatAuxiliaryControlSupport.anthropicWebSearchMaxUsesValue(controls: controls), 4)
        XCTAssertEqual(controls.webSearch?.maxUses, 4)
    }

    func testPerplexityContextSizeMutatorCreatesEnabledWebSearchWhenMissing() {
        let controls = ChatAuxiliaryControlSupport.setPerplexityWebSearchContextSize(
            .high,
            controls: GenerationControls(),
            providerType: .perplexity
        )

        XCTAssertEqual(controls.webSearch?.enabled, true)
        XCTAssertEqual(controls.webSearch?.contextSize, .high)
        XCTAssertNil(controls.webSearch?.sources)
    }

    func testIsWebSearchEnabledMatchesSupportAndProviderDefaults() {
        XCTAssertFalse(
            ChatAuxiliaryControlSupport.isWebSearchEnabled(
                supportsWebSearchControl: false,
                providerType: .perplexity,
                controls: GenerationControls()
            )
        )
        XCTAssertTrue(
            ChatAuxiliaryControlSupport.isWebSearchEnabled(
                supportsWebSearchControl: true,
                providerType: .perplexity,
                controls: GenerationControls()
            )
        )
        XCTAssertFalse(
            ChatAuxiliaryControlSupport.isWebSearchEnabled(
                supportsWebSearchControl: true,
                providerType: .openai,
                controls: GenerationControls()
            )
        )
        XCTAssertTrue(
            ChatAuxiliaryControlSupport.isWebSearchEnabled(
                supportsWebSearchControl: true,
                providerType: .xai,
                controls: GenerationControls(webSearch: WebSearchControls(enabled: true))
            )
        )
    }

    func testNativeWebSearchSupportHonorsManagedCodexAndMediaGenerationGates() {
        XCTAssertFalse(
            ChatAuxiliaryControlSupport.supportsNativeWebSearchControl(
                hidesManagedAgentInternalUI: true,
                providerType: .openai,
                supportsMediaGenerationControl: false,
                supportsImageGenerationControl: false,
                supportsImageGenerationWebSearch: false,
                modelSupportsWebSearch: true
            )
        )
        XCTAssertTrue(
            ChatAuxiliaryControlSupport.supportsNativeWebSearchControl(
                hidesManagedAgentInternalUI: false,
                providerType: .openai,
                supportsMediaGenerationControl: false,
                supportsImageGenerationControl: false,
                supportsImageGenerationWebSearch: false,
                modelSupportsWebSearch: true
            )
        )
        XCTAssertFalse(
            ChatAuxiliaryControlSupport.supportsNativeWebSearchControl(
                hidesManagedAgentInternalUI: false,
                providerType: .openai,
                supportsMediaGenerationControl: true,
                supportsImageGenerationControl: false,
                supportsImageGenerationWebSearch: true,
                modelSupportsWebSearch: true
            )
        )
        XCTAssertTrue(
            ChatAuxiliaryControlSupport.supportsNativeWebSearchControl(
                hidesManagedAgentInternalUI: false,
                providerType: .openai,
                supportsMediaGenerationControl: true,
                supportsImageGenerationControl: true,
                supportsImageGenerationWebSearch: true,
                modelSupportsWebSearch: false
            )
        )
    }

    func testBuiltinSearchSupportAndEngineSelectionMatchConfigurationGates() {
        XCTAssertFalse(
            ChatAuxiliaryControlSupport.modelSupportsBuiltinSearchPluginControl(
                hidesManagedAgentInternalUI: true,
                providerType: .openai,
                supportsMediaGenerationControl: false,
                modelSupportsToolCalling: true
            )
        )
        XCTAssertFalse(
            ChatAuxiliaryControlSupport.modelSupportsBuiltinSearchPluginControl(
                hidesManagedAgentInternalUI: false,
                providerType: .openai,
                supportsMediaGenerationControl: true,
                modelSupportsToolCalling: true
            )
        )
        XCTAssertTrue(
            ChatAuxiliaryControlSupport.modelSupportsBuiltinSearchPluginControl(
                hidesManagedAgentInternalUI: false,
                providerType: .openai,
                supportsMediaGenerationControl: false,
                modelSupportsToolCalling: true
            )
        )

        XCTAssertFalse(
            ChatAuxiliaryControlSupport.supportsBuiltinSearchPluginControl(
                modelSupportsBuiltinSearchPluginControl: true,
                webSearchPluginEnabled: true,
                webSearchPluginConfigured: false
            )
        )
        XCTAssertTrue(
            ChatAuxiliaryControlSupport.supportsBuiltinSearchPluginControl(
                modelSupportsBuiltinSearchPluginControl: true,
                webSearchPluginEnabled: true,
                webSearchPluginConfigured: true
            )
        )
        XCTAssertTrue(
            ChatAuxiliaryControlSupport.supportsSearchEngineModeSwitch(
                supportsNativeWebSearchControl: true,
                supportsBuiltinSearchPluginControl: true
            )
        )
        XCTAssertFalse(
            ChatAuxiliaryControlSupport.usesBuiltinSearchPlugin(
                supportsNativeWebSearchControl: true,
                supportsBuiltinSearchPluginControl: true,
                prefersJinSearchEngine: false
            )
        )
        XCTAssertTrue(
            ChatAuxiliaryControlSupport.usesBuiltinSearchPlugin(
                supportsNativeWebSearchControl: true,
                supportsBuiltinSearchPluginControl: true,
                prefersJinSearchEngine: true
            )
        )
        XCTAssertTrue(
            ChatAuxiliaryControlSupport.usesBuiltinSearchPlugin(
                supportsNativeWebSearchControl: false,
                supportsBuiltinSearchPluginControl: true,
                prefersJinSearchEngine: false
            )
        )
    }

    func testWebSearchPresentationMatchesSupportAndEnabledState() {
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchHelpText(
                supportsWebSearchControl: false,
                isWebSearchEnabled: true,
                label: "High"
            ),
            "Web Search: Not supported"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchHelpText(
                supportsWebSearchControl: true,
                isWebSearchEnabled: false,
                label: "High"
            ),
            "Web Search: Off"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchHelpText(
                supportsWebSearchControl: true,
                isWebSearchEnabled: true,
                label: "High"
            ),
            "Web Search: High"
        )

        let controls = GenerationControls(webSearch: WebSearchControls(enabled: true, contextSize: .high))
        XCTAssertNil(
            ChatAuxiliaryControlSupport.webSearchBadgeText(
                supportsWebSearchControl: false,
                isWebSearchEnabled: true,
                providerType: .openai,
                controls: controls,
                usesBuiltinSearchPlugin: false,
                searchPluginProvider: .exa
            )
        )
        XCTAssertNil(
            ChatAuxiliaryControlSupport.webSearchBadgeText(
                supportsWebSearchControl: true,
                isWebSearchEnabled: false,
                providerType: .openai,
                controls: controls,
                usesBuiltinSearchPlugin: false,
                searchPluginProvider: .exa
            )
        )
    }

    func testNativeWebSearchLabelsAndBadgesMatchProviderDefaults() {
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchLabel(
                providerType: .openai,
                controls: GenerationControls(),
                usesBuiltinSearchPlugin: false,
                searchPluginProvider: .exa
            ),
            "Medium"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchBadgeText(
                supportsWebSearchControl: true,
                isWebSearchEnabled: true,
                providerType: .openai,
                controls: GenerationControls(),
                usesBuiltinSearchPlugin: false,
                searchPluginProvider: .exa
            ),
            "M"
        )

        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchLabel(
                providerType: .perplexity,
                controls: GenerationControls(),
                usesBuiltinSearchPlugin: false,
                searchPluginProvider: .exa
            ),
            "Low"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchBadgeText(
                supportsWebSearchControl: true,
                isWebSearchEnabled: true,
                providerType: .perplexity,
                controls: GenerationControls(),
                usesBuiltinSearchPlugin: false,
                searchPluginProvider: .exa
            ),
            "M"
        )

        let high = GenerationControls(webSearch: WebSearchControls(enabled: true, contextSize: .high))
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchLabel(
                providerType: .perplexity,
                controls: high,
                usesBuiltinSearchPlugin: false,
                searchPluginProvider: .exa
            ),
            "High"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchBadgeText(
                supportsWebSearchControl: true,
                isWebSearchEnabled: true,
                providerType: .perplexity,
                controls: high,
                usesBuiltinSearchPlugin: false,
                searchPluginProvider: .exa
            ),
            "H"
        )

        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchLabel(
                providerType: .anthropic,
                controls: GenerationControls(),
                usesBuiltinSearchPlugin: false,
                searchPluginProvider: .exa
            ),
            "On"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchBadgeText(
                supportsWebSearchControl: true,
                isWebSearchEnabled: true,
                providerType: .anthropic,
                controls: GenerationControls(),
                usesBuiltinSearchPlugin: false,
                searchPluginProvider: .exa
            ),
            "On"
        )
    }

    func testXAIWebSearchSourceLabelsAndBadgesMatchSelectedSources() {
        let none = GenerationControls(webSearch: WebSearchControls(enabled: true))
        XCTAssertEqual(ChatAuxiliaryControlSupport.webSearchSourcesLabel(controls: none), "On")
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchBadgeText(
                supportsWebSearchControl: true,
                isWebSearchEnabled: true,
                providerType: .xai,
                controls: none,
                usesBuiltinSearchPlugin: false,
                searchPluginProvider: .exa
            ),
            "On"
        )

        let web = GenerationControls(webSearch: WebSearchControls(enabled: true, sources: [.web]))
        XCTAssertEqual(ChatAuxiliaryControlSupport.webSearchSourcesLabel(controls: web), "Web")
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchBadgeText(
                supportsWebSearchControl: true,
                isWebSearchEnabled: true,
                providerType: .xai,
                controls: web,
                usesBuiltinSearchPlugin: false,
                searchPluginProvider: .exa
            ),
            "W"
        )

        let x = GenerationControls(webSearch: WebSearchControls(enabled: true, sources: [.x]))
        XCTAssertEqual(ChatAuxiliaryControlSupport.webSearchSourcesLabel(controls: x), "X")
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchBadgeText(
                supportsWebSearchControl: true,
                isWebSearchEnabled: true,
                providerType: .xai,
                controls: x,
                usesBuiltinSearchPlugin: false,
                searchPluginProvider: .exa
            ),
            "X"
        )

        let both = GenerationControls(webSearch: WebSearchControls(enabled: true, sources: [.web, .x]))
        XCTAssertEqual(ChatAuxiliaryControlSupport.webSearchSourcesLabel(controls: both), "Web + X")
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchLabel(
                providerType: .xai,
                controls: both,
                usesBuiltinSearchPlugin: false,
                searchPluginProvider: .exa
            ),
            "Web + X"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchBadgeText(
                supportsWebSearchControl: true,
                isWebSearchEnabled: true,
                providerType: .xai,
                controls: both,
                usesBuiltinSearchPlugin: false,
                searchPluginProvider: .exa
            ),
            "W+X"
        )
    }

    func testBuiltinSearchPluginPresentationUsesProviderAndMaxResults() {
        let controls = GenerationControls(searchPlugin: SearchPluginControls(maxResults: 7))
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchLabel(
                providerType: .openai,
                controls: controls,
                usesBuiltinSearchPlugin: true,
                searchPluginProvider: .brave
            ),
            "Brave Search \u{00B7} 7 results"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchBadgeText(
                supportsWebSearchControl: true,
                isWebSearchEnabled: true,
                providerType: .openai,
                controls: controls,
                usesBuiltinSearchPlugin: true,
                searchPluginProvider: .brave
            ),
            "BR"
        )

        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchLabel(
                providerType: .openai,
                controls: GenerationControls(),
                usesBuiltinSearchPlugin: true,
                searchPluginProvider: .firecrawl
            ),
            "Firecrawl"
        )
        XCTAssertEqual(
            ChatAuxiliaryControlSupport.webSearchBadgeText(
                supportsWebSearchControl: true,
                isWebSearchEnabled: true,
                providerType: .openai,
                controls: GenerationControls(),
                usesBuiltinSearchPlugin: true,
                searchPluginProvider: .firecrawl
            ),
            "FC"
        )
    }

    func testPrepareGoogleMapsEditorDraftPreservesSavedFields() {
        let current = GoogleMapsControls(
            enabled: true,
            enableWidget: true,
            latitude: 35.6764,
            longitude: 139.65,
            languageCode: "ja_JP"
        )

        let prepared = ChatAuxiliaryControlSupport.prepareGoogleMapsEditorDraft(
            current: current,
            isEnabled: false
        )

        XCTAssertEqual(prepared.draft.enabled, true)
        XCTAssertEqual(prepared.latitudeDraft, "35.6764")
        XCTAssertEqual(prepared.longitudeDraft, "139.65")
        XCTAssertEqual(prepared.languageCodeDraft, "ja_JP")
    }

    func testClearGoogleMapsLocationClearsCoordinatesOnly() {
        let controls = ChatAuxiliaryControlSupport.clearGoogleMapsLocation(
            controls: GenerationControls(
                googleMaps: GoogleMapsControls(
                    enabled: true,
                    enableWidget: true,
                    latitude: 35.6764,
                    longitude: 139.65,
                    languageCode: "ja_JP"
                )
            )
        )

        XCTAssertEqual(controls.googleMaps?.enabled, true)
        XCTAssertEqual(controls.googleMaps?.enableWidget, true)
        XCTAssertNil(controls.googleMaps?.latitude)
        XCTAssertNil(controls.googleMaps?.longitude)
        XCTAssertEqual(controls.googleMaps?.languageCode, "ja_JP")
        XCTAssertEqual(controls.googleMaps?.hasLocation, false)
    }

    func testSetGoogleMapsEnabledCreatesNormalizesAndPreservesExistingFields() {
        let enabled = ChatAuxiliaryControlSupport.setGoogleMapsEnabled(
            true,
            controls: GenerationControls()
        )
        XCTAssertEqual(enabled.googleMaps?.enabled, true)
        XCTAssertNil(enabled.googleMaps?.enableWidget)
        XCTAssertNil(enabled.googleMaps?.latitude)
        XCTAssertNil(enabled.googleMaps?.longitude)
        XCTAssertNil(enabled.googleMaps?.languageCode)

        let disabledEmpty = ChatAuxiliaryControlSupport.setGoogleMapsEnabled(
            false,
            controls: enabled
        )
        XCTAssertNil(disabledEmpty.googleMaps)

        let configured = ChatAuxiliaryControlSupport.setGoogleMapsEnabled(
            false,
            controls: GenerationControls(
                googleMaps: GoogleMapsControls(
                    enabled: true,
                    enableWidget: true,
                    latitude: 35.6764,
                    longitude: 139.65,
                    languageCode: "ja_JP"
                )
            )
        )
        XCTAssertEqual(configured.googleMaps?.enabled, false)
        XCTAssertEqual(configured.googleMaps?.enableWidget, true)
        XCTAssertEqual(configured.googleMaps?.latitude, 35.6764)
        XCTAssertEqual(configured.googleMaps?.longitude, 139.65)
        XCTAssertEqual(configured.googleMaps?.languageCode, "ja_JP")
    }

    func testApplyGoogleMapsDraftRequiresBothCoordinates() {
        let result = ChatAuxiliaryControlSupport.applyGoogleMapsDraft(
            draft: GoogleMapsControls(enabled: true),
            latitudeDraft: "35.0",
            longitudeDraft: "",
            languageCodeDraft: "",
            providerType: .gemini
        )

        switch result {
        case .success:
            XCTFail("Expected validation failure")
        case .failure(let error):
            XCTAssertEqual(error.localizedDescription, "Enter both latitude and longitude, or leave both empty.")
        }
    }

    func testApplyGoogleMapsDraftClearsUnsupportedLocaleOutsideVertex() throws {
        let result = try XCTUnwrap(
            try? ChatAuxiliaryControlSupport.applyGoogleMapsDraft(
                draft: GoogleMapsControls(enabled: true, languageCode: "ja_JP"),
                latitudeDraft: "",
                longitudeDraft: "",
                languageCodeDraft: "ja_JP",
                providerType: .gemini
            ).get()
        )

        XCTAssertTrue(result.enabled)
        XCTAssertNil(result.languageCode)
    }

    func testApplyGoogleMapsDraftKeepsVertexLocaleAndNormalizesEmptyState() throws {
        let configured = try XCTUnwrap(
            try? ChatAuxiliaryControlSupport.applyGoogleMapsDraft(
                draft: GoogleMapsControls(enabled: true),
                latitudeDraft: " 34.050481\n",
                longitudeDraft: "\t-118.248526 ",
                languageCodeDraft: " en_US\n",
                providerType: .vertexai
            ).get()
        )

        XCTAssertEqual(configured.latitude, 34.050481)
        XCTAssertEqual(configured.longitude, -118.248526)
        XCTAssertEqual(configured.languageCode, "en_US")

        let empty = try? ChatAuxiliaryControlSupport.applyGoogleMapsDraft(
            draft: GoogleMapsControls(enabled: false),
            latitudeDraft: "",
            longitudeDraft: "",
            languageCodeDraft: "",
            providerType: .vertexai
        ).get()

        XCTAssertNil(empty)
    }

    func testApplyGoogleMapsDraftWritesNormalizedResultIntoGenerationControls() throws {
        let controls = GenerationControls(
            temperature: 0.2,
            googleMaps: GoogleMapsControls(enabled: false)
        )

        let applied = try ChatAuxiliaryControlSupport.applyGoogleMapsDraft(
            draft: GoogleMapsControls(enabled: true, enableWidget: false),
            latitudeDraft: "34.050481",
            longitudeDraft: "-118.248526",
            languageCodeDraft: "en_US",
            providerType: .vertexai,
            controls: controls
        ).get()

        XCTAssertEqual(applied.controls.temperature, 0.2)
        XCTAssertEqual(applied.googleMaps?.enabled, true)
        XCTAssertNil(applied.googleMaps?.enableWidget)
        XCTAssertEqual(applied.googleMaps?.latitude, 34.050481)
        XCTAssertEqual(applied.googleMaps?.longitude, -118.248526)
        XCTAssertEqual(applied.googleMaps?.languageCode, "en_US")
        XCTAssertEqual(applied.controls.googleMaps?.latitude, 34.050481)
        XCTAssertEqual(applied.controls.googleMaps?.longitude, -118.248526)
    }

    func testApplyGoogleMapsDraftWithGenerationControlsPropagatesValidationFailure() {
        let result = ChatAuxiliaryControlSupport.applyGoogleMapsDraft(
            draft: GoogleMapsControls(enabled: true),
            latitudeDraft: "34.050481",
            longitudeDraft: "",
            languageCodeDraft: "",
            providerType: .vertexai,
            controls: GenerationControls(
                googleMaps: GoogleMapsControls(enabled: true, latitude: 10, longitude: 20)
            )
        )

        switch result {
        case .success:
            XCTFail("Expected validation failure")
        case .failure(let error):
            XCTAssertEqual(error.localizedDescription, "Enter both latitude and longitude, or leave both empty.")
        }
    }

    func testResolvedMCPServerConfigsUsesPerMessageOverrideWhenConversationMCPDisabled() throws {
        var controls = GenerationControls()
        controls.mcpTools = MCPToolsControls(enabled: false, enabledServerIDs: nil)

        let configs = try ChatAuxiliaryControlSupport.resolvedMCPServerConfigs(
            controls: controls,
            supportsMCPToolsControl: true,
            servers: [makeServer(id: "alpha"), makeServer(id: "beta")],
            perMessageOverrideServerIDs: ["beta"]
        )

        XCTAssertEqual(configs.map(\.id), ["beta"])
    }

    func testEligibleMCPServersFiltersAutomaticEnabledServersAndSortsByName() {
        let servers = [
            makeServer(id: "zeta", name: "Zeta"),
            makeServer(id: "disabled", name: "Alpha", isEnabled: false),
            makeServer(id: "manual", name: "Beta", runToolsAutomatically: false),
            makeServer(id: "alpha", name: "alpha")
        ]

        let eligible = ChatAuxiliaryControlSupport.eligibleMCPServers(from: servers)

        XCTAssertEqual(eligible.map(\.id), ["alpha", "zeta"])
    }

    func testResolvedMCPServerConfigsFiltersPerMessageOverrideToEligibleServers() throws {
        let controls = GenerationControls(mcpTools: MCPToolsControls(enabled: true, enabledServerIDs: nil))
        let servers = [
            makeServer(id: "alpha"),
            makeServer(id: "beta", isEnabled: false),
            makeServer(id: "gamma", runToolsAutomatically: false)
        ]

        let configs = try ChatAuxiliaryControlSupport.resolvedMCPServerConfigs(
            controls: controls,
            supportsMCPToolsControl: true,
            servers: servers,
            perMessageOverrideServerIDs: ["alpha", "beta", "gamma", "missing"]
        )

        XCTAssertEqual(configs.map(\.id), ["alpha"])
    }

    func testResolvedMCPServerConfigsIgnoresPerMessageOverrideWhenMCPUnsupported() throws {
        let controls = GenerationControls(mcpTools: MCPToolsControls(enabled: true, enabledServerIDs: nil))

        let configs = try ChatAuxiliaryControlSupport.resolvedMCPServerConfigs(
            controls: controls,
            supportsMCPToolsControl: false,
            servers: [makeServer(id: "alpha")],
            perMessageOverrideServerIDs: ["alpha"]
        )

        XCTAssertTrue(configs.isEmpty)
    }

    private func makeServer(
        id: String,
        name: String? = nil,
        isEnabled: Bool = true,
        runToolsAutomatically: Bool = true
    ) -> MCPServerConfigEntity {
        let transport: MCPTransportConfig = .stdio(
            MCPStdioTransportConfig(command: "npx", args: ["-y", "mock-mcp-server"])
        )

        return MCPServerConfigEntity(
            id: id,
            name: name ?? id.capitalized,
            transportKindRaw: transport.kind.rawValue,
            transportData: try! JSONEncoder().encode(transport),
            lifecycleRaw: MCPLifecyclePolicy.persistent.rawValue,
            isEnabled: isEnabled,
            runToolsAutomatically: runToolsAutomatically,
            isLongRunning: true
        )
    }

    private func makeWebSearchPluginSettings(
        jinaReadPages: Bool = true,
        firecrawlExtractContent: Bool = true
    ) -> WebSearchPluginSettings {
        WebSearchPluginSettings(
            isEnabled: true,
            defaultProvider: .exa,
            defaultMaxResults: 8,
            defaultRecencyDays: nil,
            exaAPIKey: "",
            braveAPIKey: "",
            jinaAPIKey: "",
            firecrawlAPIKey: "",
            exaSearchType: nil,
            exaCategory: nil,
            exaUserLocation: nil,
            exaModeration: false,
            braveCountry: nil,
            braveLanguage: nil,
            braveSafesearch: nil,
            jinaReadPages: jinaReadPages,
            jinaCountry: nil,
            jinaLocale: nil,
            firecrawlExtractContent: firecrawlExtractContent,
            firecrawlCountry: nil,
            firecrawlLanguage: nil,
            firecrawlSources: [],
            tavilyAPIKey: "",
            perplexityAPIKey: "",
            tavilySearchDepth: nil,
            tavilyTopic: nil,
            tavilyCountry: nil,
            tavilyAutoParameters: false,
            perplexityCountry: nil,
            perplexityLanguage: nil
        )
    }
}
