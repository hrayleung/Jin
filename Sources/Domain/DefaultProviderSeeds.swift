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
            openAIWebSocket,
            codexAppServer,
            githubCopilot,
            groq,
            openRouter,
            cloudflareAIGateway,
            vercelAIGateway,
            anthropic,
            cohere,
            mistral,
            perplexity,
            deepInfra,
            together,
            xAI,
            deepSeek,
            zhipuCodingPlan,
            minimax,
            minimaxCodingPlan,
            fireworks,
            sambaNova,
            morphLLM,
            opencodeGo,
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
            models: ModelCatalog.seededModels(for: .openai)
        )
    }

    static var openAIWebSocket: ProviderConfig {
        ProviderConfig(
            id: "openai-websocket",
            name: "OpenAI (WebSocket)",
            type: .openaiWebSocket,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .openaiWebSocket),
            baseURL: ProviderType.openaiWebSocket.defaultBaseURL,
            models: ModelCatalog.seededModels(for: .openaiWebSocket)
        )
    }

    static var codexAppServer: ProviderConfig {
        ProviderConfig(
            id: "codex-app-server",
            name: "Codex App Server (Beta)",
            type: .codexAppServer,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .codexAppServer),
            baseURL: ProviderType.codexAppServer.defaultBaseURL,
            models: ModelCatalog.seededModels(for: .codexAppServer)
        )
    }

    static var githubCopilot: ProviderConfig {
        ProviderConfig(
            id: "github-copilot",
            name: "GitHub Copilot",
            type: .githubCopilot,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .githubCopilot),
            baseURL: ProviderType.githubCopilot.defaultBaseURL,
            models: []
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

    static var cloudflareAIGateway: ProviderConfig {
        ProviderConfig(
            id: "cloudflare-ai-gateway",
            name: "Cloudflare AI Gateway",
            type: .cloudflareAIGateway,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .cloudflareAIGateway),
            baseURL: ProviderType.cloudflareAIGateway.defaultBaseURL,
            models: []
        )
    }

    static var vercelAIGateway: ProviderConfig {
        ProviderConfig(
            id: "vercel-ai-gateway",
            name: "Vercel AI Gateway",
            type: .vercelAIGateway,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .vercelAIGateway),
            baseURL: ProviderType.vercelAIGateway.defaultBaseURL,
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
            models: ModelCatalog.seededModels(for: .anthropic)
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
            models: ModelCatalog.seededModels(for: .perplexity)
        )
    }

    static var deepInfra: ProviderConfig {
        ProviderConfig(
            id: "deepinfra",
            name: "DeepInfra",
            type: .deepinfra,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .deepinfra),
            baseURL: ProviderType.deepinfra.defaultBaseURL,
            models: ModelCatalog.seededModels(for: .deepinfra)
        )
    }

    static var together: ProviderConfig {
        ProviderConfig(
            id: "together",
            name: "Together AI",
            type: .together,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .together),
            baseURL: ProviderType.together.defaultBaseURL,
            models: ModelCatalog.seededModels(for: .together)
        )
    }

    static var xAI: ProviderConfig {
        ProviderConfig(
            id: "xai",
            name: "xAI",
            type: .xai,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .xai),
            baseURL: ProviderType.xai.defaultBaseURL,
            models: ModelCatalog.seededModels(for: .xai)
        )
    }

    static var deepSeek: ProviderConfig {
        ProviderConfig(
            id: "deepseek",
            name: "DeepSeek",
            type: .deepseek,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .deepseek),
            baseURL: ProviderType.deepseek.defaultBaseURL,
            models: ModelCatalog.seededModels(for: .deepseek)
        )
    }

    static var zhipuCodingPlan: ProviderConfig {
        ProviderConfig(
            id: "zhipu-coding-plan",
            name: "Zhipu Coding Plan",
            type: .zhipuCodingPlan,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .zhipuCodingPlan),
            baseURL: ProviderType.zhipuCodingPlan.defaultBaseURL,
            models: ModelCatalog.seededModels(for: .zhipuCodingPlan)
        )
    }

    static var minimax: ProviderConfig {
        ProviderConfig(
            id: "minimax",
            name: "MiniMax",
            type: .minimax,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .minimax),
            baseURL: ProviderType.minimax.defaultBaseURL,
            models: ModelCatalog.seededModels(for: .minimax)
        )
    }

    static var minimaxCodingPlan: ProviderConfig {
        ProviderConfig(
            id: "minimax-coding-plan",
            name: "MiniMax Coding Plan",
            type: .minimaxCodingPlan,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .minimaxCodingPlan),
            baseURL: ProviderType.minimaxCodingPlan.defaultBaseURL,
            models: ModelCatalog.seededModels(for: .minimaxCodingPlan)
        )
    }

    static var fireworks: ProviderConfig {
        ProviderConfig(
            id: "fireworks",
            name: "Fireworks",
            type: .fireworks,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .fireworks),
            baseURL: ProviderType.fireworks.defaultBaseURL,
            models: ModelCatalog.seededModels(for: .fireworks)
        )
    }

    static var sambaNova: ProviderConfig {
        ProviderConfig(
            id: "sambanova",
            name: "SambaNova",
            type: .sambanova,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .sambanova),
            baseURL: ProviderType.sambanova.defaultBaseURL,
            models: ModelCatalog.seededModels(for: .sambanova)
        )
    }

    static var morphLLM: ProviderConfig {
        ProviderConfig(
            id: "morphllm",
            name: "MorphLLM",
            type: .morphllm,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .morphllm),
            baseURL: ProviderType.morphllm.defaultBaseURL,
            models: ModelCatalog.seededModels(for: .morphllm)
        )
    }

    static var opencodeGo: ProviderConfig {
        ProviderConfig(
            id: "opencode-go",
            name: "OpenCode Go",
            type: .opencodeGo,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .opencodeGo),
            baseURL: "https://opencode.ai/zen/go/v1",
            models: ModelCatalog.seededModels(for: .opencodeGo)
        )
    }

    static var gemini: ProviderConfig {
        ProviderConfig(
            id: "gemini",
            name: "Gemini (AI Studio)",
            type: .gemini,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .gemini),
            baseURL: ProviderType.gemini.defaultBaseURL,
            models: ModelCatalog.seededModels(for: .gemini)
        )
    }

    static var vertexAI: ProviderConfig {
        ProviderConfig(
            id: "vertexai",
            name: "Vertex AI",
            type: .vertexai,
            iconID: LobeProviderIconCatalog.defaultIconID(for: .vertexai),
            models: ModelCatalog.seededModels(for: .vertexai)
        )
    }
}
