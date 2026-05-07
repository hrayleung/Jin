import Foundation

// MARK: - Model Resolution

extension ContentView {
    func modelsForProvider(_ providerID: String) -> [ModelInfo] {
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            return []
        }
        return provider.selectableModels
    }

    func defaultModelID(for providerID: String) -> String {
        if let provider = providers.first(where: { $0.id == providerID }),
           ProviderType(rawValue: provider.typeRaw) == .claudeManagedAgents {
            return provider.selectableModels.first?.id
                ?? ClaudeManagedAgentRuntime.syntheticThreadModelID(
                    providerID: providerID,
                    agentID: provider.claudeManagedDefaultAgentID,
                    environmentID: provider.claudeManagedDefaultEnvironmentID
                )
        }

        let models = modelsForProvider(providerID)
        guard !models.isEmpty else {
            switch providerID {
            case "anthropic":
                return "claude-opus-4-7"
            case "xai":
                return "grok-4.3"
            case "deepseek":
                return "deepseek-chat"
            case "zhipu-coding-plan":
                return "glm-5"
            case "minimax", "minimax-coding-plan":
                return "MiniMax-M2.7"
            case "deepinfra":
                return "zai-org/GLM-5"
            case "fireworks":
                return "fireworks/kimi-k2p6"
            case "together":
                return "moonshotai/Kimi-K2.5"
            case "cerebras":
                return "qwen-3-235b-a22b-instruct-2507"
            case "sambanova":
                return "MiniMax-M2.5"
            case "vercel-ai-gateway":
                return "openai/gpt-5.2"
            case "vertexai":
                return "gemini-3-pro-preview"
            default:
                return "gpt-5.2"
            }
        }

        if providerID == "openai", let gpt52 = models.first(where: { $0.id == "gpt-5.2" }) {
            return gpt52.id
        }
        if providerID == "vercel-ai-gateway", let gpt52 = models.first(where: { $0.id == "openai/gpt-5.2" }) {
            return gpt52.id
        }
        if providerID == "vercel-ai-gateway", let gpt5 = models.first(where: { $0.id == "openai/gpt-5" }) {
            return gpt5.id
        }
        if providerID == "anthropic", let opus47 = models.first(where: { $0.id == "claude-opus-4-7" }) {
            return opus47.id
        }
        if providerID == "anthropic", let opus46 = models.first(where: { $0.id == "claude-opus-4-6" }) {
            return opus46.id
        }
        if providerID == "anthropic", let sonnet46 = models.first(where: { $0.id == "claude-sonnet-4-6" }) {
            return sonnet46.id
        }
        if providerID == "anthropic", let sonnet45 = models.first(where: { $0.id == "claude-sonnet-4-5-20250929" }) {
            return sonnet45.id
        }
        if providerID == "xai", let grok43 = models.first(where: { $0.id == "grok-4.3" }) {
            return grok43.id
        }
        if providerID == "xai", let grok420 = models.first(where: { $0.id == "grok-4.20" }) {
            return grok420.id
        }
        if providerID == "xai", let grok41Fast = models.first(where: { $0.id == "grok-4-1-fast" }) {
            return grok41Fast.id
        }
        if providerID == "deepseek", let deepseekChat = models.first(where: { $0.id == "deepseek-chat" }) {
            return deepseekChat.id
        }
        if providerID == "zhipu-coding-plan", let glm5 = models.first(where: { $0.id.lowercased() == "glm-5" }) {
            return glm5.id
        }
        if providerID == "zhipu-coding-plan", let glm47 = models.first(where: { $0.id.lowercased() == "glm-4.7" }) {
            return glm47.id
        }
        if providerID == "minimax" || providerID == "minimax-coding-plan",
           let m27 = models.first(where: { $0.id == "MiniMax-M2.7" }) {
            return m27.id
        }
        if providerID == "minimax" || providerID == "minimax-coding-plan",
           let m25 = models.first(where: { $0.id == "MiniMax-M2.5" }) {
            return m25.id
        }
        if providerID == "deepinfra", let glm51 = models.first(where: { $0.id == "zai-org/GLM-5.1" }) {
            return glm51.id
        }
        if providerID == "deepinfra", let qwen36 = models.first(where: { $0.id == "Qwen/Qwen3.6-35B-A3B" }) {
            return qwen36.id
        }
        if providerID == "deepinfra", let glm5 = models.first(where: { $0.id == "zai-org/GLM-5" }) {
            return glm5.id
        }
        if providerID == "deepinfra", let qwen397 = models.first(where: { $0.id == "Qwen/Qwen3.5-397B-A17B" }) {
            return qwen397.id
        }
        if providerID == "fireworks",
           let preferredFireworksModelID = ChatModelSelectionSupport.preferredFireworksModelID(in: models) {
            return preferredFireworksModelID
        }
        if providerID == "together", let kimiK2p5 = models.first(where: { $0.id == "moonshotai/Kimi-K2.5" }) {
            return kimiK2p5.id
        }
        if providerID == "together", let glm5 = models.first(where: { $0.id == "zai-org/GLM-5" }) {
            return glm5.id
        }
        if providerID == "cerebras",
           let qwen235 = models.first(where: { $0.id == "qwen-3-235b-a22b-instruct-2507" }) {
            return qwen235.id
        }
        if providerID == "cerebras", let glm47 = models.first(where: { $0.id == "zai-glm-4.7" }) {
            return glm47.id
        }
        if providerID == "sambanova", let miniMax = models.first(where: { $0.id == "MiniMax-M2.5" }) {
            return miniMax.id
        }
        if providerID == "sambanova", let deepSeekV31 = models.first(where: { $0.id == "DeepSeek-V3.1" }) {
            return deepSeekV31.id
        }
        if providerID == "vertexai", let gemini3Pro = models.first(where: { $0.id == "gemini-3-pro-preview" }) {
            return gemini3Pro.id
        }
        if let first = models.first?.id {
            return first
        }

        if providerID == "anthropic" {
            return "claude-opus-4-7"
        }
        if providerID == "vercel-ai-gateway" {
            return "openai/gpt-5.2"
        }
        return "gpt-5.2"
    }
}
