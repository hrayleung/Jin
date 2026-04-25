import XCTest
@testable import Jin

final class ChatStreamingSessionResolverTests: XCTestCase {
    func testProviderSnapshotConvertsMatchingProviderEntity() throws {
        let provider = ProviderConfig(
            id: "openai-provider",
            name: "OpenAI",
            type: .openai,
            baseURL: "https://api.openai.com/v1",
            models: [makeModel(id: "gpt-5.2", name: "GPT")]
        )
        let entity = try ProviderConfigEntity.fromDomain(provider)
        let thread = try makeThread(providerID: provider.id, modelID: "gpt-5.2")

        let snapshot = try ChatStreamingSessionResolver.providerSnapshot(for: thread, providers: [entity])

        XCTAssertEqual(snapshot.providerID, provider.id)
        XCTAssertEqual(snapshot.type, .openai)
        XCTAssertEqual(snapshot.config?.id, provider.id)
    }

    func testModelSnapshotUsesEffectiveModelAndNormalizedName() throws {
        let thread = try makeThread(providerID: "openai", modelID: "alias")
        let resolvedModel = makeModel(id: "unit-test-model", name: "Raw Name")
        let normalizedModel = makeModel(id: "unit-test-model", name: "Normalized Name")
        var migratedModelID: String?

        let snapshot = ChatStreamingSessionResolver.modelSnapshot(
            for: thread,
            threadControls: GenerationControls(),
            providerSnapshot: ChatStreamingProviderSnapshot(
                providerID: "openai",
                entity: nil,
                type: .openai,
                config: nil
            ),
            managedAgentSyntheticModelID: { _, _ in XCTFail("Managed agent path should not run"); return "" },
            effectiveModelID: { modelID, _, _ in
                XCTAssertEqual(modelID, "alias")
                return "unit-test-model"
            },
            migrateThreadModelIDIfNeeded: { _, resolvedModelID in
                migratedModelID = resolvedModelID
            },
            resolvedModelInfo: { modelID, _, _ in
                XCTAssertEqual(modelID, "unit-test-model")
                return resolvedModel
            },
            normalizedModelInfo: { model, _ in
                XCTAssertEqual(model.id, resolvedModel.id)
                return normalizedModel
            }
        )

        XCTAssertEqual(snapshot.modelID, "unit-test-model")
        XCTAssertEqual(snapshot.modelName, "Normalized Name")
        XCTAssertEqual(migratedModelID, "unit-test-model")
        XCTAssertEqual(snapshot.resolvedSettings?.contextWindow, normalizedModel.contextWindow)
    }

    func testRequestControlsAppliesAutomaticCacheSanitizersAndPersistenceInjectors() {
        var sanitizedProviderType: ProviderType?
        var didInjectCodex = false
        var didInjectClaudeManaged = false
        let model = makeModel(id: "unit-test-model", name: "GPT")
        let modelSnapshot = ChatStreamingModelSnapshot(
            modelID: model.id,
            modelName: model.name,
            modelInfo: model,
            normalizedModelInfo: model,
            resolvedSettings: ModelSettingsResolver.resolve(model: model, providerType: .openai)
        )

        let controls = ChatStreamingSessionResolver.requestControls(
            threadControls: GenerationControls(),
            assistant: nil,
            modelSnapshot: modelSnapshot,
            providerType: .openai,
            isAgentModeActive: false,
            automaticContextCacheControls: { providerType, modelID, capabilities in
                XCTAssertEqual(providerType, .openai)
                XCTAssertEqual(modelID, "unit-test-model")
                XCTAssertTrue(capabilities?.contains(.toolCalling) == true)
                return ContextCacheControls(mode: .implicit)
            },
            sanitizeProviderSpecific: { providerType, controls in
                sanitizedProviderType = providerType
                controls.providerSpecific["removed"] = nil
            },
            injectCodexThreadPersistence: { controls in
                didInjectCodex = true
                controls.codexResumeThreadID = "codex-thread"
            },
            injectClaudeManagedAgentSessionPersistence: { _ in
                didInjectClaudeManaged = true
            }
        )

        XCTAssertEqual(sanitizedProviderType, .openai)
        XCTAssertEqual(controls.contextCache?.mode, .implicit)
        XCTAssertEqual(controls.codexResumeThreadID, "codex-thread")
        XCTAssertTrue(didInjectCodex)
        XCTAssertTrue(didInjectClaudeManaged)
        XCTAssertNil(controls.agentMode)
    }

    private func makeModel(id: String, name: String) -> ModelInfo {
        ModelInfo(
            id: id,
            name: name,
            capabilities: [.streaming, .toolCalling],
            contextWindow: 128000,
            maxOutputTokens: 8192
        )
    }

    private func makeThread(providerID: String, modelID: String) throws -> ConversationModelThreadEntity {
        ConversationModelThreadEntity(
            providerID: providerID,
            modelID: modelID,
            modelConfigData: try JSONEncoder().encode(GenerationControls())
        )
    }
}
