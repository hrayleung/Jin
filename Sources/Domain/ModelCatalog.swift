import Foundation

/// Unified source of truth for all known model metadata.
///
/// Capabilities, context windows, reasoning configs, and fully-supported status
/// are all defined here — no string-matching heuristics in adapters or UI code.
///
/// Usage:
///   ModelCatalog.entry(for: "claude-sonnet-4-6", provider: .anthropic)
///   ModelCatalog.modelInfo(for: "anthropic/claude-sonnet-4-6", provider: .cloudflareAIGateway)
///   ModelCatalog.seededModels(for: .anthropic)  // ordered list for first-launch seeding
struct ModelCatalogEntry {
    let capabilities: ModelCapability
    let contextWindow: Int
    let reasoningConfig: ModelReasoningConfig?
    let isFullySupported: Bool
    let displayName: String
}

enum ModelCatalog {
    private static let conservativeUnknownCapabilities: ModelCapability = [.streaming, .toolCalling]
    private static let conservativeUnknownContextWindow = 128_000

    // MARK: - Internal record

    private struct Record {
        let id: String
        let displayName: String
        let capabilities: ModelCapability
        let contextWindow: Int
        let reasoningConfig: ModelReasoningConfig?
        let isFullySupported: Bool
        /// Whether this model appears in the first-launch seed list.
        let isSeeded: Bool

        var entry: ModelCatalogEntry {
            ModelCatalogEntry(
                capabilities: capabilities,
                contextWindow: contextWindow,
                reasoningConfig: reasoningConfig,
                isFullySupported: isFullySupported,
                displayName: displayName
            )
        }
    }

    // MARK: - Public API

    /// Returns the catalog entry for a known (provider, modelID) pair, or nil for unknown models.
    static func entry(for modelID: String, provider: ProviderType) -> ModelCatalogEntry? {
        let lower = modelID.lowercased()
        // openaiWebSocket shares the openai model set.
        let lookupProvider: ProviderType = (provider == .openaiWebSocket) ? .openai : provider
        return lookup[lookupProvider]?[lower]?.entry
    }

    /// Returns a ModelInfo for the given model ID. Uses catalog data for known models;
    /// unknown IDs always receive conservative defaults.
    static func modelInfo(for modelID: String, provider: ProviderType, name: String? = nil) -> ModelInfo {
        if let e = entry(for: modelID, provider: provider) {
            return ModelInfo(
                id: modelID,
                name: name ?? e.displayName,
                capabilities: e.capabilities,
                contextWindow: e.contextWindow,
                reasoningConfig: e.reasoningConfig
            )
        }
        return fallbackModelInfo(id: modelID, name: name ?? modelID, provider: provider)
    }

    /// Returns true if the model is "fully supported" (eligible for the ✦ badge).
    static func isFullySupported(modelID: String, provider: ProviderType) -> Bool {
        entry(for: modelID, provider: provider)?.isFullySupported ?? false
    }

    /// Returns the ordered list of seed models for a provider (used on first launch).
    /// openaiWebSocket mirrors openai's list.
    static func seededModels(for provider: ProviderType) -> [ModelInfo] {
        let source: ProviderType = (provider == .openaiWebSocket) ? .openai : provider
        return (orderedRecords[source] ?? [])
            .filter { $0.isSeeded }
            .map { r in
                ModelInfo(
                    id: r.id,
                    name: r.displayName,
                    capabilities: r.capabilities,
                    contextWindow: r.contextWindow,
                    reasoningConfig: r.reasoningConfig
                )
            }
    }

    // MARK: - Cloudflare compound IDs
    // Cloudflare models are exact, fully-qualified IDs (for example `openai/gpt-5.2`).
    // Do not infer by prefix/substring from non-Cloudflare providers.

    // MARK: - Fallback for unknown models

    /// Used when the model ID is not in the catalog.
    /// Keep this conservative: exact-ID catalog entries are the only source of rich capabilities.
    private static func fallbackModelInfo(id: String, name: String, provider: ProviderType) -> ModelInfo {
        _ = provider
        return ModelInfo(
            id: id,
            name: name,
            capabilities: conservativeUnknownCapabilities,
            contextWindow: conservativeUnknownContextWindow,
            reasoningConfig: nil
        )
    }

    // MARK: - Index

    private static let lookup: [ProviderType: [String: Record]] = {
        var result: [ProviderType: [String: Record]] = [:]
        for (provider, records) in orderedRecords {
            result[provider] = Dictionary(records.map { ($0.id.lowercased(), $0) },
                                          uniquingKeysWith: { first, _ in first })
        }
        return result
    }()

    private static let orderedRecords: [ProviderType: [Record]] = [
        .openai: openAIRecords,
        .codexAppServer: codexAppServerRecords,
        .cloudflareAIGateway: cloudflareAIGatewayRecords,
        .anthropic: anthropicRecords,
        .perplexity: perplexityRecords,
        .xai: xAIRecords,
        .deepseek: deepSeekRecords,
        .fireworks: fireworksRecords,
        .cerebras: cerebrasRecords,
        .gemini: geminiRecords,
        .vertexai: vertexAIRecords,
        .openrouter: openRouterRecords,
    ]
}

// MARK: - Model Record Tables

extension ModelCatalog {

    // MARK: OpenAI (also used for openaiWebSocket via the entry/seededModels redirects)

    private static let openAIRecords: [Record] = [
        // Seeded — appear in the model picker on first launch
        Record(id: "gpt-5.2", displayName: "GPT-5.2",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 400_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "gpt-5.2-2025-12-11", displayName: "GPT-5.2 (2025-12-11)",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 400_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "gpt-5.3-codex", displayName: "GPT-5.3 Codex",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 400_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "gpt-4o", displayName: "GPT-4o",
               capabilities: [.streaming, .toolCalling, .vision, .promptCaching, .nativePDF],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        // Catalog-only — recognized when fetched via the API
        // Note: gpt-5 (unversioned) does not have nativePDF; use gpt-5.2+ for native PDF.
        Record(id: "gpt-5", displayName: "GPT-5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 400_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "o3", displayName: "o3",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "o4", displayName: "o4",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "gpt-4o-audio-preview", displayName: "GPT-4o Audio Preview",
               capabilities: [.streaming, .toolCalling, .audio],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "gpt-4o-audio-preview-2024-10-01", displayName: "GPT-4o Audio Preview (2024-10-01)",
               capabilities: [.streaming, .toolCalling, .audio],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "gpt-4o-mini-audio-preview", displayName: "GPT-4o Mini Audio Preview",
               capabilities: [.streaming, .toolCalling, .audio],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "gpt-4o-mini-audio-preview-2024-12-17", displayName: "GPT-4o Mini Audio Preview (2024-12-17)",
               capabilities: [.streaming, .toolCalling, .audio],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "gpt-4o-realtime-preview", displayName: "GPT-4o Realtime Preview",
               capabilities: [.streaming, .toolCalling, .audio],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "gpt-4o-realtime-preview-2024-10-01", displayName: "GPT-4o Realtime Preview (2024-10-01)",
               capabilities: [.streaming, .toolCalling, .audio],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "gpt-4o-realtime-preview-2024-12-17", displayName: "GPT-4o Realtime Preview (2024-12-17)",
               capabilities: [.streaming, .toolCalling, .audio],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "gpt-4o-mini-realtime-preview", displayName: "GPT-4o Mini Realtime Preview",
               capabilities: [.streaming, .toolCalling, .audio],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "gpt-4o-mini-realtime-preview-2024-12-17", displayName: "GPT-4o Mini Realtime Preview (2024-12-17)",
               capabilities: [.streaming, .toolCalling, .audio],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "gpt-realtime", displayName: "GPT Realtime",
               capabilities: [.streaming, .toolCalling, .audio],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "gpt-realtime-mini", displayName: "GPT Realtime Mini",
               capabilities: [.streaming, .toolCalling, .audio],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
    ]

    // MARK: Codex App Server

    private static let codexAppServerRecords: [Record] = [
        Record(id: "gpt-5.1-codex", displayName: "GPT-5.1 Codex",
               capabilities: [.streaming, .reasoning],
               contextWindow: 256_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: false, isSeeded: true),
    ]

    // MARK: Cloudflare AI Gateway

    private static let cloudflareAIGatewayRecords: [Record] = [
        // OpenAI
        Record(id: "openai/gpt-5", displayName: "GPT-5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 400_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "openai/gpt-5.2", displayName: "GPT-5.2",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 400_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "openai/gpt-5.2-2025-12-11", displayName: "GPT-5.2 (2025-12-11)",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 400_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "openai/gpt-5.3-codex", displayName: "GPT-5.3 Codex",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 400_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "openai/gpt-4o", displayName: "GPT-4o",
               capabilities: [.streaming, .toolCalling, .vision, .promptCaching],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "openai/o3", displayName: "o3",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "openai/o4", displayName: "o4",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),

        // Anthropic
        Record(id: "anthropic/claude-opus-4-6", displayName: "Claude Opus 4.6",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
        Record(id: "anthropic/claude-sonnet-4-6", displayName: "Claude Sonnet 4.6",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "anthropic/claude-opus-4-5-20251101", displayName: "Claude Opus 4.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 1024),
               isFullySupported: true, isSeeded: false),
        Record(id: "anthropic/claude-sonnet-4-5-20250929", displayName: "Claude Sonnet 4.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 1024),
               isFullySupported: true, isSeeded: false),
        Record(id: "anthropic/claude-haiku-4-5-20251001", displayName: "Claude Haiku 4.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 1024),
               isFullySupported: true, isSeeded: false),
        Record(id: "anthropic/claude-opus-4", displayName: "Claude Opus 4",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
        Record(id: "anthropic/claude-sonnet-4", displayName: "Claude Sonnet 4",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "anthropic/claude-haiku-4", displayName: "Claude Haiku 4",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 1024),
               isFullySupported: true, isSeeded: false),

        // xAI (chat/text models only)
        Record(id: "grok/grok-4-1-fast", displayName: "Grok 4.1 Fast",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 2_000_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "grok/grok-4-1", displayName: "Grok 4.1",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 2_000_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "grok/grok-4-1-fast-non-reasoning", displayName: "Grok 4.1 Fast (Non-Reasoning)",
               capabilities: [.streaming, .toolCalling, .vision, .promptCaching],
               contextWindow: 2_000_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "grok/grok-4-1-fast-reasoning", displayName: "Grok 4.1 Fast (Reasoning)",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 2_000_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),

        // DeepSeek
        Record(id: "deepseek/deepseek-chat", displayName: "DeepSeek Chat",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "deepseek/deepseek-reasoner", displayName: "DeepSeek Reasoner",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
        Record(id: "deepseek/deepseek-v3.2-exp", displayName: "DeepSeek V3.2 Exp",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),

        // Cerebras
        Record(id: "cerebras/zai-glm-4.7", displayName: "ZAI GLM-4.7",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),

        // Perplexity
        Record(id: "perplexity/sonar", displayName: "Sonar",
               capabilities: [.streaming, .vision],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "perplexity/sonar-pro", displayName: "Sonar Pro",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 200_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "perplexity/sonar-reasoning", displayName: "Sonar Reasoning",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "perplexity/sonar-reasoning-pro", displayName: "Sonar Reasoning Pro",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "perplexity/sonar-deep-research", displayName: "Sonar Deep Research",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),

        // Vertex via Cloudflare compound path
        Record(id: "google-vertex-ai/google/gemini-3", displayName: "Gemini 3",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "google-vertex-ai/google/gemini-3-pro", displayName: "Gemini 3 Pro",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: false, isSeeded: false),
        Record(id: "google-vertex-ai/google/gemini-3-pro-preview", displayName: "Gemini 3 Pro (Preview)",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "google-vertex-ai/google/gemini-3.1-pro-preview", displayName: "Gemini 3.1 Pro (Preview)",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "google-vertex-ai/google/gemini-3-flash-preview", displayName: "Gemini 3 Flash (Preview)",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "google-vertex-ai/google/gemini-2.5", displayName: "Gemini 2.5",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 2048),
               isFullySupported: true, isSeeded: false),
        Record(id: "google-vertex-ai/google/gemini-2.5-pro", displayName: "Gemini 2.5 Pro",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 2048),
               isFullySupported: true, isSeeded: false),
        Record(id: "google-vertex-ai/google/gemini-2.5-flash", displayName: "Gemini 2.5 Flash",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 2048),
               isFullySupported: false, isSeeded: false),
        Record(id: "google-vertex-ai/google/gemini-2.5-flash-lite", displayName: "Gemini 2.5 Flash Lite",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 2048),
               isFullySupported: false, isSeeded: false),

        // AI Studio via Cloudflare compound path
        Record(id: "google-ai-studio/gemini-3", displayName: "Gemini 3",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
        Record(id: "google-ai-studio/gemini-3-pro", displayName: "Gemini 3 Pro",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: false, isSeeded: false),
        Record(id: "google-ai-studio/gemini-3-pro-preview", displayName: "Gemini 3 Pro (Preview)",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
        Record(id: "google-ai-studio/gemini-3.1-pro-preview", displayName: "Gemini 3.1 Pro (Preview)",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
        Record(id: "google-ai-studio/gemini-3-flash-preview", displayName: "Gemini 3 Flash (Preview)",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
    ]

    // MARK: Anthropic

    private static let anthropicRecords: [Record] = [
        // Seeded
        Record(id: "claude-opus-4-6", displayName: "Claude Opus 4.6",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "claude-opus-4-5-20251101", displayName: "Claude Opus 4.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 1024),
               isFullySupported: true, isSeeded: true),
        Record(id: "claude-sonnet-4-5-20250929", displayName: "Claude Sonnet 4.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 1024),
               isFullySupported: true, isSeeded: true),
        Record(id: "claude-haiku-4-5-20251001", displayName: "Claude Haiku 4.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 1024),
               isFullySupported: true, isSeeded: true),
        // Catalog-only
        Record(id: "claude-opus-4", displayName: "Claude Opus 4",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
        Record(id: "claude-sonnet-4", displayName: "Claude Sonnet 4",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "claude-haiku-4", displayName: "Claude Haiku 4",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 1024),
               isFullySupported: true, isSeeded: false),
    ]

    // MARK: Perplexity

    private static let perplexityRecords: [Record] = [
        // Seeded (capabilities match DefaultProviderSeeds; nativePDF added per JinModelSupport)
        Record(id: "sonar", displayName: "Sonar",
               capabilities: [.streaming, .vision, .nativePDF],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: true),
        Record(id: "sonar-pro", displayName: "Sonar Pro",
               capabilities: [.streaming, .toolCalling, .vision, .nativePDF],
               contextWindow: 200_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "sonar-reasoning-pro", displayName: "Sonar Reasoning Pro",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .nativePDF],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "sonar-deep-research", displayName: "Sonar Deep Research",
               capabilities: [.streaming, .toolCalling, .reasoning, .nativePDF],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        // Catalog-only
        Record(id: "sonar-reasoning", displayName: "Sonar Reasoning",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .nativePDF],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
    ]

    // MARK: xAI

    private static let xAIRecords: [Record] = [
        // Seeded
        Record(id: "grok-4-1-fast", displayName: "Grok 4.1 Fast",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 2_000_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "grok-4-1", displayName: "Grok 4.1",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 2_000_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "grok-imagine-image", displayName: "Grok Imagine Image",
               capabilities: [.imageGeneration],
               contextWindow: 32_768,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "grok-imagine-image-pro", displayName: "Grok Imagine Image Pro",
               capabilities: [.imageGeneration],
               contextWindow: 32_768,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "grok-2-image-1212", displayName: "Grok 2 Image",
               capabilities: [.imageGeneration],
               contextWindow: 131_072,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "grok-imagine-video", displayName: "Grok Imagine Video",
               capabilities: [.videoGeneration],
               contextWindow: 32_768,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        // Catalog-only
        Record(id: "grok-4-1-fast-non-reasoning", displayName: "Grok 4.1 Fast (Non-Reasoning)",
               capabilities: [.streaming, .toolCalling, .vision, .promptCaching, .nativePDF],
               contextWindow: 2_000_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "grok-4-1-fast-reasoning", displayName: "Grok 4.1 Fast (Reasoning)",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 2_000_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
    ]

    // MARK: DeepSeek

    private static let deepSeekRecords: [Record] = [
        Record(id: "deepseek-chat", displayName: "DeepSeek Chat",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "deepseek-reasoner", displayName: "DeepSeek Reasoner",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: "deepseek-v3.2-exp", displayName: "DeepSeek V3.2 Exp",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
    ]

    // MARK: Fireworks

    private static let fireworksRecords: [Record] = [
        // Seeded (canonical "fireworks/" prefix IDs)
        Record(id: "fireworks/glm-5", displayName: "GLM-5",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 202_800,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "fireworks/minimax-m2p5", displayName: "MiniMax M2.5",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 196_600,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "fireworks/kimi-k2p5", displayName: "Kimi K2.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_100,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "fireworks/glm-4p7", displayName: "GLM-4.7",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 202_800,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        // Alternate "accounts/fireworks/models/" IDs (same capabilities, not seeded separately)
        Record(id: "accounts/fireworks/models/glm-5", displayName: "GLM-5",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 202_800,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "accounts/fireworks/models/minimax-m2p5", displayName: "MiniMax M2.5",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 196_600,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "accounts/fireworks/models/kimi-k2p5", displayName: "Kimi K2.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_100,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "accounts/fireworks/models/glm-4p7", displayName: "GLM-4.7",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 202_800,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        // Additional models present in ModelSettingsResolver (not fully supported)
        Record(id: "fireworks/minimax-m2p1", displayName: "MiniMax M2.1",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 204_800,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: false, isSeeded: false),
        Record(id: "accounts/fireworks/models/minimax-m2p1", displayName: "MiniMax M2.1",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 204_800,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: false, isSeeded: false),
        Record(id: "fireworks/minimax-m2", displayName: "MiniMax M2",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 196_600,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: false, isSeeded: false),
        Record(id: "accounts/fireworks/models/minimax-m2", displayName: "MiniMax M2",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 196_600,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: false, isSeeded: false),
    ]

    // MARK: Cerebras

    private static let cerebrasRecords: [Record] = [
        Record(id: "zai-glm-4.7", displayName: "ZAI GLM-4.7",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
    ]

    // MARK: Gemini (AI Studio)

    private static let geminiRecords: [Record] = [
        // Seeded
        Record(id: "gemini-3-pro-preview", displayName: "Gemini 3 Pro (Preview)",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "gemini-3.1-pro-preview", displayName: "Gemini 3.1 Pro (Preview)",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "gemini-3-pro-image-preview", displayName: "Gemini 3 Pro Image (Preview)",
               capabilities: [.streaming, .vision, .reasoning, .imageGeneration],
               contextWindow: 65_536,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "gemini-3.1-flash-image-preview", displayName: "Gemini 3.1 Flash Image (Preview)",
               capabilities: [.streaming, .vision, .reasoning, .nativePDF, .imageGeneration],
               contextWindow: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .minimal),
               isFullySupported: true, isSeeded: true),
        Record(id: "gemini-3-flash-preview", displayName: "Gemini 3 Flash (Preview)",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "gemini-2.5-flash-image", displayName: "Gemini 2.5 Flash Image",
               capabilities: [.streaming, .vision, .imageGeneration],
               contextWindow: 32_768,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        // Catalog-only
        Record(id: "gemini-3", displayName: "Gemini 3",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
        Record(id: "gemini-3-pro", displayName: "Gemini 3 Pro",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: false, isSeeded: false),
        Record(id: "veo-2", displayName: "Veo 2",
               capabilities: [.videoGeneration],
               contextWindow: 32_768,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "veo-3", displayName: "Veo 3",
               capabilities: [.videoGeneration],
               contextWindow: 32_768,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
    ]

    // MARK: Vertex AI

    private static let vertexAIRecords: [Record] = [
        // Seeded
        Record(id: "gemini-3-pro-preview", displayName: "Gemini 3 Pro (Preview)",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "gemini-3.1-pro-preview", displayName: "Gemini 3.1 Pro (Preview)",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "gemini-3-pro-image-preview", displayName: "Gemini 3 Pro Image (Preview)",
               capabilities: [.streaming, .vision, .reasoning, .imageGeneration],
               contextWindow: 65_536,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "gemini-3.1-flash-image-preview", displayName: "Gemini 3.1 Flash Image (Preview)",
               capabilities: [.streaming, .vision, .reasoning, .nativePDF, .imageGeneration],
               contextWindow: 131_072,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "gemini-3-flash-preview", displayName: "Gemini 3 Flash (Preview)",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 2048),
               isFullySupported: true, isSeeded: true),
        Record(id: "gemini-2.5-flash-image", displayName: "Gemini 2.5 Flash Image",
               capabilities: [.streaming, .vision, .imageGeneration],
               contextWindow: 32_768,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        // Catalog-only
        Record(id: "gemini-3", displayName: "Gemini 3",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "gemini-3-pro", displayName: "Gemini 3 Pro",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: false, isSeeded: false),
        Record(id: "gemini-2.5", displayName: "Gemini 2.5",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 2048),
               isFullySupported: true, isSeeded: false),
        Record(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 2048),
               isFullySupported: false, isSeeded: false),
        Record(id: "gemini-2.5-flash-lite", displayName: "Gemini 2.5 Flash Lite",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 2048),
               isFullySupported: false, isSeeded: false),
        Record(id: "veo-2", displayName: "Veo 2",
               capabilities: [.videoGeneration],
               contextWindow: 32_768,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "veo-3", displayName: "Veo 3",
               capabilities: [.videoGeneration],
               contextWindow: 32_768,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
    ]

    // MARK: OpenRouter

    private static let openRouterRecords: [Record] = [
        Record(id: "google/gemini-3-pro-preview", displayName: "Gemini 3 Pro (Preview)",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
        Record(id: "google/gemini-3.1-pro-preview", displayName: "Gemini 3.1 Pro (Preview)",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
    ]
}
