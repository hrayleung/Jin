import Foundation

enum ModelSettingsSheetSupport {
    /// Keep the off state separate from the mode and defaults shown when enabling reasoning.
    static func editableReasoningConfig(
        for model: ModelInfo,
        providerType: ProviderType?
    ) -> ModelReasoningConfig {
        let resolved = ModelSettingsResolver.resolve(model: model, providerType: providerType)
        if let config = resolved.reasoningConfig, config.type != .none {
            return config
        }

        // Disabling reasoning can persist both a `.none` config and a capability
        // override without reasoning. Resolve the base model to recover its
        // catalog mode and defaults, including for legacy persisted metadata.
        var baseModel = model
        baseModel.overrides = nil
        let base = ModelSettingsResolver.resolve(model: baseModel, providerType: providerType)
        if let config = base.reasoningConfig, config.type != .none {
            return config
        }

        return ModelReasoningConfig(type: .effort, defaultEffort: .medium)
    }

    enum OptionalPositiveIntegerDraft: Equatable {
        case empty
        case value(Int)
        case invalid
    }

    static func positiveInteger(from draft: String) -> Int? {
        guard let trimmed = draft.trimmedNonEmpty,
              let value = Int(trimmed),
              value > 0 else { return nil }
        return value
    }

    static func optionalPositiveInteger(from draft: String) -> OptionalPositiveIntegerDraft {
        guard let trimmed = draft.trimmedNonEmpty else { return .empty }
        guard let value = Int(trimmed), value > 0 else { return .invalid }
        return .value(value)
    }
}
