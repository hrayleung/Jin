import XCTest
@testable import Jin

final class ModelSettingsSheetSupportTests: XCTestCase {
    func testReenablingBudgetReasoningRestoresDefaultsThroughPersistenceAndNormalization() throws {
        var model = ModelCatalog.modelInfo(for: "gemini-2.5-flash", provider: .gemini)
        model.overrides = ModelOverrides(
            capabilities: model.capabilities.subtracting(.reasoning),
            reasoningConfig: ModelReasoningConfig(type: .none)
        )
        let reopened = try JSONDecoder().decode(ModelInfo.self, from: JSONEncoder().encode(model))
        let editable = ModelSettingsSheetSupport.editableReasoningConfig(for: reopened, providerType: .gemini)

        XCTAssertEqual(editable.type, .budget)
        XCTAssertEqual(editable.defaultBudget, 2048)
        XCTAssertNil(editable.defaultEffort)
        XCTAssertNil(ModelSettingsResolver.resolve(model: reopened, providerType: .gemini).reasoningConfig)

        var reenabled = reopened
        reenabled.overrides?.capabilities?.insert(.reasoning)
        reenabled.overrides?.reasoningConfig = editable
        let saved = try JSONDecoder().decode(ModelInfo.self, from: JSONEncoder().encode(reenabled))
        let resolved = ModelSettingsResolver.resolve(model: saved, providerType: .gemini)
        var controls = GenerationControls(reasoning: ReasoningControls(enabled: true))
        ChatReasoningSupport.normalizeReasoningControls(
            controls: &controls,
            supportsReasoningControl: resolved.capabilities.contains(.reasoning),
            selectedReasoningConfig: resolved.reasoningConfig,
            providerType: .gemini,
            modelID: saved.id,
            supportsReasoningSummaryControl: false,
            reasoningMustRemainEnabled: false,
            defaultAnthropicEffort: .high,
            defaultAnthropicBudget: 1024
        )

        XCTAssertEqual(controls.reasoning?.enabled, true)
        XCTAssertEqual(controls.reasoning?.budgetTokens, 2048)
        XCTAssertNil(controls.reasoning?.effort)
    }

    func testReenablingToggleReasoningPreservesItsCatalogMode() {
        var model = ModelCatalog.modelInfo(for: "mistral-small-4-0-26-03", provider: .mistral)
        model.overrides = ModelOverrides(reasoningConfig: ModelReasoningConfig(type: .none))

        let editable = ModelSettingsSheetSupport.editableReasoningConfig(for: model, providerType: .mistral)

        XCTAssertEqual(editable, ModelReasoningConfig(type: .toggle))
        XCTAssertEqual(
            ModelSettingsResolver.resolve(model: model, providerType: .mistral).reasoningConfig?.type,
            ReasoningConfigType.none
        )
    }

    func testDisabledLegacyModelUsesCatalogReasoningInsteadOfStaleMetadata() {
        let model = ModelInfo(
            id: "gemini-2.5-flash",
            name: "Legacy Gemini",
            capabilities: [.streaming],
            contextWindow: 8192,
            reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .low),
            overrides: ModelOverrides(
                capabilities: [.streaming],
                reasoningConfig: ModelReasoningConfig(type: .none)
            )
        )

        XCTAssertEqual(
            ModelSettingsSheetSupport.editableReasoningConfig(for: model, providerType: .gemini),
            ModelReasoningConfig(type: .budget, defaultBudget: 2048)
        )
    }

    func testDisabledUncataloguedModelsRestoreDeclaredModesAndDefaults() {
        let configs = [
            ModelReasoningConfig(type: .effort, defaultEffort: .high, supportedEfforts: [.low, .high]),
            ModelReasoningConfig(type: .budget, defaultBudget: 8192),
            ModelReasoningConfig(type: .toggle)
        ]
        for config in configs {
            let model = ModelInfo(
                id: "custom-reasoning-model",
                name: "Custom Model",
                capabilities: [.streaming, .reasoning],
                contextWindow: 8192,
                reasoningConfig: config,
                overrides: ModelOverrides(
                    capabilities: [.streaming],
                    reasoningConfig: ModelReasoningConfig(type: .none)
                )
            )
            for providerType: ProviderType? in [nil, .openai] {
                XCTAssertEqual(
                    ModelSettingsSheetSupport.editableReasoningConfig(for: model, providerType: providerType),
                    config
                )
            }
        }
    }

    func testReasoningEditorPreservesActiveOverridesAndTheirDefaults() {
        let override = ModelReasoningConfig(type: .budget, defaultBudget: 8192)
        var model = ModelCatalog.modelInfo(for: "gemini-2.5-flash", provider: .gemini)
        model.overrides = ModelOverrides(reasoningConfig: override)

        XCTAssertEqual(
            ModelSettingsSheetSupport.editableReasoningConfig(for: model, providerType: .gemini),
            override
        )
    }

    func testReasoningEditorHasAnEditableFallbackWithoutDeclaredReasoning() {
        for config: ModelReasoningConfig? in [nil, ModelReasoningConfig(type: .none)] {
            let model = ModelInfo(
                id: "custom-model",
                name: "Custom Model",
                capabilities: [.streaming, .reasoning],
                contextWindow: 8192,
                reasoningConfig: config
            )
            XCTAssertEqual(
                ModelSettingsSheetSupport.editableReasoningConfig(for: model, providerType: nil),
                ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            )
        }
    }

    func testPositiveIntegerParsesTrimmedPositiveInteger() {
        XCTAssertEqual(
            ModelSettingsSheetSupport.positiveInteger(from: " \n 128000\t "),
            128_000
        )
    }

    func testPositiveIntegerRejectsBlankZeroNegativeAndNonIntegerDrafts() {
        XCTAssertNil(ModelSettingsSheetSupport.positiveInteger(from: " \n\t "))
        XCTAssertNil(ModelSettingsSheetSupport.positiveInteger(from: "0"))
        XCTAssertNil(ModelSettingsSheetSupport.positiveInteger(from: "-1"))
        XCTAssertNil(ModelSettingsSheetSupport.positiveInteger(from: "1.5"))
        XCTAssertNil(ModelSettingsSheetSupport.positiveInteger(from: "many"))
    }

    func testOptionalPositiveIntegerReturnsEmptyForBlankDraft() {
        XCTAssertEqual(
            ModelSettingsSheetSupport.optionalPositiveInteger(from: " \n\t "),
            .empty
        )
    }

    func testOptionalPositiveIntegerParsesTrimmedPositiveInteger() {
        XCTAssertEqual(
            ModelSettingsSheetSupport.optionalPositiveInteger(from: " \n 4096\t "),
            .value(4_096)
        )
    }

    func testOptionalPositiveIntegerRejectsInvalidValues() {
        XCTAssertEqual(ModelSettingsSheetSupport.optionalPositiveInteger(from: "0"), .invalid)
        XCTAssertEqual(ModelSettingsSheetSupport.optionalPositiveInteger(from: "-1"), .invalid)
        XCTAssertEqual(ModelSettingsSheetSupport.optionalPositiveInteger(from: "1.5"), .invalid)
        XCTAssertEqual(ModelSettingsSheetSupport.optionalPositiveInteger(from: "many"), .invalid)
    }
}
