import Foundation

extension ChatMessagePreparationSupport {
    static func supportsImageGenerationModel(providerType: ProviderType?, lowerModelID: String) -> Bool {
        switch providerType {
        case .openai, .openaiWebSocket:
            return ChatView.openAIImageGenerationModelIDs.contains(lowerModelID)
        case .xai:
            return ChatView.xAIImageGenerationModelIDs.contains(lowerModelID)
        case .gemini, .vertexai:
            return ChatView.geminiImageGenerationModelIDs.contains(lowerModelID)
        case .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .anthropic, .claudeManagedAgents, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together,
             .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI,
             .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .zyphra, .none:
            return false
        }
    }

    static func supportsVideoGenerationModel(providerType: ProviderType?, lowerModelID: String) -> Bool {
        switch providerType {
        case .xai:
            return ChatView.xAIVideoGenerationModelIDs.contains(lowerModelID)
        case .gemini, .vertexai:
            return ChatView.googleVideoGenerationModelIDs.contains(lowerModelID)
        default:
            return false
        }
    }

    static func supportsNativePDFForThread(
        providerType: ProviderType?,
        lowerModelID: String,
        supportsMediaGenerationControl: Bool,
        resolvedModelSettings: ResolvedModelSettings?
    ) -> Bool {
        guard !supportsMediaGenerationControl else { return false }
        guard let providerType else { return false }

        switch providerType {
        case .openai, .openaiWebSocket, .anthropic, .claudeManagedAgents, .perplexity, .xai, .gemini, .vertexai:
            break
        case .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq,
             .cohere, .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan,
             .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI, .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo,
             .zyphra:
            return false
        }

        if resolvedModelSettings?.capabilities.contains(.nativePDF) == true {
            return true
        }

        return JinModelSupport.supportsNativePDF(providerType: providerType, modelID: lowerModelID)
    }

    static func messagePreparationProfile(
        for conversation: ConversationEntity,
        providers: [ProviderConfigEntity],
        controls: GenerationControls,
        mistralOCRPluginEnabled: Bool,
        mineruOCRPluginEnabled: Bool,
        deepSeekOCRPluginEnabled: Bool,
        openRouterOCRPluginEnabled: Bool,
        firecrawlOCRPluginEnabled: Bool,
        defaultPDFProcessingFallbackMode: PDFProcessingMode
    ) throws -> MessagePreparationProfile {
        let providerTypeSnapshot = providerType(forProviderID: conversation.providerID, providers: providers)
        let providerEntity = providers.first(where: { $0.id == conversation.providerID })
        let threadControls: GenerationControls
        do {
            threadControls = try JSONDecoder().decode(GenerationControls.self, from: conversation.modelConfigData)
        } catch {
            throw LLMError.decodingError(message: "Failed to load conversation settings: \(error.localizedDescription)")
        }
        let resolvedManagedControls: GenerationControls = {
            guard providerTypeSnapshot == .claudeManagedAgents else { return threadControls }
            var merged = threadControls
            providerEntity?.applyClaudeManagedDefaults(into: &merged)
            return merged
        }()
        let resolvedModelID: String
        if providerTypeSnapshot == .claudeManagedAgents {
            resolvedModelID = ClaudeManagedAgentRuntime.resolvedRuntimeModelID(
                threadModelID: conversation.modelID,
                controls: resolvedManagedControls
            )
        } else {
            resolvedModelID = ChatModelCapabilitySupport.effectiveModelID(
                modelID: conversation.modelID,
                providerEntity: providerEntity,
                providerType: providerTypeSnapshot
            )
        }
        let lowerModelID = resolvedModelID.lowercased()
        let modelInfo: ModelInfo? = {
            if providerTypeSnapshot == .claudeManagedAgents {
                return ChatModelCapabilitySupport.resolvedClaudeManagedAgentModelInfo(
                    threadModelID: conversation.modelID,
                    providerEntity: providerEntity,
                    threadControls: threadControls
                )
            }
            return ChatModelCapabilitySupport.resolvedModelInfo(
                modelID: conversation.modelID,
                providerEntity: providerEntity,
                providerType: providerTypeSnapshot
            )
        }()
        let normalizedModelInfoSnapshot = modelInfo.map {
            ChatModelCapabilitySupport.normalizedSelectedModelInfo($0, providerType: providerTypeSnapshot)
        }
        let resolvedModelSettings = normalizedModelInfoSnapshot.map {
            ModelSettingsResolver.resolve(model: $0, providerType: providerTypeSnapshot)
        }

        let supportsImageGen = (resolvedModelSettings?.capabilities.contains(.imageGeneration) == true)
            || supportsImageGenerationModel(providerType: providerTypeSnapshot, lowerModelID: lowerModelID)
        let supportsVideoGen = (resolvedModelSettings?.capabilities.contains(.videoGeneration) == true)
            || supportsVideoGenerationModel(providerType: providerTypeSnapshot, lowerModelID: lowerModelID)
        let supportsVideoInput = resolvedModelSettings?.capabilities.contains(.videoInput) == true
        let supportsMediaGen = supportsImageGen || supportsVideoGen
        let nativePDFSupported = supportsNativePDFForThread(
            providerType: providerTypeSnapshot,
            lowerModelID: lowerModelID,
            supportsMediaGenerationControl: supportsMediaGen,
            resolvedModelSettings: resolvedModelSettings
        )
        let supportsVision = (resolvedModelSettings?.capabilities.contains(.vision) == true)
            || supportsImageGen
            || supportsVideoGen
        let pdfMode = ChatModelCapabilitySupport.resolvedPDFProcessingMode(
            controls: resolvedManagedControls,
            supportsNativePDF: nativePDFSupported,
            defaultPDFProcessingFallbackMode: defaultPDFProcessingFallbackMode,
            mistralOCRPluginEnabled: mistralOCRPluginEnabled,
            mineruOCRPluginEnabled: mineruOCRPluginEnabled,
            deepSeekOCRPluginEnabled: deepSeekOCRPluginEnabled,
            openRouterOCRPluginEnabled: openRouterOCRPluginEnabled,
            firecrawlOCRPluginEnabled: firecrawlOCRPluginEnabled
        )
        let firecrawlPDFParserMode = resolvedManagedControls.firecrawlPDFParserMode ?? .ocr
        let modelName = modelInfo?.name
            ?? (providerTypeSnapshot == .claudeManagedAgents
                ? ClaudeManagedAgentRuntime.resolvedDisplayName(threadModelID: conversation.modelID, controls: resolvedManagedControls)
                : resolvedModelID)

        return MessagePreparationProfile(
            modelName: modelName,
            supportsVideoGenerationControl: supportsVideoGen,
            supportsVideoInput: supportsVideoInput,
            supportsMediaGenerationControl: supportsMediaGen,
            supportsNativePDF: nativePDFSupported,
            supportsVision: supportsVision,
            pdfProcessingMode: pdfMode,
            firecrawlPDFParserMode: firecrawlPDFParserMode
        )
    }
}
