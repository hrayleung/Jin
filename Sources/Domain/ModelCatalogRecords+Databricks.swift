import Foundation

// MARK: - Databricks Foundation Model APIs

extension ModelCatalog {
    /// Databricks Model Serving (Foundation Model APIs) catalog.
    ///
    /// Databricks is workspace-scoped: each user points Jin at their own workspace host
    /// (for example `https://dbc-xxxx.cloud.databricks.com/serving-endpoints`) and the real
    /// set of available endpoints is discovered dynamically via
    /// `GET /api/2.0/serving-endpoints`. These records seed a representative set of the
    /// Databricks-hosted, pay-per-token foundation models and provide rich capability
    /// metadata (vision / reasoning / tools) for the ones a workspace commonly exposes.
    ///
    /// The serving-endpoint name is the OpenAI `model` value (for example
    /// `databricks-claude-sonnet-4-6`). Reasoning models accept `reasoning_effort`
    /// (`low`/`medium`/`high`). Model IDs and availability change per workspace and over
    /// time, so unseeded/unknown IDs fall back to conservative heuristics in the adapter.
    ///
    /// Verified against the Databricks "Databricks-hosted foundation models" supported-models
    /// docs (AWS/Azure/GCP), 2026-07.
    static let databricksRecords: [Record] = [
        // MARK: Seeded — appear in the model picker on first launch

        // Anthropic Claude (vision + reasoning via reasoning_effort)
        Record(id: "databricks-claude-sonnet-4-6", displayName: "Claude Sonnet 4.6",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "databricks-claude-opus-4-8", displayName: "Claude Opus 4.8",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),

        // OpenAI GPT-OSS (reasoning, text-only)
        Record(id: "databricks-gpt-oss-120b", displayName: "GPT-OSS 120B",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),

        // Google Gemini (vision + reasoning)
        Record(id: "databricks-gemini-3-1-pro", displayName: "Gemini 3.1 Pro",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),

        // Alibaba Qwen (reasoning, text-only)
        Record(id: "databricks-qwen35-122b-a10b", displayName: "Qwen3.5 122B A10B",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 256_000,
               maxOutputTokens: 8_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),

        // Meta Llama (vision, no reasoning)
        Record(id: "databricks-llama-4-maverick", displayName: "Llama 4 Maverick",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "databricks-meta-llama-3-3-70b-instruct", displayName: "Llama 3.3 70B Instruct",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),

        // Google Gemma (vision, no reasoning)
        Record(id: "databricks-gemma-3-12b", displayName: "Gemma 3 12B",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),

        // MARK: Catalog-only — recognized when fetched from the workspace

        // Anthropic Claude
        Record(id: "databricks-claude-sonnet-5", displayName: "Claude Sonnet 5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "databricks-claude-sonnet-4-5", displayName: "Claude Sonnet 4.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "databricks-claude-opus-4-7", displayName: "Claude Opus 4.7",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "databricks-claude-opus-4-6", displayName: "Claude Opus 4.6",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "databricks-claude-opus-4-5", displayName: "Claude Opus 4.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "databricks-claude-haiku-4-5", displayName: "Claude Haiku 4.5",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 200_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),

        // OpenAI GPT
        Record(id: "databricks-gpt-oss-20b", displayName: "GPT-OSS 20B",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "databricks-gpt-5-6-sol", displayName: "GPT-5.6 Sol",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 1_048_576,
               maxOutputTokens: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "databricks-gpt-5-6-terra", displayName: "GPT-5.6 Terra",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 1_048_576,
               maxOutputTokens: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "databricks-gpt-5-6-luna", displayName: "GPT-5.6 Luna",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 400_000,
               maxOutputTokens: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),

        // Google Gemini
        Record(id: "databricks-gemini-3-5-flash", displayName: "Gemini 3.5 Flash",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "databricks-gemini-3-1-flash-lite", displayName: "Gemini 3.1 Flash Lite",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 1_048_576,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "databricks-gemini-2-5-pro", displayName: "Gemini 2.5 Pro",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "databricks-gemini-2-5-flash", displayName: "Gemini 2.5 Flash",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),

        // Meta Llama
        Record(id: "databricks-meta-llama-3-1-8b-instruct", displayName: "Llama 3.1 8B Instruct",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),

        // Alibaba Qwen
        Record(id: "databricks-qwen3-next-80b-a3b-instruct", displayName: "Qwen3 Next 80B A3B Instruct",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
    ]
}
