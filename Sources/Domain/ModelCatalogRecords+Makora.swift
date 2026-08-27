import Foundation

extension ModelCatalog {
    // MARK: Makora
    //
    // OpenAI-compatible Chat Completions on vLLM at https://inference.makora.com/v1.
    // Exact IDs only. Seeded IDs are the current makora.com lineup; the rest are
    // catalogued from Makora's `/v1/models` dump (omp-makora-provider 1.0.4) so
    // Fetch Models still gets first-class metadata if those IDs remain live.
    //
    // Context windows: prefer Makora-first-party numbers (homepage cards, or the
    // `/v1/models` dump). Respan/AA are cited only when they independently report
    // the same model on Makora and the homepage figure is clearly stale.
    // Max output: only the values omp-makora-provider set on exact IDs — Makora
    // model discovery does not report max output tokens.

    private static let makoraChat: ModelCapability = [.streaming, .toolCalling]
    private static let makoraReasoning: ModelCapability = [.streaming, .toolCalling, .reasoning]
    private static let makoraVisionReasoning: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning]

    static let makoraRecords: [Record] = [
        // Seeded — current https://www.makora.com lineup (org + model name), IDs
        // confirmed by Respan `/models/makora/…` pages where they exist.
        Record(
            id: "deepseek-ai/DeepSeek-V4-Flash-0731",
            displayName: "DeepSeek V4 Flash 0731",
            capabilities: makoraReasoning,
            contextWindow: 1_000_000,
            reasoningConfig: ModelReasoningConfig(
                type: .effort,
                defaultEffort: .high,
                supportedEfforts: [.high, .max]
            ),
            isFullySupported: true,
            isSeeded: true
        ),
        // Homepage card: Text Generation, Context 128k (not Image/Text). Respan lists
        // vision + 262K for the same ID; first-party card wins. AA tracks a thinking
        // Gemma 4 26B A4B on Makora, so reasoning is a toggle via enable_thinking.
        Record(
            id: "google/gemma-4-26B-A4B",
            displayName: "Gemma 4 26B A4B",
            capabilities: makoraReasoning,
            contextWindow: 131_072,
            reasoningConfig: ModelReasoningConfig(type: .toggle),
            isFullySupported: true,
            isSeeded: true
        ),
        Record(
            id: "zai-org/GLM-5.2-FP8",
            displayName: "GLM 5.2 FP8",
            capabilities: makoraReasoning,
            contextWindow: 1_000_000,
            maxOutputTokens: 16_384,
            reasoningConfig: ModelReasoningConfig(
                type: .effort,
                defaultEffort: .high,
                supportedEfforts: [.minimal, .low, .medium, .high, .max]
            ),
            isFullySupported: true,
            isSeeded: true
        ),
        Record(
            id: "zai-org/GLM-5.2-NVFP4",
            displayName: "GLM 5.2 NVFP4",
            capabilities: makoraReasoning,
            contextWindow: 1_000_000,
            reasoningConfig: ModelReasoningConfig(
                type: .effort,
                defaultEffort: .high,
                supportedEfforts: [.minimal, .low, .medium, .high, .max]
            ),
            isFullySupported: true,
            isSeeded: true
        ),
        // Homepage: Image/Text to Text. Context card says 256k (same figure as the
        // previous K2.6 card); Respan reports 1.0M and Artificial Analysis lists
        // 1.05M for Makora's Kimi K3, matching Moonshot's native window.
        Record(
            id: "moonshotai/Kimi-K3",
            displayName: "Kimi K3",
            capabilities: makoraVisionReasoning,
            contextWindow: 1_048_576,
            reasoningConfig: ModelReasoningConfig(
                type: .effort,
                defaultEffort: .max,
                supportedEfforts: [.low, .high, .max]
            ),
            isFullySupported: true,
            isSeeded: true
        ),

        // Catalog-only — present on Makora `/v1/models` (omp-makora-provider 1.0.4)
        // and/or Respan's Makora catalog. Not on the current homepage cards.
        Record(
            id: "deepseek-ai/DeepSeek-V4-Flash",
            displayName: "DeepSeek V4 Flash",
            capabilities: makoraReasoning,
            contextWindow: 1_048_576,
            maxOutputTokens: 32_768,
            reasoningConfig: ModelReasoningConfig(
                type: .effort,
                defaultEffort: .high,
                supportedEfforts: [.high, .max]
            ),
            isFullySupported: true,
            isSeeded: false
        ),
        Record(
            id: "deepseek-ai/DeepSeek-V4-Pro",
            displayName: "DeepSeek V4 Pro",
            capabilities: makoraReasoning,
            contextWindow: 1_048_576,
            maxOutputTokens: 32_768,
            reasoningConfig: ModelReasoningConfig(
                type: .effort,
                defaultEffort: .high,
                supportedEfforts: [.high, .max]
            ),
            isFullySupported: true,
            isSeeded: false
        ),
        Record(
            id: "openai/gpt-oss-120b",
            displayName: "GPT-OSS 120B",
            capabilities: makoraReasoning,
            contextWindow: 131_072,
            maxOutputTokens: 16_384,
            reasoningConfig: ModelReasoningConfig(
                type: .effort,
                defaultEffort: .medium,
                supportedEfforts: [.low, .medium, .high]
            ),
            isFullySupported: true,
            isSeeded: false
        ),
        Record(
            id: "nvidia/Kimi-K2.6-NVFP4",
            displayName: "Kimi K2.6 NVFP4",
            capabilities: makoraVisionReasoning,
            contextWindow: 262_144,
            maxOutputTokens: 16_384,
            reasoningConfig: ModelReasoningConfig(
                type: .effort,
                defaultEffort: .medium,
                supportedEfforts: [.low, .medium, .high]
            ),
            isFullySupported: true,
            isSeeded: false
        ),
        Record(
            id: "moonshotai/Kimi-K2.7-Code",
            displayName: "Kimi K2.7 Code",
            capabilities: makoraVisionReasoning,
            contextWindow: 262_144,
            maxOutputTokens: 16_384,
            reasoningConfig: ModelReasoningConfig(
                type: .effort,
                defaultEffort: .medium,
                supportedEfforts: [.low, .medium, .high]
            ),
            isFullySupported: true,
            isSeeded: false
        ),
        Record(
            id: "zai-org/GLM-5.1-FP8",
            displayName: "GLM 5.1 FP8",
            capabilities: makoraReasoning,
            contextWindow: 200_000,
            maxOutputTokens: 16_384,
            reasoningConfig: ModelReasoningConfig(
                type: .effort,
                defaultEffort: .medium,
                supportedEfforts: [.low, .medium, .high]
            ),
            isFullySupported: true,
            isSeeded: false
        ),
        Record(
            id: "MiniMaxAI/MiniMax-M3-MXFP8",
            displayName: "MiniMax M3 MXFP8",
            capabilities: makoraVisionReasoning,
            contextWindow: 1_048_576,
            maxOutputTokens: 16_384,
            reasoningConfig: ModelReasoningConfig(
                type: .effort,
                defaultEffort: .high,
                supportedEfforts: [.high, .max]
            ),
            isFullySupported: true,
            isSeeded: false
        ),
        Record(
            id: "unsloth/Qwen3.6-27B-NVFP4",
            displayName: "Qwen 3.6 27B NVFP4",
            capabilities: makoraReasoning,
            contextWindow: 262_144,
            maxOutputTokens: 16_384,
            reasoningConfig: ModelReasoningConfig(
                type: .effort,
                defaultEffort: .medium,
                supportedEfforts: [.low, .medium, .high]
            ),
            isFullySupported: true,
            isSeeded: false
        ),
        Record(
            id: "unsloth/Qwen3.6-35B-A3B-NVFP4",
            displayName: "Qwen 3.6 35B A3B NVFP4",
            capabilities: makoraReasoning,
            contextWindow: 262_144,
            maxOutputTokens: 16_384,
            reasoningConfig: ModelReasoningConfig(
                type: .effort,
                defaultEffort: .medium,
                supportedEfforts: [.low, .medium, .high]
            ),
            isFullySupported: true,
            isSeeded: false
        ),
        Record(
            id: "meta-llama/Llama-3.3-70B-Instruct",
            displayName: "Llama 3.3 70B Instruct",
            capabilities: makoraChat,
            contextWindow: 131_072,
            maxOutputTokens: 8_192,
            reasoningConfig: nil,
            isFullySupported: true,
            isSeeded: false
        ),
        Record(
            id: "amd/Llama-3.3-70B-Instruct-FP8-KV",
            displayName: "Llama 3.3 70B FP8",
            capabilities: makoraChat,
            contextWindow: 128_000,
            maxOutputTokens: 16_384,
            reasoningConfig: nil,
            isFullySupported: true,
            isSeeded: false
        ),
    ]
}
