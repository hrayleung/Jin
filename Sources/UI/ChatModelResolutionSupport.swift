import Foundation

extension ChatModelCapabilitySupport {
    static func resolvedClaudeManagedAgentModelInfo(
        threadModelID: String,
        providerEntity: ProviderConfigEntity?,
        threadControls: GenerationControls?
    ) -> ModelInfo? {
        var controls = threadControls ?? GenerationControls()
        providerEntity?.applyClaudeManagedDefaults(into: &controls)

        let remoteModelID = ClaudeManagedAgentRuntime.resolvedRuntimeModelID(
            threadModelID: threadModelID,
            controls: controls
        )

        if let remoteModel = ModelCatalog.seededModels(for: .anthropic).first(where: { $0.id == remoteModelID }) {
            return ModelInfo(
                id: remoteModelID,
                name: controls.claudeManagedAgentModelDisplayName
                    ?? controls.claudeManagedAgentDisplayName
                    ?? remoteModel.name,
                capabilities: remoteModel.capabilities,
                contextWindow: remoteModel.contextWindow,
                maxOutputTokens: remoteModel.maxOutputTokens,
                reasoningConfig: remoteModel.reasoningConfig,
                overrides: remoteModel.overrides,
                catalogMetadata: remoteModel.catalogMetadata,
                isEnabled: true
            )
        }

        return providerEntity?.selectableModels.first(where: { $0.id == threadModelID })
    }

    static func resolvedModelInfo(
        modelID: String,
        providerEntity: ProviderConfigEntity?,
        providerType: ProviderType?,
        availableModels: [ModelInfo]? = nil
    ) -> ModelInfo? {
        let models = availableModels ?? providerEntity?.allModels ?? []
        return ProviderModelAliasResolver.resolvedModel(
            for: modelID,
            providerType: providerType,
            availableModels: models
        )
    }

    static func effectiveModelID(
        modelID: String,
        providerEntity: ProviderConfigEntity?,
        providerType: ProviderType?,
        availableModels: [ModelInfo]? = nil
    ) -> String {
        let models = availableModels ?? providerEntity?.allModels ?? []
        return ProviderModelAliasResolver.resolvedModelID(
            for: modelID,
            providerType: providerType,
            availableModels: models
        )
    }

    static func normalizedSelectedModelInfo(
        _ model: ModelInfo,
        providerType: ProviderType?
    ) -> ModelInfo {
        guard providerType == .fireworks else { return model }
        return normalizedFireworksModelInfo(model)
    }

    static func normalizedFireworksModelInfo(_ model: ModelInfo) -> ModelInfo {
        if let catalogEntry = ModelCatalog.entry(for: model.id, provider: .fireworks) {
            return ModelInfo(
                id: model.id,
                name: model.name == model.id ? catalogEntry.displayName : model.name,
                capabilities: catalogEntry.capabilities,
                contextWindow: catalogEntry.contextWindow,
                maxOutputTokens: catalogEntry.maxOutputTokens,
                reasoningConfig: catalogEntry.reasoningConfig,
                overrides: model.overrides,
                catalogMetadata: model.catalogMetadata,
                isEnabled: model.isEnabled
            )
        }

        let canonicalID = fireworksCanonicalModelID(model.id)
        var caps = model.capabilities
        var contextWindow = model.contextWindow
        var reasoningConfig = model.reasoningConfig
        var name = model.name
        let defaultReasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
        let deepSeekV4ProReasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .high)

        if isFireworksDeepSeekV4ProModel(model.id) {
            caps.remove(.audio)
            caps.remove(.vision)
            caps.remove(.promptCaching)
            caps.insert(.reasoning)
            contextWindow = 1_048_600
            reasoningConfig = deepSeekV4ProReasoningConfig
            if name == model.id { name = "DeepSeek V4 Pro" }
        } else {
            switch canonicalID {
            case "qwen3p6-plus":
                caps.insert(.vision)
                caps.remove(.audio)
                caps.remove(.reasoning)
                contextWindow = 128_000
                reasoningConfig = nil
                if name == model.id { name = "Qwen3.6 Plus" }
            case "deepseek-v3p2":
                caps.remove(.audio)
                caps.remove(.vision)
                caps.remove(.reasoning)
                contextWindow = 163_800
                reasoningConfig = nil
                if name == model.id { name = "DeepSeek V3.2" }
            case "kimi-k2-instruct-0905":
                caps.remove(.audio)
                caps.remove(.vision)
                caps.remove(.reasoning)
                contextWindow = 262_100
                reasoningConfig = nil
                if name == model.id { name = "Kimi K2 Instruct 0905" }
            case "kimi-k2p5":
                caps.insert(.vision)
                caps.insert(.reasoning)
                contextWindow = 262_100
                reasoningConfig = defaultReasoningConfig
                if name == model.id { name = "Kimi K2.5" }
            case "kimi-k2p6":
                caps.insert(.vision)
                caps.insert(.reasoning)
                contextWindow = 262_100
                reasoningConfig = defaultReasoningConfig
                if name == model.id { name = "Kimi K2.6" }
            case "qwen3-235b-a22b":
                caps.remove(.audio)
                caps.remove(.vision)
                caps.remove(.reasoning)
                contextWindow = 131_100
                reasoningConfig = nil
                if name == model.id { name = "Qwen3 235B A22B" }
            case "qwen3-omni-30b-a3b-instruct", "qwen3-omni-30b-a3b-thinking":
                caps.insert(.vision)
                caps.insert(.audio)
            case "qwen3-asr-4b", "qwen3-asr-0.6b":
                caps.insert(.audio)
            case "glm-5":
                caps.insert(.reasoning)
                contextWindow = 202_800
                reasoningConfig = defaultReasoningConfig
                if name == model.id { name = "GLM-5" }
            case "glm-4p7":
                caps.insert(.reasoning)
                contextWindow = 202_800
                reasoningConfig = defaultReasoningConfig
                if name == model.id { name = "GLM-4.7" }
            case "minimax-m2p5":
                caps.insert(.reasoning)
                contextWindow = 196_600
                reasoningConfig = defaultReasoningConfig
                if name == model.id { name = "MiniMax M2.5" }
            case "minimax-m2p1":
                caps.insert(.reasoning)
                contextWindow = 204_800
                reasoningConfig = defaultReasoningConfig
                if name == model.id { name = "MiniMax M2.1" }
            case "minimax-m2":
                caps.insert(.reasoning)
                contextWindow = 196_600
                reasoningConfig = defaultReasoningConfig
                if name == model.id { name = "MiniMax M2" }
            default:
                break
            }
        }

        return ModelInfo(
            id: model.id,
            name: name,
            capabilities: caps,
            contextWindow: contextWindow,
            maxOutputTokens: model.maxOutputTokens,
            reasoningConfig: reasoningConfig,
            overrides: model.overrides,
            catalogMetadata: model.catalogMetadata,
            isEnabled: model.isEnabled
        )
    }
}
