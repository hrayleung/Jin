import Foundation

/// Configuration for OpenAI Chat Completions-compatible providers.
///
/// Thin adapters (DeepSeek, Cerebras, Fireworks, …) differ mainly by reasoning
/// field name and capability bits. Route new generic providers through
/// `OpenAICompatibleAdapter` + a profile instead of a new actor file trio.
struct OpenAICompatibleProfile: Sendable, Equatable {
    var reasoningField: OpenAIChatCompletionsReasoningField
    var capabilities: ModelCapability
    /// When true, streaming is forced off whenever tools are present (Cerebras).
    var disablesStreamingWithTools: Bool

    /// Broad default for generic OpenAI-compatible endpoints (includes audio).
    static let `default` = OpenAICompatibleProfile(
        reasoningField: .reasoningOrReasoningContent,
        capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning],
        disablesStreamingWithTools: false
    )

    /// Common chat profile without audio (Together, SambaNova, Meta, …).
    static let chatWithVision = OpenAICompatibleProfile(
        reasoningField: .reasoningOrReasoningContent,
        capabilities: [.streaming, .toolCalling, .vision, .reasoning],
        disablesStreamingWithTools: false
    )

    init(
        reasoningField: OpenAIChatCompletionsReasoningField,
        capabilities: ModelCapability,
        disablesStreamingWithTools: Bool = false
    ) {
        self.reasoningField = reasoningField
        self.capabilities = capabilities
        self.disablesStreamingWithTools = disablesStreamingWithTools
    }

    /// Profile for known provider types that speak OpenAI-compatible chat completions.
    /// Returns `nil` for providers with specialist adapters (Anthropic, Gemini, …).
    static func profile(for providerType: ProviderType) -> OpenAICompatibleProfile? {
        switch providerType {
        case .openaiCompatible, .githubCopilot, .cloudflareAIGateway, .vercelAIGateway,
             .groq, .mistral, .deepinfra, .zhipuCodingPlan, .minimax, .minimaxCodingPlan,
             .mimoTokenPlanOpenAI:
            return .default

        case .perplexity, .together, .zyphra, .meta, .sambanova:
            return .chatWithVision

        case .deepseek:
            return OpenAICompatibleProfile(
                reasoningField: .reasoningContent,
                capabilities: [.streaming, .toolCalling, .reasoning]
            )

        case .fireworks:
            return OpenAICompatibleProfile(
                reasoningField: .reasoningContent,
                capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning]
            )

        case .cerebras:
            return OpenAICompatibleProfile(
                reasoningField: .reasoning,
                capabilities: [.streaming, .toolCalling, .reasoning],
                disablesStreamingWithTools: true
            )

        case .morphllm:
            return OpenAICompatibleProfile(
                reasoningField: .reasoning,
                capabilities: [.streaming]
            )

        case .opencodeGo:
            return OpenAICompatibleProfile(
                reasoningField: .reasoningOrReasoningContent,
                capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning]
            )

        case .databricks:
            return OpenAICompatibleProfile(
                reasoningField: .reasoningOrReasoningContent,
                capabilities: [.streaming, .toolCalling, .vision, .reasoning]
            )

        case .openai, .openaiWebSocket, .openrouter, .anthropic, .claudeManagedAgents,
             .mimoTokenPlanAnthropic, .kimiForCoding, .cohere, .xai, .gemini, .vertexai:
            return nil
        }
    }
}

extension OpenAIChatCompletionsReasoningField: Equatable {}
