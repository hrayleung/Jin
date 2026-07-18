import XCTest
@testable import Jin

/// Guardrails for the catalog ↔ registry dual-read migration.
///
/// These contracts must stay green while allowlists move onto `ModelFeatures`.
final class ModelCatalogConsistencyTests: XCTestCase {

    // MARK: - Catalog integrity

    func testEveryRecordHasNonEmptyIDAndDisplayName() {
        for (provider, records) in ModelCatalog.orderedRecords {
            for record in records {
                XCTAssertFalse(
                    record.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Empty model id for provider \(provider)"
                )
                XCTAssertFalse(
                    record.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Empty display name for \(provider)/\(record.id)"
                )
            }
        }
    }

    func testPrimaryProviderSeededModelsAreFullySupported() {
        // First-party / fully-curated providers should only seed ✦ models.
        // Some gateway/hosting providers intentionally seed useful-but-partial
        // models (e.g. Fireworks community models) — exclude those from this contract.
        let strictSeedProviders: Set<ProviderType> = [
            .openai, .anthropic, .gemini, .vertexai, .xai, .deepseek, .mistral, .perplexity
        ]
        for (provider, records) in ModelCatalog.orderedRecords where strictSeedProviders.contains(provider) {
            for record in records where record.isSeeded {
                XCTAssertTrue(
                    record.isFullySupported,
                    "Seeded model \(provider)/\(record.id) must be fully supported"
                )
            }
        }
    }

    func testReasoningConfigOnlyAppearsWithReasoningCapability() {
        // Inverse contract: a non-nil reasoningConfig without `.reasoning` is always a bug.
        // (Many fully-supported models intentionally keep reasoningConfig nil — e.g. always-on
        // or no-UI reasoning — so we do not require config for every `.reasoning` bit.)
        for (provider, records) in ModelCatalog.orderedRecords {
            for record in records where record.reasoningConfig != nil {
                XCTAssertTrue(
                    record.capabilities.contains(.reasoning),
                    "\(provider)/\(record.id) has reasoningConfig but lacks .reasoning capability"
                )
            }
        }
    }

    func testLookupIndexCoversEveryOrderedRecordWithoutDuplicates() {
        for (provider, records) in ModelCatalog.orderedRecords {
            let lookup = ModelCatalog.lookup[provider] ?? [:]
            XCTAssertEqual(
                lookup.count,
                Set(records.map { $0.id.lowercased() }).count,
                "Lookup size mismatch for \(provider)"
            )
            for record in records {
                XCTAssertNotNil(
                    lookup[record.id.lowercased()],
                    "Missing lookup entry for \(provider)/\(record.id)"
                )
            }
        }
    }

    // MARK: - Capability ↔ registry dual-read

    func testCatalogCodeExecutionCapabilityImpliesRegistrySupportUnlessFeaturesDeny() {
        // Capability bit implies support unless declared features set codeExecution: false
        // (alias records may advertise tools while the wire allowlist denies execution).
        let providersWithNativeCodeExecution: [ProviderType] = [
            .openai, .openaiWebSocket, .anthropic, .xai, .gemini, .vertexai
        ]

        for provider in providersWithNativeCodeExecution {
            let records = ModelCatalog.orderedRecords[provider] ?? []
            for record in records where record.capabilities.contains(.codeExecution) {
                let features = ModelCatalog.features(for: record.id, provider: provider)
                if features?.codeExecution == false {
                    XCTAssertFalse(
                        ModelCapabilityRegistry.supportsCodeExecution(for: provider, modelID: record.id),
                        "\(provider)/\(record.id) features deny code execution but registry returned true"
                    )
                    continue
                }
                XCTAssertTrue(
                    ModelCapabilityRegistry.supportsCodeExecution(for: provider, modelID: record.id),
                    "\(provider)/\(record.id) has .codeExecution but registry/dual-read returned false"
                )
                XCTAssertTrue(
                    JinModelSupport.supportsCodeExecution(providerType: provider, modelID: record.id),
                    "JinModelSupport must agree for \(provider)/\(record.id)"
                )
            }
        }
    }

    func testDeclaredFeaturesWinOverRegistryHeuristics() {
        // GPT-5.6 Sol declares features on the catalog — dual-read must honor them.
        let entry = ModelCatalog.entry(for: "gpt-5.6-sol", provider: .openai)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.features.webSearch, true)
        XCTAssertEqual(entry?.features.codeExecution, true)
        XCTAssertEqual(entry?.features.openAIStyleProMode, true)
        XCTAssertEqual(entry?.features.openAIStyleMaxEffort, true)

        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .openai, modelID: "gpt-5.6-sol"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-5.6-sol"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsOpenAIStyleProMode(for: .openai, modelID: "gpt-5.6-sol"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(for: .openai, modelID: "gpt-5.6-sol"))
        XCTAssertTrue(JinModelSupport.supportsWebSearch(providerType: .openai, modelID: "gpt-5.6-sol"))
    }

    func testOpenAIFeatureTableCoversAllowlistOnlyIDs() {
        // IDs that live in the feature table without a full Record still resolve.
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-4.1"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "o4-mini"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-5-mini"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-4o"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-realtime"))
    }

    func testAnthropicFeatureTableDeniesAliasCodeExecution() {
        // Alias records may still carry .codeExecution on capabilities; features deny it.
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-opus-4"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-sonnet-4"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-haiku-4"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-opus-4-8"))
    }

    func testOpenAICatalogFeatureTableIsSingleSourceForWirePolicy() {
        // No private registry sets remain — these must come from catalog features.
        XCTAssertTrue(ModelCapabilityRegistry.supportsOpenAIStyleExtremeEffort(for: .openai, modelID: "gpt-5.4"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(for: .openai, modelID: "gpt-5.4"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsOpenAIStyleVerbosity(for: .openai, modelID: "gpt-5.4"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsOpenAIStyleProMode(for: .openai, modelID: "gpt-5.4"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsOpenAIStyleProMode(for: .openai, modelID: "gpt-5.6-terra"))
    }

    func testGoogleFeatureTablesDifferentiateAIStudioAndVertex() {
        // AI Studio 3.5 Flash has Maps; Vertex 3.5 Flash does not.
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .gemini, modelID: "gemini-3.5-flash"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-3.5-flash"))

        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemma-4-31b-it"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemma-4-31b-it"))

        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-2.0-flash-001"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-2.5-flash-preview"))

        // Prefixed IDs normalize to bare keys.
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "models/gemini-3.5-flash"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "google/gemini-3-pro-preview"))
    }

    func testGoogleFeatureTableDeniesImageModelsMapsAndCode() {
        XCTAssertFalse(ModelCapabilityRegistry.supportsGoogleMaps(for: .gemini, modelID: "gemini-3-pro-image-preview"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-3-pro-image-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3-pro-image-preview"))
    }

    func testGemini35FlashDeclaredMapsAndSearchFeatures() {
        let entry = ModelCatalog.entry(for: "gemini-3.5-flash", provider: .gemini)
        XCTAssertEqual(entry?.features.webSearch, true)
        XCTAssertEqual(entry?.features.googleMaps, true)
        XCTAssertEqual(entry?.features.codeExecution, true)

        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3.5-flash"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .gemini, modelID: "gemini-3.5-flash"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-3.5-flash"))
    }

    func testAnthropicDeclaredDynamicFilteringFeatures() {
        let entry = ModelCatalog.entry(for: "claude-opus-4-8", provider: .anthropic)
        XCTAssertEqual(entry?.features.webSearchDynamicFiltering, true)
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(
                for: .anthropic,
                modelID: "claude-opus-4-8"
            )
        )
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsWebSearch(for: .anthropic, modelID: "claude-opus-4-8")
        )
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-opus-4-8")
        )
    }

    func testUnspecifiedFeaturesStillUseRegistryFallback() {
        // Mistral has no web search — features unspecified must not invent support.
        let entry = ModelCatalog.entry(for: "mistral-medium-3.5", provider: .mistral)
        XCTAssertNotNil(entry)
        XCTAssertTrue(entry?.features.isUnspecified == true)
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .mistral, modelID: "mistral-medium-3.5"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .mistral, modelID: "mistral-medium-3.5"))
    }

    func testUnknownModelsStayConservative() {
        XCTAssertFalse(
            ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-totally-unknown-xyz")
        )
        XCTAssertFalse(
            ModelCapabilityRegistry.supportsWebSearch(for: .mistral, modelID: "mistral-totally-unknown-xyz")
        )
        XCTAssertNil(ModelCatalog.entry(for: "gpt-totally-unknown-xyz", provider: .openai))
    }

    // MARK: - Resolver dual-read

    func testResolverPicksUpCatalogWebSearchFeature() {
        let model = ModelCatalog.modelInfo(for: "gpt-5.6-sol", provider: .openai)
        let resolved = ModelSettingsResolver.resolve(model: model, providerType: .openai)
        XCTAssertTrue(resolved.supportsWebSearch)
        XCTAssertTrue(resolved.capabilities.contains(.codeExecution))
    }
}
