import Foundation
import SwiftData

enum ChatModelSelectionSupport {
    static let preferredAnthropicModelOrder: [String] = [
        "claude-opus-5",
        "claude-opus-4-8",
        "claude-opus-4-7",
        "claude-opus-4-6",
        "claude-sonnet-5",
        "claude-sonnet-4-6",
        "claude-sonnet-4-5-20250929",
    ]
    static let preferredFireworksModelOrder: [String] = [
        "kimi-k3",
        "kimi-k2p6",
        "qwen3p6-plus",
        "deepseek-v4-pro",
        "deepseek-v3p2",
        "kimi-k2-instruct-0905",
        "glm-5p2",
        "glm-5",
        "minimax-m2p5",
        "kimi-k2p5",
        "glm-4p7"
    ]
    static let preferredDeepInfraModelOrder: [String] = [
        "moonshotai/Kimi-K3",
        "zai-org/GLM-5.2",
        "zai-org/GLM-5.1",
        "Qwen/Qwen3.6-35B-A3B",
        "nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning",
        "zai-org/GLM-5",
        "Qwen/Qwen3.5-397B-A17B",
        "Qwen/Qwen3.5-122B-A10B",
        "Qwen/Qwen3.5-35B-A3B",
        "Qwen/Qwen3.5-27B",
        "Qwen/Qwen3.5-9B",
    ]
    static let preferredTogetherModelOrder: [String] = [
        "moonshotai/Kimi-K3",
        "moonshotai/Kimi-K2.5",
        "zai-org/GLM-5.2",
        "zai-org/GLM-5",
        "deepseek-ai/DeepSeek-V3.1",
        "openai/gpt-oss-120b",
        "Qwen/Qwen3.5-397B-A17B",
        "Qwen/Qwen3-235B-A22B-Instruct-2507-tput",
        "Qwen/Qwen3-Coder-Next-FP8",
    ]
    static let preferredBasetenModelOrder: [String] = [
        "moonshotai/Kimi-K3",
        "moonshotai/Kimi-K2.7-Code",
        "moonshotai/Kimi-K2.6",
        "thinkingmachines/inkling",
        "deepseek-ai/DeepSeek-V4-Pro",
        "zai-org/GLM-5.2",
        "zai-org/GLM-5.2-Fast",
        "zai-org/GLM-4.7",
        "nvidia/NVIDIA-Nemotron-3-Ultra-550B-A55B",
        "openai/gpt-oss-120b",
    ]
    static let preferredModalModelOrder: [String] = [
        "moonshotai/Kimi-K3",
        "thinkingmachines/Inkling-NVFP4",
    ]
    static let preferredDatabricksModelOrder: [String] = [
        "databricks-claude-sonnet-4-6",
        "databricks-claude-opus-5",
        "databricks-claude-opus-4-8",
        "databricks-gpt-oss-120b",
        "databricks-gemini-3-1-pro",
        "databricks-meta-llama-3-3-70b-instruct",
        "databricks-llama-4-maverick",
        "databricks-qwen35-122b-a10b",
    ]

    static func preferredFireworksModelID(in models: [ModelInfo]) -> String? {
        for canonicalID in preferredFireworksModelOrder {
            if canonicalID == "deepseek-v4-pro" {
                for preferredID in fireworksDeepSeekV4ProPreferredModelIDs {
                    if let modelID = models.first(where: { $0.id.lowercased() == preferredID })?.id {
                        return modelID
                    }
                }
                continue
            }

            if let modelID = models.first(where: { fireworksCanonicalModelID($0.id) == canonicalID })?.id {
                return modelID
            }
        }
        return nil
    }

    static func preferredDeepInfraModelID(in models: [ModelInfo]) -> String? {
        for preferredID in preferredDeepInfraModelOrder {
            if let modelID = models.first(where: { $0.id == preferredID })?.id {
                return modelID
            }
        }
        return nil
    }

    static func preferredModelID(
        in models: [ModelInfo],
        providerID: String,
        providers: [ProviderConfigEntity],
        geminiPreferredModelOrder: [String]
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
            for preferredID in preferredAnthropicModelOrder {
                if let modelID = models.first(where: { $0.id == preferredID })?.id {
                    return modelID
                }
            }
            return nil
        case .perplexity:
            return models.first(where: { $0.id == "sonar-pro" })?.id
                ?? models.first(where: { $0.id == "sonar" })?.id
        case .deepseek:
            return models.first(where: { $0.id == "deepseek-chat" })?.id
                ?? models.first(where: { $0.id == "deepseek-reasoner" })?.id
        case .zhipuCodingPlan:
            return models.first(where: { $0.id.lowercased() == "glm-5.2[1m]" })?.id
                ?? models.first(where: { $0.id.lowercased() == "glm-5.2" })?.id
                ?? models.first(where: { $0.id.lowercased() == "glm-5" })?.id
                ?? models.first(where: { $0.id.lowercased() == "glm-4.7" })?.id
        case .minimax, .minimaxCodingPlan:
            return models.first(where: { $0.id == "MiniMax-M2.7" })?.id
                ?? models.first(where: { $0.id == "MiniMax-M2.5" })?.id
        case .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI:
            return models.first(where: { $0.id == "mimo-v2.5-pro" })?.id
                ?? models.first(where: { $0.id == "mimo-v2.5" })?.id
                ?? models.first(where: { $0.id == "mimo-v2-pro" })?.id
                ?? models.first(where: { $0.id == "mimo-v2-omni" })?.id
        case .kimiForCoding:
            return models.first(where: { $0.id == "k3" })?.id
                ?? models.first(where: { $0.id == "kimi-for-coding" })?.id
        case .deepinfra:
            return preferredDeepInfraModelID(in: models)
        case .together:
            for preferredID in preferredTogetherModelOrder {
                if let modelID = models.first(where: { $0.id == preferredID })?.id {
                    return modelID
                }
            }
            return nil
        case .baseten:
            for preferredID in preferredBasetenModelOrder {
                if let modelID = models.first(where: { $0.id == preferredID })?.id {
                    return modelID
                }
            }
            return nil
        case .modal:
            for preferredID in preferredModalModelOrder {
                if let modelID = models.first(where: { $0.id == preferredID })?.id {
                    return modelID
                }
            }
            return nil
        case .fireworks:
            return preferredFireworksModelID(in: models)
        case .cerebras:
            return models.first(where: { $0.id == "qwen-3-235b-a22b-instruct-2507" })?.id
                ?? models.first(where: { $0.id == "zai-glm-4.7" })?.id
                ?? models.first(where: { $0.id == "gpt-oss-120b" })?.id
        case .sambanova:
            return models.first(where: { $0.id == "MiniMax-M2.5" })?.id
                ?? models.first(where: { $0.id == "DeepSeek-V3.1" })?.id
                ?? models.first(where: { $0.id == "gpt-oss-120b" })?.id
                ?? models.first(where: { $0.id == "Qwen3-235B-A22B-Instruct-2507" })?.id
        case .databricks:
            for preferredID in preferredDatabricksModelOrder {
                if let modelID = models.first(where: { $0.id == preferredID })?.id {
                    return modelID
                }
            }
            return nil
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
        case .meta:
            return models.first(where: { $0.id == "muse-spark-1.1" })?.id
        case .zyphra:
            return models.first(where: { $0.id == "zyphra/ZAYA1-8B" })?.id
                ?? models.first(where: { $0.id == "moonshotai/Kimi-K2.6" })?.id
                ?? models.first(where: { $0.id == "deepseek-ai/DeepSeek-V3.2" })?.id
        case .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq, .cohere, .mistral, .xai, .vertexai:
            return nil
        }
    }
}
