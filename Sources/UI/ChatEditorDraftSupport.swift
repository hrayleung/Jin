import Foundation

enum ChatEditorDraftError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}

struct PreparedImageGenerationEditorDraft {
    let draft: ImageGenerationControls
    let seedDraft: String
    let compressionQualityDraft: String
}

struct PreparedThinkingBudgetEditorDraft {
    let thinkingBudgetDraft: String
    let maxTokensDraft: String
}

enum ChatEditorDraftSupport {
    static func prepareImageGenerationEditorDraft(
        current: ImageGenerationControls?,
        supportedAspectRatios: [ImageAspectRatio],
        supportedImageSizes: [ImageOutputSize]
    ) -> PreparedImageGenerationEditorDraft {
        var draft = current ?? ImageGenerationControls()
        if let ratio = draft.aspectRatio, !supportedAspectRatios.contains(ratio) {
            draft.aspectRatio = nil
        }
        if let size = draft.imageSize, !supportedImageSizes.contains(size) {
            draft.imageSize = nil
        }
        return PreparedImageGenerationEditorDraft(
            draft: draft,
            seedDraft: draft.seed.map(String.init) ?? "",
            compressionQualityDraft: draft.vertexCompressionQuality.map(String.init) ?? ""
        )
    }

    static func isImageGenerationDraftValid(
        seedDraft: String,
        compressionQualityDraft: String
    ) -> Bool {
        let seedText = seedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !seedText.isEmpty, Int(seedText) == nil {
            return false
        }

        let qualityText = compressionQualityDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !qualityText.isEmpty {
            guard let quality = Int(qualityText), (0...100).contains(quality) else {
                return false
            }
        }

        return true
    }

    static func applyImageGenerationDraft(
        draft: ImageGenerationControls,
        seedDraft: String,
        compressionQualityDraft: String,
        supportsCurrentModelImageSizeControl: Bool,
        supportedCurrentModelImageSizes: [ImageOutputSize],
        supportedCurrentModelImageAspectRatios: [ImageAspectRatio],
        providerType: ProviderType?
    ) -> Result<ImageGenerationControls?, ChatEditorDraftError> {
        var draft = draft

        let seedText = seedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if seedText.isEmpty {
            draft.seed = nil
        } else if let seed = Int(seedText) {
            draft.seed = seed
        } else {
            return .failure(.message("Seed must be an integer."))
        }

        let qualityText = compressionQualityDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if qualityText.isEmpty {
            draft.vertexCompressionQuality = nil
        } else if let quality = Int(qualityText), (0...100).contains(quality) {
            draft.vertexCompressionQuality = quality
        } else {
            return .failure(.message("JPEG quality must be an integer between 0 and 100."))
        }

        if !supportsCurrentModelImageSizeControl {
            draft.imageSize = nil
        } else if let size = draft.imageSize, !supportedCurrentModelImageSizes.contains(size) {
            draft.imageSize = nil
        }

        if let ratio = draft.aspectRatio, !supportedCurrentModelImageAspectRatios.contains(ratio) {
            draft.aspectRatio = nil
        }

        if providerType != .vertexai {
            draft.vertexPersonGeneration = nil
            draft.vertexOutputMIMEType = nil
            draft.vertexCompressionQuality = nil
        }

        return .success(draft.isEmpty ? nil : draft)
    }

    static func normalizedCodexWorkingDirectoryPath(from raw: String) -> String? {
        CodexWorkingDirectoryPresetsStore.normalizedDirectoryPath(from: raw, requireExistingDirectory: true)
    }

    static func applyCodexSessionSettingsDraft(
        workingDirectoryDraft: String,
        sandboxModeDraft: CodexSandboxMode,
        personalityDraft: CodexPersonality?,
        controls: GenerationControls
    ) -> Result<(controls: GenerationControls, normalizedPath: String?), ChatEditorDraftError> {
        var updatedControls = controls
        let trimmed = workingDirectoryDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            updatedControls.codexWorkingDirectory = nil
            updatedControls.codexSandboxMode = sandboxModeDraft
            updatedControls.codexPersonality = personalityDraft
            return .success((updatedControls, nil))
        }

        guard let normalized = normalizedCodexWorkingDirectoryPath(from: trimmed) else {
            return .failure(.message("Choose an existing local folder (absolute path or ~/path)."))
        }

        updatedControls.codexWorkingDirectory = normalized
        updatedControls.codexSandboxMode = sandboxModeDraft
        updatedControls.codexPersonality = personalityDraft
        return .success((updatedControls, normalized))
    }

    static func applyClaudeManagedAgentSessionSettingsDraft(
        agentIDDraft: String,
        environmentIDDraft: String,
        agentDisplayNameDraft: String,
        environmentDisplayNameDraft: String,
        controls: GenerationControls
    ) -> Result<GenerationControls, ChatEditorDraftError> {
        var updatedControls = controls
        let trimmedAgentID = agentIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEnvironmentID = environmentIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAgentDisplayName = agentDisplayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEnvironmentDisplayName = environmentDisplayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedAgentID.isEmpty != trimmedEnvironmentID.isEmpty {
            return .failure(.message("Enter both Agent ID and Environment ID, or leave both blank."))
        }

        updatedControls.claudeManagedAgentID = trimmedAgentID.isEmpty ? nil : trimmedAgentID
        updatedControls.claudeManagedEnvironmentID = trimmedEnvironmentID.isEmpty ? nil : trimmedEnvironmentID
        updatedControls.claudeManagedAgentDisplayName = trimmedAgentDisplayName.isEmpty ? nil : trimmedAgentDisplayName
        updatedControls.claudeManagedEnvironmentDisplayName = trimmedEnvironmentDisplayName.isEmpty ? nil : trimmedEnvironmentDisplayName

        if trimmedAgentID.isEmpty || trimmedEnvironmentID.isEmpty {
            updatedControls.clearClaudeManagedAgentSessionState()
        }

        return .success(updatedControls)
    }

    static func thinkingBudgetDraftInt(from raw: String) -> Int? {
        Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func maxTokensDraftInt(from raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    static func resolvedAnthropicMaxTokensDraftInt(
        from raw: String,
        currentMaxTokens: Int?,
        modelID: String
    ) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let fallback = currentMaxTokens ?? AnthropicModelLimits.resolvedMaxTokens(
                requested: nil,
                for: modelID,
                fallback: 4096
            )
            return fallback > 0 ? fallback : nil
        }
        return maxTokensDraftInt(from: raw)
    }

    static func prepareThinkingBudgetEditorDraft(
        anthropicUsesAdaptiveThinking: Bool,
        budgetTokens: Int?,
        defaultBudget: Int,
        providerType: ProviderType?,
        requestedMaxTokens: Int?,
        modelID: String
    ) -> PreparedThinkingBudgetEditorDraft {
        let thinkingBudgetDraft: String
        if anthropicUsesAdaptiveThinking {
            thinkingBudgetDraft = ""
        } else {
            thinkingBudgetDraft = "\(budgetTokens ?? defaultBudget)"
        }

        let maxTokensDraft: String
        if providerType == .anthropic {
            let resolvedMax = AnthropicModelLimits.resolvedMaxTokens(
                requested: requestedMaxTokens,
                for: modelID,
                fallback: 4096
            )
            maxTokensDraft = "\(resolvedMax)"
        } else {
            maxTokensDraft = requestedMaxTokens.map(String.init) ?? ""
        }

        return PreparedThinkingBudgetEditorDraft(
            thinkingBudgetDraft: thinkingBudgetDraft,
            maxTokensDraft: maxTokensDraft
        )
    }

    static func isThinkingBudgetDraftValid(
        anthropicUsesAdaptiveThinking: Bool,
        providerType: ProviderType?,
        modelID: String,
        thinkingBudgetDraft: String,
        maxTokensDraft: String,
        currentMaxTokens: Int?
    ) -> Bool {
        if !anthropicUsesAdaptiveThinking {
            guard let budget = thinkingBudgetDraftInt(from: thinkingBudgetDraft), budget > 0 else { return false }
        }
        guard providerType == .anthropic else { return true }
        guard let maxTokens = resolvedAnthropicMaxTokensDraftInt(
            from: maxTokensDraft,
            currentMaxTokens: currentMaxTokens,
            modelID: modelID
        ) else { return false }
        if let modelMax = AnthropicModelLimits.maxOutputTokens(for: modelID), maxTokens > modelMax {
            return false
        }
        return true
    }

    static func thinkingBudgetValidationWarning(
        providerType: ProviderType?,
        anthropicUsesAdaptiveThinking: Bool,
        modelID: String,
        thinkingBudgetDraft: String,
        maxTokensDraft: String,
        currentMaxTokens: Int?
    ) -> String? {
        guard providerType == .anthropic else { return nil }

        let thinkingBudgetDraftInt = thinkingBudgetDraftInt(from: thinkingBudgetDraft)
        let trimmedMaxTokensDraft = maxTokensDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxTokensDraftInt = resolvedAnthropicMaxTokensDraftInt(
            from: maxTokensDraft,
            currentMaxTokens: currentMaxTokens,
            modelID: modelID
        )

        if !anthropicUsesAdaptiveThinking {
            guard let budget = thinkingBudgetDraftInt else { return "Enter an integer token budget (e.g., 4096)." }

            if budget <= 0 {
                return "Thinking budget must be a positive integer."
            }

            if let maxTokens = maxTokensDraftInt, maxTokens > 0, budget >= maxTokens {
                return "Recommended: keep budget tokens below max output tokens."
            }
        }

        if !trimmedMaxTokensDraft.isEmpty && maxTokensDraftInt == nil {
            return "Enter a valid positive max output token value."
        }

        if let modelMax = AnthropicModelLimits.maxOutputTokens(for: modelID),
           let maxTokens = maxTokensDraftInt,
           maxTokens > modelMax {
            return "This model allows at most \(modelMax) max output tokens."
        }

        return nil
    }
}
