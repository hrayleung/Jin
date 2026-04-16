import Foundation
import SwiftData

enum ChatModelSelectionSupport {
    @MainActor
    static func setProvider(
        providerID: String,
        activeThread: ConversationModelThreadEntity?,
        providers: [ProviderConfigEntity],
        modelContext: ModelContext,
        clearCodexThreadPersistence: (ConversationModelThreadEntity) -> Void,
        clearClaudeManagedAgentSessionPersistence: (ConversationModelThreadEntity) -> Void,
        synchronizeLegacyConversationModelFields: (ConversationModelThreadEntity) -> Void,
        normalizeControlsForCurrentSelection: () -> Void,
        preferredModelID: ([ModelInfo], String) -> String?
    ) {
        guard let activeThread else { return }
        guard providerID != activeThread.providerID else { return }

        guard let provider = providers.first(where: { $0.id == providerID }) else { return }
        let models = provider.selectableModels

        clearCodexThreadPersistence(activeThread)
        clearClaudeManagedAgentSessionPersistence(activeThread)
        activeThread.providerID = providerID

        if ProviderType(rawValue: provider.typeRaw) == .claudeManagedAgents {
            if let managedModelID = models.first?.id {
                activeThread.modelID = managedModelID
            }
            synchronizeLegacyConversationModelFields(activeThread)
            normalizeControlsForCurrentSelection()
            try? modelContext.save()
            return
        }

        guard !models.isEmpty else { return }

        if let preferredModelID = preferredModelID(models, providerID) {
            activeThread.modelID = preferredModelID
            synchronizeLegacyConversationModelFields(activeThread)
            normalizeControlsForCurrentSelection()
            try? modelContext.save()
            return
        }

        activeThread.modelID = models.first?.id ?? activeThread.modelID
        synchronizeLegacyConversationModelFields(activeThread)
        normalizeControlsForCurrentSelection()
        try? modelContext.save()
    }

    @MainActor
    static func setModel(
        modelID: String,
        activeThread: ConversationModelThreadEntity?,
        modelContext: ModelContext,
        providerTypeForProviderID: (String) -> ProviderType?,
        canonicalModelID: (String, String) -> String,
        clearClaudeManagedAgentSessionPersistence: (ConversationModelThreadEntity) -> Void,
        synchronizeLegacyConversationModelFields: (ConversationModelThreadEntity) -> Void,
        normalizeControlsForCurrentSelection: () -> Void
    ) {
        guard let activeThread else { return }
        let resolvedModelID = canonicalModelID(activeThread.providerID, modelID)
        guard resolvedModelID != canonicalModelID(activeThread.providerID, activeThread.modelID) else { return }
        if providerTypeForProviderID(activeThread.providerID) != .claudeManagedAgents {
            clearClaudeManagedAgentSessionPersistence(activeThread)
        }
        activeThread.modelID = resolvedModelID
        synchronizeLegacyConversationModelFields(activeThread)
        normalizeControlsForCurrentSelection()
        try? modelContext.save()
    }

    @MainActor
    static func setProviderAndModel(
        providerID: String,
        modelID: String,
        activeThread: ConversationModelThreadEntity?,
        sortedThreads: [ConversationModelThreadEntity],
        clearCodexThreadPersistence: (ConversationModelThreadEntity) -> Void,
        clearClaudeManagedAgentSessionPersistence: (ConversationModelThreadEntity) -> Void,
        canonicalModelID: (String, String) -> String,
        addOrActivateThread: (String, String) -> Void,
        activateThread: (ConversationModelThreadEntity) -> Void,
        synchronizeLegacyConversationModelFields: (ConversationModelThreadEntity) -> Void,
        normalizeControlsForCurrentSelection: () -> Void,
        persistControlsToConversation: () -> Void
    ) {
        let resolvedModelID = canonicalModelID(providerID, modelID)
        if let existing = sortedThreads.first(where: {
            $0.providerID == providerID && canonicalModelID($0.providerID, $0.modelID) == resolvedModelID
        }) {
            existing.isSelected = true
            activateThread(existing)
            return
        }

        guard let activeThread else {
            addOrActivateThread(providerID, resolvedModelID)
            return
        }

        if providerID != activeThread.providerID {
            clearCodexThreadPersistence(activeThread)
            clearClaudeManagedAgentSessionPersistence(activeThread)
        }
        activeThread.providerID = providerID
        activeThread.modelID = resolvedModelID
        activeThread.updatedAt = Date()
        synchronizeLegacyConversationModelFields(activeThread)
        normalizeControlsForCurrentSelection()
        persistControlsToConversation()
    }

    static func preferredModelID(
        in models: [ModelInfo],
        providerID: String,
        providers: [ProviderConfigEntity],
        geminiPreferredModelOrder: [String],
        isFireworksModelID: (String, String) -> Bool
    ) -> String? {
        guard let provider = providers.first(where: { $0.id == providerID }),
              let type = ProviderType(rawValue: provider.typeRaw) else {
            return nil
        }

        switch type {
        case .openai, .openaiWebSocket:
            return models.first(where: { $0.id == "gpt-5.2" })?.id
        case .githubCopilot:
            return nil
        case .anthropic, .claudeManagedAgents:
            return models.first(where: { $0.id == "claude-opus-4-7" })?.id
                ?? models.first(where: { $0.id == "claude-opus-4-6" })?.id
                ?? models.first(where: { $0.id == "claude-sonnet-4-6" })?.id
                ?? models.first(where: { $0.id == "claude-sonnet-4-5-20250929" })?.id
        case .perplexity:
            return models.first(where: { $0.id == "sonar-pro" })?.id
                ?? models.first(where: { $0.id == "sonar" })?.id
        case .deepseek:
            return models.first(where: { $0.id == "deepseek-chat" })?.id
                ?? models.first(where: { $0.id == "deepseek-reasoner" })?.id
        case .zhipuCodingPlan:
            return models.first(where: { $0.id.lowercased() == "glm-5" })?.id
                ?? models.first(where: { $0.id.lowercased() == "glm-4.7" })?.id
        case .minimax, .minimaxCodingPlan:
            return models.first(where: { $0.id == "MiniMax-M2.7" })?.id
                ?? models.first(where: { $0.id == "MiniMax-M2.5" })?.id
        case .deepinfra:
            return models.first(where: { $0.id == "zai-org/GLM-5" })?.id
                ?? models.first(where: { $0.id == "Qwen/Qwen3.5-397B-A17B" })?.id
                ?? models.first(where: { $0.id == "Qwen/Qwen3.5-122B-A10B" })?.id
                ?? models.first(where: { $0.id == "Qwen/Qwen3.5-35B-A3B" })?.id
                ?? models.first(where: { $0.id == "Qwen/Qwen3.5-27B" })?.id
                ?? models.first(where: { $0.id == "Qwen/Qwen3.5-9B" })?.id
        case .together:
            return models.first(where: { $0.id == "moonshotai/Kimi-K2.5" })?.id
                ?? models.first(where: { $0.id == "zai-org/GLM-5" })?.id
                ?? models.first(where: { $0.id == "deepseek-ai/DeepSeek-V3.1" })?.id
                ?? models.first(where: { $0.id == "openai/gpt-oss-120b" })?.id
                ?? models.first(where: { $0.id == "Qwen/Qwen3.5-397B-A17B" })?.id
                ?? models.first(where: { $0.id == "Qwen/Qwen3-235B-A22B-Instruct-2507-tput" })?.id
                ?? models.first(where: { $0.id == "Qwen/Qwen3-Coder-Next-FP8" })?.id
        case .fireworks:
            return models.first(where: { isFireworksModelID($0.id, "qwen3p6-plus") })?.id
                ?? models.first(where: { isFireworksModelID($0.id, "deepseek-v3p2") })?.id
                ?? models.first(where: { isFireworksModelID($0.id, "kimi-k2-instruct-0905") })?.id
                ?? models.first(where: { isFireworksModelID($0.id, "glm-5") })?.id
                ?? models.first(where: { isFireworksModelID($0.id, "minimax-m2p5") })?.id
                ?? models.first(where: { isFireworksModelID($0.id, "kimi-k2p5") })?.id
                ?? models.first(where: { isFireworksModelID($0.id, "glm-4p7") })?.id
        case .cerebras:
            return models.first(where: { $0.id == "qwen-3-235b-a22b-instruct-2507" })?.id
                ?? models.first(where: { $0.id == "zai-glm-4.7" })?.id
                ?? models.first(where: { $0.id == "gpt-oss-120b" })?.id
        case .sambanova:
            return models.first(where: { $0.id == "MiniMax-M2.5" })?.id
                ?? models.first(where: { $0.id == "DeepSeek-V3.1" })?.id
                ?? models.first(where: { $0.id == "gpt-oss-120b" })?.id
                ?? models.first(where: { $0.id == "Qwen3-235B-A22B-Instruct-2507" })?.id
        case .gemini:
            for preferredID in geminiPreferredModelOrder {
                if let exact = models.first(where: { $0.id.lowercased() == preferredID }) {
                    return exact.id
                }
            }
            return nil
        case .morphllm:
            return models.first(where: { $0.id == "auto" })?.id
                ?? models.first(where: { $0.id == "morph-v3-large" })?.id
        case .opencodeGo:
            return models.first?.id
        case .codexAppServer, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq, .cohere, .mistral, .xai, .vertexai:
            return nil
        }
    }
}
