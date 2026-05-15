import XCTest
@testable import Jin

final class ProviderFormSupportTests: XCTestCase {
    func testCredentialKindClassifiesProviderAuthenticationRequirements() {
        XCTAssertEqual(ProviderFormSupport.credentialKind(for: .openai), .apiKey)
        XCTAssertEqual(ProviderFormSupport.credentialKind(for: .githubCopilot), .apiKey)
        XCTAssertEqual(ProviderFormSupport.credentialKind(for: .claudeManagedAgents), .apiKey)
        XCTAssertEqual(ProviderFormSupport.credentialKind(for: .vertexai), .serviceAccountJSON)
    }

    func testAPIKeyFieldTitleUsesGitHubTokenForCopilotOnly() {
        XCTAssertEqual(ProviderFormSupport.apiKeyFieldTitle(for: .githubCopilot), "GitHub Token")
        XCTAssertEqual(ProviderFormSupport.apiKeyFieldTitle(for: .openai), "API Key")
        XCTAssertEqual(ProviderFormSupport.apiKeyFieldTitle(for: nil), "API Key")
    }

    func testAPIKeyVisibilityHelpUsesGitHubTokenForCopilotOnly() {
        XCTAssertEqual(ProviderFormSupport.apiKeyRevealHelp(for: .githubCopilot), "Show GitHub token")
        XCTAssertEqual(ProviderFormSupport.apiKeyConcealHelp(for: .githubCopilot), "Hide GitHub token")
        XCTAssertEqual(ProviderFormSupport.apiKeyRevealHelp(for: .openai), "Show API key")
        XCTAssertEqual(ProviderFormSupport.apiKeyConcealHelp(for: nil), "Hide API key")
    }

    func testProviderSetupCalloutIsNilForAllProviders() {
        XCTAssertNil(ProviderFormSupport.providerSetupCallout(for: .openai))
    }

    func testProviderDetailsTextUsesProviderSpecificCopy() {
        XCTAssertEqual(
            ProviderFormSupport.providerDetailsText(for: .openaiWebSocket),
            "Keeps a persistent connection to `/v1/responses`. Only one response can be in flight per connection."
        )
        XCTAssertEqual(
            ProviderFormSupport.providerDetailsText(for: .cloudflareAIGateway),
            "Recommended: use a Cloudflare API Token (BYOK mode). Keep the `/compat` base URL, configure upstream provider keys in AI Gateway, then use model IDs like `openai/gpt-5` or `anthropic/claude-sonnet-4.5`."
        )
        XCTAssertEqual(
            ProviderFormSupport.providerDetailsText(for: .zhipuCodingPlan),
            "Use `https://open.bigmodel.cn/api/coding/paas/v4` instead of the generic `/api/paas/v4`. Recommended models: `glm-5`, `glm-4.7`."
        )
        XCTAssertEqual(
            ProviderFormSupport.providerDetailsText(for: .minimax),
            "International endpoint: `https://api.minimax.io/v1`. Recommended models: `MiniMax-M2.7`, `MiniMax-M2.5`."
        )
        XCTAssertEqual(
            ProviderFormSupport.providerDetailsText(for: .minimaxCodingPlan),
            "Uses MiniMax's Anthropic-compatible endpoint: `https://api.minimaxi.com/anthropic/v1`. Supports both pay-as-you-go and Coding Plan API keys."
        )
        XCTAssertEqual(
            ProviderFormSupport.providerDetailsText(for: .mimoTokenPlanOpenAI),
            "Use the OpenAI-compatible Token Plan Base URL from the MiMo subscription page. The Singapore default is `https://token-plan-sgp.xiaomimimo.com/v1`; Token Plan keys start with `tp-`."
        )
        XCTAssertEqual(
            ProviderFormSupport.providerDetailsText(for: .mimoTokenPlanAnthropic),
            "Use the Anthropic-compatible Token Plan Base URL from the MiMo subscription page. Jin accepts Xiaomi's displayed `/anthropic` URL and sends requests to `/anthropic/v1/messages`; Token Plan keys start with `tp-`."
        )
        XCTAssertEqual(
            ProviderFormSupport.providerDetailsText(for: .githubCopilot),
            "Uses GitHub Models at `https://models.github.ai/inference`. Configure a GitHub token with GitHub Models access."
        )
        XCTAssertNil(ProviderFormSupport.providerDetailsText(for: .openai))
    }

    func testNormalizedStringsTrimAndCollapseEmptyValues() {
        XCTAssertEqual(ProviderFormSupport.normalizedOptionalString(" token "), "token")
        XCTAssertNil(ProviderFormSupport.normalizedOptionalString(" "))
        XCTAssertNil(ProviderFormSupport.normalizedOptionalString(nil))
        XCTAssertEqual(ProviderFormSupport.normalizedIconID(" openai "), "openai")
        XCTAssertNil(ProviderFormSupport.normalizedIconID(""))
    }

    func testNormalizedBaseURLExcludesVertexAIAndDropsBlankValues() {
        XCTAssertEqual(
            ProviderFormSupport.normalizedBaseURL(" https://example.com/v1 ", providerType: .openai),
            "https://example.com/v1"
        )
        XCTAssertNil(ProviderFormSupport.normalizedBaseURL(" ", providerType: .openai))
        XCTAssertNil(ProviderFormSupport.normalizedBaseURL("https://example.com", providerType: .vertexai))
    }

    func testBaseURLForEditingFallsBackToDefaultWhenBlank() {
        XCTAssertEqual(
            ProviderFormSupport.baseURLForEditing(" ", defaultBaseURL: "https://api.example.com"),
            "https://api.example.com"
        )
        XCTAssertEqual(
            ProviderFormSupport.baseURLForEditing(" https://custom.example.com ", defaultBaseURL: "https://api.example.com"),
            "https://custom.example.com"
        )
    }

    func testAddDisabledMatchesCredentialRequirements() {
        XCTAssertTrue(
            ProviderFormSupport.isAddDisabled(
                providerType: .openai,
                name: " ",
                apiKey: "token",
                serviceAccountJSON: "",
                isSaving: false
            )
        )
        XCTAssertTrue(
            ProviderFormSupport.isAddDisabled(
                providerType: .openai,
                name: "OpenAI",
                apiKey: " ",
                serviceAccountJSON: "",
                isSaving: false
            )
        )
        XCTAssertFalse(
            ProviderFormSupport.isAddDisabled(
                providerType: .openai,
                name: "OpenAI",
                apiKey: " token ",
                serviceAccountJSON: "",
                isSaving: false
            )
        )
        XCTAssertTrue(
            ProviderFormSupport.isAddDisabled(
                providerType: .vertexai,
                name: "Vertex",
                apiKey: "",
                serviceAccountJSON: " ",
                isSaving: false
            )
        )
        XCTAssertFalse(
            ProviderFormSupport.isAddDisabled(
                providerType: .vertexai,
                name: "Vertex",
                apiKey: "",
                serviceAccountJSON: "{}",
                isSaving: false
            )
        )
    }

    func testCredentialEmptyMatchesProviderRequirements() {
        XCTAssertTrue(ProviderFormSupport.isCredentialEmpty(providerType: .openai, apiKey: " ", serviceAccountJSON: ""))
        XCTAssertFalse(ProviderFormSupport.isCredentialEmpty(providerType: .openai, apiKey: "token", serviceAccountJSON: ""))
        XCTAssertTrue(ProviderFormSupport.isCredentialEmpty(providerType: .vertexai, apiKey: "", serviceAccountJSON: " "))
        XCTAssertFalse(ProviderFormSupport.isCredentialEmpty(providerType: .vertexai, apiKey: "", serviceAccountJSON: "{}"))
        XCTAssertTrue(ProviderFormSupport.isCredentialEmpty(providerType: nil, apiKey: "token", serviceAccountJSON: "{}"))
    }

    func testFetchModelsDisabledWhileFetchIsInProgress() {
        XCTAssertTrue(
            ProviderFormSupport.isFetchModelsDisabled(
                isFetchingModels: true,
                providerType: .openai,
                apiKey: "token",
                serviceAccountJSON: "{}"
            )
        )
    }

    func testFetchModelsDisabledWithoutProviderType() {
        XCTAssertTrue(
            ProviderFormSupport.isFetchModelsDisabled(
                isFetchingModels: false,
                providerType: nil,
                apiKey: "token",
                serviceAccountJSON: "{}"
            )
        )
    }

    func testFetchModelsDisabledForAPIKeyProvidersWithoutAPIKey() {
        XCTAssertTrue(
            ProviderFormSupport.isFetchModelsDisabled(
                isFetchingModels: false,
                providerType: .openai,
                apiKey: " ",
                serviceAccountJSON: ""
            )
        )
        XCTAssertFalse(
            ProviderFormSupport.isFetchModelsDisabled(
                isFetchingModels: false,
                providerType: .openai,
                apiKey: " token ",
                serviceAccountJSON: ""
            )
        )
    }

    func testFetchModelsDisabledForVertexAIWithoutServiceAccountJSON() {
        XCTAssertTrue(
            ProviderFormSupport.isFetchModelsDisabled(
                isFetchingModels: false,
                providerType: .vertexai,
                apiKey: "",
                serviceAccountJSON: " "
            )
        )
        XCTAssertFalse(
            ProviderFormSupport.isFetchModelsDisabled(
                isFetchingModels: false,
                providerType: .vertexai,
                apiKey: "",
                serviceAccountJSON: " {} "
            )
        )
    }

    func testTestConnectionDisabledWithoutProviderType() {
        XCTAssertTrue(
            ProviderFormSupport.isTestConnectionDisabled(
                providerType: nil,
                isTesting: false,
                apiKey: "token",
                serviceAccountJSON: "{}"
            )
        )
    }

    func testTestConnectionDisabledForAPIKeyProvidersWithoutAPIKeyOrWhileTesting() {
        XCTAssertTrue(
            ProviderFormSupport.isTestConnectionDisabled(
                providerType: .openai,
                isTesting: false,
                apiKey: " ",
                serviceAccountJSON: ""
            )
        )
        XCTAssertTrue(
            ProviderFormSupport.isTestConnectionDisabled(
                providerType: .openai,
                isTesting: true,
                apiKey: " token ",
                serviceAccountJSON: ""
            )
        )
        XCTAssertFalse(
            ProviderFormSupport.isTestConnectionDisabled(
                providerType: .openai,
                isTesting: false,
                apiKey: " token ",
                serviceAccountJSON: ""
            )
        )
    }

    func testTestConnectionDisabledForVertexAIWithoutServiceAccountJSONOrWhileTesting() {
        XCTAssertTrue(
            ProviderFormSupport.isTestConnectionDisabled(
                providerType: .vertexai,
                isTesting: false,
                apiKey: "",
                serviceAccountJSON: " "
            )
        )
        XCTAssertTrue(
            ProviderFormSupport.isTestConnectionDisabled(
                providerType: .vertexai,
                isTesting: true,
                apiKey: "",
                serviceAccountJSON: " {} "
            )
        )
        XCTAssertFalse(
            ProviderFormSupport.isTestConnectionDisabled(
                providerType: .vertexai,
                isTesting: false,
                apiKey: "",
                serviceAccountJSON: " {} "
            )
        )
    }

    func testOpenRouterUsagePresentationDisablesRefreshWithoutAPIKey() {
        let presentation = ProviderFormSupport.openRouterUsagePresentation(
            apiKey: " ",
            status: .idle
        )

        XCTAssertTrue(presentation.isRefreshDisabled)
        XCTAssertEqual(presentation.statusLabel, "Not observed")
        XCTAssertEqual(presentation.hintText, "Enter an API key to check usage.")
    }

    func testOpenRouterUsagePresentationDisablesRefreshWhileLoading() {
        let presentation = ProviderFormSupport.openRouterUsagePresentation(
            apiKey: " token ",
            status: .loading
        )

        XCTAssertTrue(presentation.isRefreshDisabled)
        XCTAssertEqual(presentation.statusLabel, "Checking")
        XCTAssertEqual(presentation.hintText, "Fetching current key usage...")
    }

    func testOpenRouterUsagePresentationAllowsRefreshWithAPIKeyWhenIdleObservedOrFailed() {
        let idle = ProviderFormSupport.openRouterUsagePresentation(
            apiKey: " token ",
            status: .idle
        )
        XCTAssertFalse(idle.isRefreshDisabled)
        XCTAssertEqual(idle.statusLabel, "Not observed")
        XCTAssertEqual(idle.hintText, "Usage not fetched yet.")

        let observed = ProviderFormSupport.openRouterUsagePresentation(
            apiKey: " token ",
            status: .observed
        )
        XCTAssertFalse(observed.isRefreshDisabled)
        XCTAssertEqual(observed.statusLabel, "Observed")
        XCTAssertEqual(observed.hintText, "No usage data returned for this key.")

        let failed = ProviderFormSupport.openRouterUsagePresentation(
            apiKey: " token ",
            status: .failure("Nope")
        )
        XCTAssertFalse(failed.isRefreshDisabled)
        XCTAssertEqual(failed.statusLabel, "Not observed")
        XCTAssertEqual(failed.hintText, "Failed to fetch usage for this key.")
    }

    func testFilteredModelsMatchesNameAndIDCaseInsensitively() {
        let models = [
            model(id: "gpt-5-mini", name: "GPT 5 Mini"),
            model(id: "claude-sonnet", name: "Claude Sonnet"),
            model(id: "gemini-pro", name: "Gemini Pro")
        ]

        XCTAssertEqual(
            ProviderFormSupport.filteredModels(models, searchText: " \n ").map(\.id),
            ["gpt-5-mini", "claude-sonnet", "gemini-pro"]
        )
        XCTAssertEqual(
            ProviderFormSupport.filteredModels(models, searchText: "SONNET").map(\.id),
            ["claude-sonnet"]
        )
        XCTAssertEqual(
            ProviderFormSupport.filteredModels(models, searchText: "gpt-5").map(\.id),
            ["gpt-5-mini"]
        )
    }

    func testModelListSummaryCountsAndFilterActionAvailability() {
        let models = [
            model(id: "supported", name: "Supported", isEnabled: true),
            model(id: "disabled-supported", name: "Disabled Supported", isEnabled: false),
            model(id: "unsupported", name: "Unsupported", isEnabled: true)
        ]

        let mixedSummary = ProviderFormSupport.modelListSummary(models: models) { modelID in
            modelID == "supported"
        }

        XCTAssertEqual(mixedSummary.totalCount, 3)
        XCTAssertEqual(mixedSummary.enabledCount, 2)
        XCTAssertEqual(mixedSummary.disabledCount, 1)
        XCTAssertEqual(mixedSummary.fullySupportedCount, 1)
        XCTAssertEqual(mixedSummary.nonFullySupportedCount, 2)
        XCTAssertTrue(mixedSummary.canKeepFullySupportedModels(hasProviderType: true))
        XCTAssertFalse(mixedSummary.canKeepFullySupportedModels(hasProviderType: false))
        XCTAssertTrue(mixedSummary.canKeepEnabledModels)

        let allSupportedSummary = ProviderFormSupport.modelListSummary(models: models) { _ in true }
        XCTAssertEqual(allSupportedSummary.fullySupportedCount, 3)
        XCTAssertEqual(allSupportedSummary.nonFullySupportedCount, 0)
        XCTAssertFalse(allSupportedSummary.canKeepFullySupportedModels(hasProviderType: true))
    }

    func testModelUpdatingReplacesMatchingModelOnly() {
        let updated = model(id: "beta", name: "Beta Updated", contextWindow: 256_000)
        let result = ProviderFormSupport.modelUpdating(
            [
                model(id: "alpha", name: "Alpha"),
                model(id: "beta", name: "Beta")
            ],
            with: updated
        )

        XCTAssertEqual(result?.map(\.name), ["Alpha", "Beta Updated"])
        XCTAssertNil(
            ProviderFormSupport.modelUpdating(
                [model(id: "alpha", name: "Alpha")],
                with: model(id: "missing", name: "Missing")
            )
        )
    }

    func testModelsSettingEnabledUpdatesEveryModelAndSkipsEmptyList() {
        let result = ProviderFormSupport.modelsSettingEnabled(
            [
                model(id: "alpha", name: "Alpha", isEnabled: true),
                model(id: "beta", name: "Beta", isEnabled: false)
            ],
            enabled: false
        )

        XCTAssertEqual(result?.map(\.isEnabled), [false, false])
        XCTAssertNil(ProviderFormSupport.modelsSettingEnabled([], enabled: true))
    }

    func testModelsKeepingOnlyFullySupportedRequiresProviderAndMatches() {
        let models = [
            model(id: "supported", name: "Supported"),
            model(id: "unsupported", name: "Unsupported")
        ]

        XCTAssertEqual(
            ProviderFormSupport.modelsKeepingOnlyFullySupported(
                models,
                hasProviderType: true,
                isFullySupported: { $0 == "supported" }
            )?.map(\.id),
            ["supported"]
        )
        XCTAssertNil(
            ProviderFormSupport.modelsKeepingOnlyFullySupported(
                models,
                hasProviderType: false,
                isFullySupported: { _ in true }
            )
        )
        XCTAssertNil(
            ProviderFormSupport.modelsKeepingOnlyFullySupported(
                models,
                hasProviderType: true,
                isFullySupported: { _ in false }
            )
        )
    }

    func testModelsKeepingOnlyEnabledRequiresARealReduction() {
        XCTAssertEqual(
            ProviderFormSupport.modelsKeepingOnlyEnabled(
                [
                    model(id: "alpha", name: "Alpha", isEnabled: true),
                    model(id: "beta", name: "Beta", isEnabled: false)
                ]
            )?.map(\.id),
            ["alpha"]
        )
        XCTAssertNil(
            ProviderFormSupport.modelsKeepingOnlyEnabled([
                model(id: "alpha", name: "Alpha", isEnabled: true)
            ])
        )
        XCTAssertNil(
            ProviderFormSupport.modelsKeepingOnlyEnabled([
                model(id: "alpha", name: "Alpha", isEnabled: false)
            ])
        )
    }

    func testModelsDeletingRemovesMatchingModelOnly() {
        let result = ProviderFormSupport.modelsDeleting(
            [
                model(id: "alpha", name: "Alpha"),
                model(id: "beta", name: "Beta")
            ],
            modelID: "alpha"
        )

        XCTAssertEqual(result?.map(\.id), ["beta"])
        XCTAssertNil(
            ProviderFormSupport.modelsDeleting(
                [model(id: "alpha", name: "Alpha")],
                modelID: "missing"
            )
        )
    }

    func testModelsUpsertingAndSortingReplacesOrAppendsByDisplayName() {
        let appended = ProviderFormSupport.modelsUpsertingAndSorting(
            [model(id: "zeta", name: "Zeta")],
            model: model(id: "alpha", name: "Alpha")
        )
        XCTAssertEqual(appended.map(\.id), ["alpha", "zeta"])

        let replaced = ProviderFormSupport.modelsUpsertingAndSorting(
            [
                model(id: "alpha", name: "Alpha"),
                model(id: "beta", name: "Beta")
            ],
            model: model(id: "beta", name: "Aardvark")
        )
        XCTAssertEqual(replaced.map(\.id), ["beta", "alpha"])
        XCTAssertEqual(replaced.first?.name, "Aardvark")
    }

    func testNormalizedFetchedModelsDeduplicatesByFirstIDAndSortsByName() {
        let fetched = [
            model(id: "zeta", name: "Zeta"),
            model(id: "alpha", name: "Alpha"),
            model(id: "zeta", name: "Zeta Duplicate"),
            model(id: "beta", name: "Beta")
        ]

        let normalized = ProviderFormSupport.normalizedFetchedModels(fetched)

        XCTAssertEqual(normalized.map(\.id), ["alpha", "beta", "zeta"])
        XCTAssertEqual(normalized.first(where: { $0.id == "zeta" })?.name, "Zeta")
    }

    func testNormalizedFetchedModelsPreservesEmptyFetch() {
        XCTAssertTrue(ProviderFormSupport.normalizedFetchedModels([]).isEmpty)
    }

    func testModelsAddingSelectedRefreshesExistingMetadataAndPreservesUserState() {
        let existing = model(
            id: "gpt-5-mini",
            name: "Old GPT Mini",
            capabilities: [.vision],
            contextWindow: 64_000,
            maxOutputTokens: 8_192,
            overrides: ModelOverrides(contextWindow: 32_000),
            isEnabled: false
        )
        let fetched = model(
            id: "gpt-5-mini",
            name: "GPT 5 Mini",
            capabilities: [.vision, .toolCalling],
            contextWindow: 400_000,
            maxOutputTokens: 16_384,
            catalogMetadata: ModelCatalogMetadata(availabilityMessage: "Fetched"),
            isEnabled: true
        )

        let merged = ProviderFormSupport.modelsAddingSelectedAndRefreshingExisting(
            existingModels: [existing],
            selectedModels: [],
            allFetchedModels: [fetched],
            providerType: .openai
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].name, "GPT 5 Mini")
        XCTAssertEqual(merged[0].contextWindow, 400_000)
        XCTAssertEqual(merged[0].overrides, ModelOverrides(contextWindow: 32_000))
        XCTAssertFalse(merged[0].isEnabled)
        XCTAssertEqual(merged[0].catalogMetadata?.availabilityMessage, "Fetched")
    }

    func testModelsAddingSelectedAddsNewModelsEnabledWithoutUserOverrides() {
        let selected = model(
            id: "claude-sonnet",
            name: "Claude Sonnet",
            overrides: ModelOverrides(maxOutputTokens: 1_024),
            isEnabled: false
        )

        let merged = ProviderFormSupport.modelsAddingSelectedAndRefreshingExisting(
            existingModels: [],
            selectedModels: [selected],
            allFetchedModels: [selected],
            providerType: .anthropic
        )

        XCTAssertEqual(merged.map(\.id), ["claude-sonnet"])
        XCTAssertNil(merged[0].overrides)
        XCTAssertTrue(merged[0].isEnabled)
    }

    func testModelsAddingSelectedMigratesGitHubCopilotLegacyModelID() {
        let existing = model(
            id: "ai21-jamba-1.5-large",
            name: "Legacy Jamba",
            overrides: ModelOverrides(maxOutputTokens: 2_048),
            isEnabled: false
        )
        let fetched = model(
            id: "ai21-labs/ai21-jamba-1.5-large",
            name: "AI21 Jamba 1.5 Large",
            capabilities: [.toolCalling],
            contextWindow: 256_000,
            maxOutputTokens: 4_096
        )

        let merged = ProviderFormSupport.modelsAddingSelectedAndRefreshingExisting(
            existingModels: [existing],
            selectedModels: [],
            allFetchedModels: [fetched],
            providerType: .githubCopilot
        )

        XCTAssertEqual(merged.map(\.id), ["ai21-labs/ai21-jamba-1.5-large"])
        XCTAssertEqual(merged[0].name, "AI21 Jamba 1.5 Large")
        XCTAssertEqual(merged[0].overrides, ModelOverrides(maxOutputTokens: 2_048))
        XCTAssertFalse(merged[0].isEnabled)
    }

    func testModelsAddingSelectedSortsMergedResultsByDisplayName() {
        let merged = ProviderFormSupport.modelsAddingSelectedAndRefreshingExisting(
            existingModels: [
                model(id: "zeta", name: "Zeta")
            ],
            selectedModels: [
                model(id: "alpha", name: "Alpha")
            ],
            allFetchedModels: [
                model(id: "alpha", name: "Alpha")
            ],
            providerType: .openai
        )

        XCTAssertEqual(merged.map(\.id), ["alpha", "zeta"])
    }

    func testUpdatedDraftValuesPreservesCustomFieldsAndReplacesDefaults() {
        let defaultValues = ProviderFormSupport.updatedDraftValues(
            oldType: .openai,
            newType: .anthropic,
            name: "OpenAI",
            baseURL: ProviderType.openai.defaultBaseURL ?? "",
            iconID: LobeProviderIconCatalog.defaultIconID(for: .openai)
        )

        XCTAssertEqual(defaultValues.name, "Anthropic")
        XCTAssertEqual(defaultValues.baseURL, ProviderType.anthropic.defaultBaseURL)
        XCTAssertEqual(defaultValues.iconID, LobeProviderIconCatalog.defaultIconID(for: .anthropic))

        let customValues = ProviderFormSupport.updatedDraftValues(
            oldType: .openai,
            newType: .anthropic,
            name: "Custom Provider",
            baseURL: "https://proxy.example.com",
            iconID: "custom"
        )

        XCTAssertEqual(customValues.name, "Custom Provider")
        XCTAssertEqual(customValues.baseURL, "https://proxy.example.com")
        XCTAssertEqual(customValues.iconID, "custom")
    }

    private func model(
        id: String,
        name: String,
        capabilities: ModelCapability = [],
        contextWindow: Int = 128_000,
        maxOutputTokens: Int? = nil,
        overrides: ModelOverrides? = nil,
        catalogMetadata: ModelCatalogMetadata? = nil,
        isEnabled: Bool = true
    ) -> ModelInfo {
        ModelInfo(
            id: id,
            name: name,
            capabilities: capabilities,
            contextWindow: contextWindow,
            maxOutputTokens: maxOutputTokens,
            overrides: overrides,
            catalogMetadata: catalogMetadata,
            isEnabled: isEnabled
        )
    }
}
