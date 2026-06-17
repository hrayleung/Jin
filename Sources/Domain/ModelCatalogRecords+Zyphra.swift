import Foundation

// MARK: - Zyphra Cloud Records
//
// Listed at https://cloud.zyphra.com/docs#description/available-models and
// served by https://api.zyphracloud.com/api/v1/models. Model IDs and
// capabilities mirror what the live /models endpoint advertises (case
// matters — e.g. "zyphra/ZAYA1-8B" with a lowercase 'z'; the GLM variant
// hosted is the FP8 quant). Zyphra's metadata reports
// `functionCalling: false` for every model, but live testing shows the
// gateway happily relays OpenAI-style tool calls and all four models
// return `finish_reason: tool_calls` correctly — so we override that
// field and enable `.toolCalling` here.

extension ModelCatalog {

    static let zyphraRecords: [Record] = [
        Record(id: "zyphra/ZAYA1-8B", displayName: "ZAYA1-8B",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "moonshotai/Kimi-K2.6", displayName: "Kimi K2.6",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 256_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "zai-org/GLM-5.1-FP8", displayName: "GLM-5.1",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 200_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "deepseek-ai/DeepSeek-V3.2", displayName: "DeepSeek V3.2",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 163_800,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
    ]
}
