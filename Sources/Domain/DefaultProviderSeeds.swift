import Foundation

/// Default provider and model seed data used on first launch.
///
/// Extracted from ContentView to keep the view focused on UI concerns.
/// ContentView calls `DefaultProviderSeeds.allProviders()` when bootstrapping
/// a fresh install.
enum DefaultProviderSeeds {

    static func allProviders() -> [ProviderConfig] {
        [
            openAI,
            groq,
            openRouter,
            anthropic,
            cohere,
            mistral,
            perplexity,
            deepInfra,
            xAI,
            deepSeek,
            fireworks,
            gemini,
            vertexAI,
        ]
    }

    // MARK: - Individual Providers

    static var openAI: ProviderConfig {
        ProviderConfig(
            id: "openai",
            name: "OpenAI",
            type: .openai,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .openai),
            baseURL: ProviderType.openai.defaultBaseURL,
            models: [
                ModelInfo(
                    id: "gpt-5.2",
                    name: "GPT-5.2",
                    capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
                    contextWindow: 400000,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                ),
                ModelInfo(
                    id: "gpt-5.2-2025-12-11",
                    name: "GPT-5.2 (2025-12-11)",
                    capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
                    contextWindow: 400000,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                ),
                ModelInfo(
                    id: "gpt-4o",
                    name: "GPT-4o",
                    capabilities: [.streaming, .toolCalling, .vision, .promptCaching],
                    contextWindow: 128000,
                    reasoningConfig: nil
                ),
            ]
        )
    }

    static var groq: ProviderConfig {
        ProviderConfig(
            id: "groq",
            name: "Groq",
            type: .groq,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .groq),
            baseURL: ProviderType.groq.defaultBaseURL,
            models: []
        )
    }

    static var openRouter: ProviderConfig {
        ProviderConfig(
            id: "openrouter",
            name: "OpenRouter",
            type: .openrouter,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .openrouter),
            baseURL: ProviderType.openrouter.defaultBaseURL,
            models: []
        )
    }

    static var anthropic: ProviderConfig {
        ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .anthropic),
            baseURL: ProviderType.anthropic.defaultBaseURL,
            models: [
                ModelInfo(
                    id: "claude-opus-4-6",
                    name: "Claude Opus 4.6",
                    capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
                    contextWindow: 200000,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high)
                ),
                ModelInfo(
                    id: "claude-sonnet-4-6",
                    name: "Claude Sonnet 4.6",
                    capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
                    contextWindow: 200000,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                ),
                ModelInfo(
                    id: "claude-opus-4-5-20251101",
                    name: "Claude Opus 4.5",
                    capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
                    contextWindow: 200000,
                    reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 1024)
                ),
                ModelInfo(
                    id: "claude-sonnet-4-5-20250929",
                    name: "Claude Sonnet 4.5",
                    capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
                    contextWindow: 200000,
                    reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 1024)
                ),
                ModelInfo(
                    id: "claude-haiku-4-5-20251001",
                    name: "Claude Haiku 4.5",
                    capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
                    contextWindow: 200000,
                    reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 1024)
                ),
            ]
        )
    }

    static var cohere: ProviderConfig {
        ProviderConfig(
            id: "cohere",
            name: "Cohere",
            type: .cohere,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .cohere),
            baseURL: ProviderType.cohere.defaultBaseURL,
            models: []
        )
    }

    static var mistral: ProviderConfig {
        ProviderConfig(
            id: "mistral",
            name: "Mistral",
            type: .mistral,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .mistral),
            baseURL: ProviderType.mistral.defaultBaseURL,
            models: []
        )
    }

    static var perplexity: ProviderConfig {
        ProviderConfig(
            id: "perplexity",
            name: "Perplexity",
            type: .perplexity,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .perplexity),
            baseURL: ProviderType.perplexity.defaultBaseURL,
            models: [
                ModelInfo(
                    id: "sonar",
                    name: "Sonar",
                    capabilities: [.streaming, .vision],
                    contextWindow: 128_000,
                    reasoningConfig: nil
                ),
                ModelInfo(
                    id: "sonar-pro",
                    name: "Sonar Pro",
                    capabilities: [.streaming, .toolCalling, .vision],
                    contextWindow: 200_000,
                    reasoningConfig: nil
                ),
                ModelInfo(
                    id: "sonar-reasoning-pro",
                    name: "Sonar Reasoning Pro",
                    capabilities: [.streaming, .toolCalling, .vision, .reasoning],
                    contextWindow: 128_000,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                ),
                ModelInfo(
                    id: "sonar-deep-research",
                    name: "Sonar Deep Research",
                    capabilities: [.streaming, .toolCalling, .vision, .reasoning],
                    contextWindow: 128_000,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                ),
            ]
        )
    }

    static var deepInfra: ProviderConfig {
        ProviderConfig(
            id: "deepinfra",
            name: "DeepInfra",
            type: .deepinfra,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .deepinfra),
            baseURL: ProviderType.deepinfra.defaultBaseURL,
            models: []
        )
    }

    static var xAI: ProviderConfig {
        ProviderConfig(
            id: "xai",
            name: "xAI",
            type: .xai,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .xai),
            baseURL: ProviderType.xai.defaultBaseURL,
            models: [
                ModelInfo(
                    id: "grok-4-1-fast",
                    name: "Grok 4.1 Fast",
                    capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
                    contextWindow: 128000,
                    reasoningConfig: nil
                ),
                ModelInfo(
                    id: "grok-4-1",
                    name: "Grok 4.1",
                    capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
                    contextWindow: 128000,
                    reasoningConfig: nil
                ),
                ModelInfo(
                    id: "grok-imagine-image",
                    name: "Grok Imagine Image",
                    capabilities: [.imageGeneration],
                    contextWindow: 32768,
                    reasoningConfig: nil
                ),
                ModelInfo(
                    id: "grok-2-image-1212",
                    name: "Grok 2 Image",
                    capabilities: [.imageGeneration],
                    contextWindow: 32768,
                    reasoningConfig: nil
                ),
                ModelInfo(
                    id: "grok-imagine-video",
                    name: "Grok Imagine Video",
                    capabilities: [.videoGeneration],
                    contextWindow: 32768,
                    reasoningConfig: nil
                ),
            ]
        )
    }

    static var deepSeek: ProviderConfig {
        ProviderConfig(
            id: "deepseek",
            name: "DeepSeek",
            type: .deepseek,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .deepseek),
            baseURL: ProviderType.deepseek.defaultBaseURL,
            models: [
                ModelInfo(
                    id: "deepseek-chat",
                    name: "DeepSeek Chat",
                    capabilities: [.streaming, .toolCalling],
                    contextWindow: 128000,
                    reasoningConfig: nil
                ),
                ModelInfo(
                    id: "deepseek-reasoner",
                    name: "DeepSeek Reasoner",
                    capabilities: [.streaming, .toolCalling, .reasoning],
                    contextWindow: 128000,
                    reasoningConfig: ModelReasoningConfig(type: .toggle)
                ),
                ModelInfo(
                    id: "deepseek-v3.2-exp",
                    name: "DeepSeek V3.2 Exp",
                    capabilities: [.streaming, .toolCalling],
                    contextWindow: 128000,
                    reasoningConfig: nil
                ),
            ]
        )
    }

    static var fireworks: ProviderConfig {
        ProviderConfig(
            id: "fireworks",
            name: "Fireworks",
            type: .fireworks,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .fireworks),
            baseURL: ProviderType.fireworks.defaultBaseURL,
            models: [
                ModelInfo(
                    id: "fireworks/glm-5",
                    name: "GLM-5",
                    capabilities: [.streaming, .toolCalling, .reasoning],
                    contextWindow: 202_800,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                ),
                ModelInfo(
                    id: "fireworks/minimax-m2p5",
                    name: "MiniMax M2.5",
                    capabilities: [.streaming, .toolCalling, .reasoning],
                    contextWindow: 204_800,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                ),
                ModelInfo(
                    id: "fireworks/kimi-k2p5",
                    name: "Kimi K2.5",
                    capabilities: [.streaming, .toolCalling, .vision, .reasoning],
                    contextWindow: 262_100,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                ),
                ModelInfo(
                    id: "fireworks/glm-4p7",
                    name: "GLM-4.7",
                    capabilities: [.streaming, .toolCalling, .reasoning],
                    contextWindow: 202_800,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                ),
            ]
        )
    }

    static var gemini: ProviderConfig {
        ProviderConfig(
            id: "gemini",
            name: "Gemini (AI Studio)",
            type: .gemini,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .gemini),
            baseURL: ProviderType.gemini.defaultBaseURL,
            models: [
                ModelInfo(
                    id: "gemini-3-pro-preview",
                    name: "Gemini 3 Pro (Preview)",
                    capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF],
                    contextWindow: 1_048_576,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high)
                ),
                ModelInfo(
                    id: "gemini-3-pro-image-preview",
                    name: "Gemini 3 Pro Image (Preview)",
                    capabilities: [.streaming, .vision, .reasoning, .imageGeneration],
                    contextWindow: 1_048_576,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high)
                ),
                ModelInfo(
                    id: "gemini-3-flash-preview",
                    name: "Gemini 3 Flash (Preview)",
                    capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF],
                    contextWindow: 1_048_576,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high)
                ),
                ModelInfo(
                    id: "gemini-2.5-flash-image",
                    name: "Gemini 2.5 Flash Image",
                    capabilities: [.streaming, .vision, .imageGeneration],
                    contextWindow: 1_048_576,
                    reasoningConfig: nil
                ),
            ]
        )
    }

    static var vertexAI: ProviderConfig {
        ProviderConfig(
            id: "vertexai",
            name: "Vertex AI",
            type: .vertexai,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .vertexai),
            models: [
                ModelInfo(
                    id: "gemini-3-pro-preview",
                    name: "Gemini 3 Pro (Preview)",
                    capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF],
                    contextWindow: 1_048_576,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                ),
                ModelInfo(
                    id: "gemini-3-pro-image-preview",
                    name: "Gemini 3 Pro Image (Preview)",
                    capabilities: [.streaming, .vision, .reasoning, .imageGeneration],
                    contextWindow: 1_048_576,
                    reasoningConfig: nil
                ),
                ModelInfo(
                    id: "gemini-3-flash-preview",
                    name: "Gemini 3 Flash (Preview)",
                    capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF],
                    contextWindow: 1_048_576,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                ),
                ModelInfo(
                    id: "gemini-2.5-pro",
                    name: "Gemini 2.5 Pro",
                    capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
                    contextWindow: 1_048_576,
                    reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 2048)
                ),
                ModelInfo(
                    id: "gemini-2.5-flash-image",
                    name: "Gemini 2.5 Flash Image",
                    capabilities: [.streaming, .vision, .imageGeneration],
                    contextWindow: 1_048_576,
                    reasoningConfig: nil
                ),
            ]
        )
    }
}
