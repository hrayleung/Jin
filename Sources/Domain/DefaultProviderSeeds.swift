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
            groq,
            openRouter,
            cloudflareAIGateway,
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
