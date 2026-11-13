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
        Record(id: "zai-org/GLM-5.3", displayName: "GLM-5.3",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 139_264,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .max),
               isFullySupported: true, isSeeded: true),
        // GLM-5.3-Flash-FP4 (Zyphra model feed, releaseDate 2026-11-12): MXFP4
        // quantization of GLM-5.3-Flash — 1,048,576 context / 131,072 output,
        // text+image input, function calling. Same weights as the GLM-5.3-Flash
        // copies on other gateways whose published effort band is low/high/max
        // (always-on thinking); reasoningConfig mirrors that band conservatively.
        Record(id: "zai-org/GLM-5.3-Flash-FP4", displayName: "GLM-5.3-Flash-FP4",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .max, supportedEfforts: [.low, .high, .max]),
               isFullySupported: true, isSeeded: false),
        // `zyphra/ZONOS3-Mini` (feed releaseDate 2026-11-09) is a TTS/voice-
        // cloning model — Zyphra's adapter has no audio-generation surface
        // (blocked-adapter). `zai-org/GLM-5.3-Flash` (2026-08-26) predates this
        // window and stays a follow-up, not a census addition.
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
        // Xiaomi MiMo V2.5 & MiMo V2.5 Pro (live GET https://api.zyphracloud.com/api/v1/models):
        // `XiaomiMiMo/MiMo-V2.5` advertises 1,000,000 context / 131,072 maxOutputTokens,
        // Text+Image+Video+Audio input (`.videoInput` withheld on Zyphra — see
        // `ZyphraAdapter+ModelCatalog`), functionCalling: true, Reasoning + Multimodal.
        // `XiaomiMiMo/MiMo-V2.5-Pro` advertises 1,048,576 context / 131,072 maxOutputTokens,
        // Text input, functionCalling: true, Reasoning + Chat.
        Record(id: "XiaomiMiMo/MiMo-V2.5", displayName: "MiMo V2.5",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning],
               contextWindow: 1_000_000,
               maxOutputTokens: 131_072,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "XiaomiMiMo/MiMo-V2.5-Pro", displayName: "MiMo V2.5 Pro",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
    ]
}
