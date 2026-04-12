import SwiftUI
import SwiftData

// MARK: - Model Info & Media Generation Capabilities

extension ChatView {

    // MARK: - Model Info

    var selectedModelInfo: ModelInfo? {
        if providerType == .claudeManagedAgents {
            let threadControls = activeModelThread.flatMap(storedGenerationControls(for:))
            if let model = ChatModelCapabilitySupport.resolvedClaudeManagedAgentModelInfo(
                threadModelID: conversationEntity.modelID,
                providerEntity: currentProvider,
                threadControls: threadControls
            ) {
                return ChatModelCapabilitySupport.normalizedSelectedModelInfo(
                    model,
                    providerType: providerType
                )
            }
        }

        guard let model = ChatModelCapabilitySupport.resolvedModelInfo(
            modelID: conversationEntity.modelID,
            providerEntity: currentProvider,
            providerType: providerType
        ) else {
            return nil
        }

        return ChatModelCapabilitySupport.normalizedSelectedModelInfo(
            model,
            providerType: providerType
        )
    }

    var resolvedModelSettings: ResolvedModelSettings? {
        guard let model = selectedModelInfo else { return nil }
        return ModelSettingsResolver.resolve(model: model, providerType: providerType)
    }

    var lowerModelID: String {
        conversationEntity.modelID.lowercased()
    }

    func resolvedModelInfo(
        for modelID: String,
        providerEntity: ProviderConfigEntity?,
        providerType: ProviderType?,
        availableModels: [ModelInfo]? = nil
    ) -> ModelInfo? {
        ChatModelCapabilitySupport.resolvedModelInfo(
            modelID: modelID,
            providerEntity: providerEntity,
            providerType: providerType,
            availableModels: availableModels
        )
    }

    func effectiveModelID(
        for modelID: String,
        providerEntity: ProviderConfigEntity?,
        providerType: ProviderType?,
        availableModels: [ModelInfo]? = nil
    ) -> String {
        if providerType == .claudeManagedAgents {
            let threadControls = activeModelThread.flatMap(storedGenerationControls(for:))
            let resolvedControls = resolvedClaudeManagedControls(
                for: providerEntity?.id ?? conversationEntity.providerID,
                threadControls: threadControls
            )
            return ClaudeManagedAgentRuntime.resolvedRuntimeModelID(
                threadModelID: modelID,
                controls: resolvedControls
            )
        }
        return ChatModelCapabilitySupport.effectiveModelID(
            modelID: modelID,
            providerEntity: providerEntity,
            providerType: providerType,
            availableModels: availableModels
        )
    }

    func migrateThreadModelIDIfNeeded(
        _ thread: ConversationModelThreadEntity,
        resolvedModelID: String
    ) {
        guard resolvedModelID != thread.modelID else { return }
        thread.modelID = resolvedModelID
        if conversationEntity.activeThreadID == thread.id {
            conversationEntity.modelID = resolvedModelID
        }
        conversationEntity.updatedAt = Date()
        try? modelContext.save()
    }

    func canonicalModelID(for providerID: String, modelID: String) -> String {
        let providerEntity = providers.first(where: { $0.id == providerID })
        let providerType = providerEntity.flatMap { ProviderType(rawValue: $0.typeRaw) }
        if providerType == .claudeManagedAgents {
            let threadControls = sortedModelThreads.first(where: {
                $0.providerID == providerID && $0.modelID == modelID
            }).flatMap(storedGenerationControls(for:))
            return ClaudeManagedAgentResolutionSupport.canonicalManagedThreadModelID(
                providerID: providerID,
                requestedModelID: modelID,
                fallbackControls: controls,
                storedThreadControls: threadControls,
                applyProviderDefaults: { candidateControls in
                    providers.first(where: { $0.id == providerID })?.applyClaudeManagedDefaults(into: &candidateControls)
                }
            )
        }
        return effectiveModelID(
            for: modelID,
            providerEntity: providerEntity,
            providerType: providerType,
            availableModels: providerEntity?.allModels
        )
    }

    func canonicalizeThreadModelIDIfNeeded(_ thread: ConversationModelThreadEntity) {
        let resolved = canonicalModelID(for: thread.providerID, modelID: thread.modelID)
        migrateThreadModelIDIfNeeded(thread, resolvedModelID: resolved)
    }

    func normalizedSelectedModelInfo(_ model: ModelInfo) -> ModelInfo {
        ChatModelCapabilitySupport.normalizedSelectedModelInfo(
            model,
            providerType: providerType
        )
    }

    func normalizedFireworksModelInfo(_ model: ModelInfo) -> ModelInfo {
        ChatModelCapabilitySupport.normalizedFireworksModelInfo(model)
    }

    func normalizedModelInfo(_ model: ModelInfo, for providerType: ProviderType?) -> ModelInfo {
        ChatModelCapabilitySupport.normalizedSelectedModelInfo(model, providerType: providerType)
    }

    // MARK: - Media Generation Capability

    var isImageGenerationModelID: Bool {
        ChatModelCapabilitySupport.isImageGenerationModelID(
            providerType: providerType,
            lowerModelID: lowerModelID,
            openAIImageGenerationModelIDs: Self.openAIImageGenerationModelIDs,
            xAIImageGenerationModelIDs: Self.xAIImageGenerationModelIDs,
            geminiImageGenerationModelIDs: Self.geminiImageGenerationModelIDs
        )
    }

    var isVideoGenerationModelID: Bool {
        ChatModelCapabilitySupport.isVideoGenerationModelID(
            providerType: providerType,
            lowerModelID: lowerModelID,
            xAIVideoGenerationModelIDs: Self.xAIVideoGenerationModelIDs,
            googleVideoGenerationModelIDs: Self.googleVideoGenerationModelIDs
        )
    }

    var supportsNativePDF: Bool {
        ChatModelCapabilitySupport.supportsNativePDF(
            supportsMediaGenerationControl: supportsMediaGenerationControl,
            providerType: providerType,
            resolvedModelSettings: resolvedModelSettings,
            lowerModelID: lowerModelID
        )
    }

    var supportsVision: Bool {
        ChatModelCapabilitySupport.supportsVision(
            resolvedModelSettings: resolvedModelSettings,
            supportsImageGenerationControl: supportsImageGenerationControl,
            supportsVideoGenerationControl: supportsVideoGenerationControl
        )
    }

    var supportsAudioInput: Bool {
        ChatModelCapabilitySupport.supportsAudioInput(
            isMistralTranscriptionOnlyModelID: isMistralTranscriptionOnlyModelID,
            resolvedModelSettings: resolvedModelSettings,
            supportsMediaGenerationControl: supportsMediaGenerationControl,
            providerType: providerType,
            lowerModelID: lowerModelID,
            openAIAudioInputModelIDs: Self.openAIAudioInputModelIDs,
            mistralAudioInputModelIDs: Self.mistralAudioInputModelIDs,
            geminiAudioInputModelIDs: Self.geminiAudioInputModelIDs,
            compatibleAudioInputModelIDs: Self.compatibleAudioInputModelIDs,
            fireworksAudioInputModelIDs: Self.fireworksAudioInputModelIDs
        )
    }

    var isMistralTranscriptionOnlyModelID: Bool {
        ChatModelCapabilitySupport.isMistralTranscriptionOnlyModelID(
            providerType: providerType,
            lowerModelID: lowerModelID,
            mistralTranscriptionOnlyModelIDs: Self.mistralTranscriptionOnlyModelIDs
        )
    }

    var supportsImageGenerationControl: Bool {
        resolvedModelSettings?.capabilities.contains(.imageGeneration) == true || isImageGenerationModelID
    }

    var supportsVideoGenerationControl: Bool {
        resolvedModelSettings?.capabilities.contains(.videoGeneration) == true || isVideoGenerationModelID
    }

    var supportsMediaGenerationControl: Bool {
        supportsImageGenerationControl || supportsVideoGenerationControl
    }

    var supportsImageGenerationWebSearch: Bool {
        ChatModelCapabilitySupport.supportsImageGenerationWebSearch(
            supportsImageGenerationControl: supportsImageGenerationControl,
            resolvedModelSettings: resolvedModelSettings,
            providerType: providerType,
            conversationModelID: conversationEntity.modelID
        )
    }

    var supportsPDFProcessingControl: Bool {
        guard providerType != .codexAppServer else { return false }
        return true
    }

    var supportsCurrentModelImageSizeControl: Bool {
        ChatModelCapabilitySupport.supportsCurrentModelImageSizeControl(lowerModelID: lowerModelID)
    }

    var supportedCurrentModelImageAspectRatios: [ImageAspectRatio] {
        ChatModelCapabilitySupport.supportedCurrentModelImageAspectRatios(lowerModelID: lowerModelID)
    }

    var supportedCurrentModelImageSizes: [ImageOutputSize] {
        ChatModelCapabilitySupport.supportedCurrentModelImageSizes(lowerModelID: lowerModelID)
    }

    var isImageGenerationConfigured: Bool {
        ChatModelCapabilitySupport.isImageGenerationConfigured(
            providerType: providerType,
            controls: controls
        )
    }

    var imageGenerationBadgeText: String? {
        ChatModelCapabilitySupport.imageGenerationBadgeText(
            supportsImageGenerationControl: supportsImageGenerationControl,
            providerType: providerType,
            controls: controls,
            isImageGenerationConfigured: isImageGenerationConfigured
        )
    }

    var imageGenerationHelpText: String {
        ChatModelCapabilitySupport.imageGenerationHelpText(
            supportsImageGenerationControl: supportsImageGenerationControl,
            providerType: providerType,
            controls: controls,
            isImageGenerationConfigured: isImageGenerationConfigured
        )
    }

    var isVideoGenerationConfigured: Bool {
        ChatModelCapabilitySupport.isVideoGenerationConfigured(
            providerType: providerType,
            controls: controls
        )
    }

    var videoGenerationBadgeText: String? {
        ChatModelCapabilitySupport.videoGenerationBadgeText(
            supportsVideoGenerationControl: supportsVideoGenerationControl,
            providerType: providerType,
            controls: controls,
            isVideoGenerationConfigured: isVideoGenerationConfigured
        )
    }

    var videoGenerationHelpText: String {
        ChatModelCapabilitySupport.videoGenerationHelpText(
            supportsVideoGenerationControl: supportsVideoGenerationControl,
            providerType: providerType,
            controls: controls,
            isVideoGenerationConfigured: isVideoGenerationConfigured
        )
    }
}
