import Foundation

struct ChatStreamingProviderSnapshot {
    let providerID: String
    let entity: ProviderConfigEntity?
    let type: ProviderType?
    let config: ProviderConfig?
}

struct ChatStreamingModelSnapshot {
    let modelID: String
    let modelName: String
    let modelInfo: ModelInfo?
    let normalizedModelInfo: ModelInfo?
    let resolvedSettings: ResolvedModelSettings?
}

struct ChatStreamingHistorySettings {
    let shouldTruncateMessages: Bool
    let maxHistoryMessages: Int?
    let modelContextWindow: Int
    let reservedOutputTokens: Int
}

enum ChatStreamingSessionResolver {
    static func providerSnapshot(
        for thread: ConversationModelThreadEntity,
        providers: [ProviderConfigEntity]
    ) throws -> ChatStreamingProviderSnapshot {
        let providerID = thread.providerID
        let providerEntity = providers.first(where: { $0.id == providerID })
        let providerType = providerEntity.flatMap { ProviderType(rawValue: $0.typeRaw) }
            ?? ProviderType(rawValue: providerID)
        let providerConfig = try providerEntity?.toDomain()

        return ChatStreamingProviderSnapshot(
            providerID: providerID,
            entity: providerEntity,
            type: providerType,
            config: providerConfig
        )
    }

    static func modelSnapshot(
        for thread: ConversationModelThreadEntity,
        threadControls: GenerationControls,
        providerSnapshot: ChatStreamingProviderSnapshot,
        managedAgentSyntheticModelID: (String, GenerationControls) -> String,
        effectiveModelID: (String, ProviderConfigEntity?, ProviderType?) -> String,
        migrateThreadModelIDIfNeeded: (ConversationModelThreadEntity, String) -> Void,
        resolvedModelInfo: (String, ProviderConfigEntity?, ProviderType?) -> ModelInfo?,
        normalizedModelInfo: (ModelInfo, ProviderType?) -> ModelInfo
    ) -> ChatStreamingModelSnapshot {
        let modelID: String
        let modelName: String

        if providerSnapshot.type == .claudeManagedAgents {
            var mergedControls = threadControls
            providerSnapshot.entity?.applyClaudeManagedDefaults(into: &mergedControls)
            let syntheticModelID = managedAgentSyntheticModelID(providerSnapshot.providerID, mergedControls)
            migrateThreadModelIDIfNeeded(thread, syntheticModelID)
            modelID = ClaudeManagedAgentRuntime.resolvedRuntimeModelID(
                threadModelID: syntheticModelID,
                controls: mergedControls
            )
            modelName = ClaudeManagedAgentRuntime.resolvedDisplayName(
                threadModelID: thread.modelID,
                controls: threadControls
            )
        } else {
            modelID = effectiveModelID(thread.modelID, providerSnapshot.entity, providerSnapshot.type)
            migrateThreadModelIDIfNeeded(thread, modelID)
            modelName = modelID
        }

        let modelInfo = resolvedModelInfo(modelID, providerSnapshot.entity, providerSnapshot.type)
        let normalized = modelInfo.map { normalizedModelInfo($0, providerSnapshot.type) }
        let resolvedSettings = normalized.map {
            ModelSettingsResolver.resolve(model: $0, providerType: providerSnapshot.type)
        }
        let resolvedName = providerSnapshot.type == .claudeManagedAgents
            ? modelName
            : (normalized?.name ?? modelName)

        return ChatStreamingModelSnapshot(
            modelID: modelID,
            modelName: resolvedName,
            modelInfo: modelInfo,
            normalizedModelInfo: normalized,
            resolvedSettings: resolvedSettings
        )
    }

    static func requestControls(
        threadControls: GenerationControls,
        assistant: AssistantEntity?,
        modelSnapshot: ChatStreamingModelSnapshot,
        providerType: ProviderType?,
        isAgentModeActive: Bool,
        automaticContextCacheControls: (ProviderType?, String, ModelCapability?) -> ContextCacheControls?,
        sanitizeProviderSpecific: (ProviderType?, inout GenerationControls) -> Void,
        injectCodexThreadPersistence: (inout GenerationControls) -> Void,
        injectClaudeManagedAgentSessionPersistence: (inout GenerationControls) -> Void
    ) -> GenerationControls {
        var controlsToUse = GenerationControlsResolver.resolvedForRequest(
            base: threadControls,
            assistantTemperature: assistant?.temperature,
            assistantMaxOutputTokens: assistant?.maxOutputTokens,
            modelMaxOutputTokens: modelSnapshot.resolvedSettings?.maxOutputTokens
        )
        controlsToUse.contextCache = automaticContextCacheControls(
            providerType,
            modelSnapshot.modelID,
            modelSnapshot.resolvedSettings?.capabilities
        )
        sanitizeProviderSpecific(providerType, &controlsToUse)
        injectCodexThreadPersistence(&controlsToUse)
        injectClaudeManagedAgentSessionPersistence(&controlsToUse)
        controlsToUse.agentMode = ChatView.resolvedAgentModeControls(active: isAgentModeActive)
        return controlsToUse
    }

    static func historySettings(
        assistant: AssistantEntity?,
        modelSnapshot: ChatStreamingModelSnapshot,
        controls: GenerationControls
    ) -> ChatStreamingHistorySettings {
        let modelContextWindow = modelSnapshot.resolvedSettings?.contextWindow ?? 128000
        return ChatStreamingHistorySettings(
            shouldTruncateMessages: assistant?.truncateMessages ?? false,
            maxHistoryMessages: assistant?.maxHistoryMessages,
            modelContextWindow: modelContextWindow,
            reservedOutputTokens: ModelContextUsageSupport.reservedOutputTokens(
                for: modelSnapshot.resolvedSettings?.modelType,
                requestedMaxTokens: controls.maxTokens
            )
        )
    }

    static func shouldOfferBuiltinSearch(
        providerType: ProviderType?,
        modelID: String,
        resolvedModelSettings: ResolvedModelSettings?,
        controls: GenerationControls,
        webSearchPluginEnabled: Bool,
        webSearchPluginConfigured: Bool
    ) -> Bool {
        let supportsBuiltinSearchPlugin = !ManagedAgentUIVisibilitySupport.hidesInternalUI(providerType: providerType)
            && (resolvedModelSettings?.capabilities.contains(.toolCalling) == true)
            && webSearchPluginEnabled
            && webSearchPluginConfigured
        let supportsNativeSearch = ModelCapabilityRegistry.supportsWebSearch(for: providerType, modelID: modelID)
        return supportsBuiltinSearchPlugin
            && (!supportsNativeSearch || controls.searchPlugin?.preferJinSearch == true)
    }
}
