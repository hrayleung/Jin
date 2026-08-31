import Foundation

extension ModelCatalog {

    // MARK: RunInfra Model APIs

    // Official hosted catalog (runinfra.ai/docs + Model Library, verified 2026-08-31).
    // Wire IDs are the short gateway slugs from GET /v1/models / the Model APIs
    // quickstart. Hugging Face repository IDs are accepted as aliases by the
    // gateway and are catalogued unseeded so Fetch/Add Model still gets exact-ID
    // metadata. Vision is claimed only for exact IDs the Chat Completions contract
    // names (`qwen3-8-27b` accepts inline `image_url` / `input_image`, up to 8).
    // Adapter + PDF rasterizer enforce that cap so 9+ page PDFs do not 400.
    // `qwen3-8-flash-next` stays text-only until that page lists it. Gateway UI
    // output ceiling stays 32,768; GET /v1/models may advertise a larger remaining-
    // context cap. Automatic prefix caching is billed at the published cached-input
    // rate and is not request-controllable.
    static let runinfraRecords: [Record] = {
        let hostedMaxOutputTokens = 32_768
        let flashEfforts: [ReasoningEffort] = [.none, .low, .medium, .max]
        let qwen27BEfforts: [ReasoningEffort] = [.none, .low, .medium, .xhigh]
        let qwen24TEfforts: [ReasoningEffort] = [.low, .medium, .xhigh]
        let hostedChat: ModelCapability = [.streaming, .toolCalling, .reasoning, .promptCaching]
        let hostedVisionChat: ModelCapability = [
            .streaming, .toolCalling, .vision, .reasoning, .promptCaching
        ]

        func hosted(
            id: String,
            displayName: String,
            contextWindow: Int,
            reasoningConfig: ModelReasoningConfig?,
            isSeeded: Bool,
            capabilities: ModelCapability = hostedChat
        ) -> Record {
            Record(
                id: id,
                displayName: displayName,
                capabilities: capabilities,
                contextWindow: contextWindow,
                maxOutputTokens: hostedMaxOutputTokens,
                reasoningConfig: reasoningConfig,
                isFullySupported: true,
                isSeeded: isSeeded
            )
        }

        let flashReasoning = ModelReasoningConfig(
            type: .effort,
            defaultEffort: .max,
            supportedEfforts: flashEfforts
        )
        let qwen27BReasoning = ModelReasoningConfig(
            type: .effort,
            defaultEffort: .medium,
            supportedEfforts: qwen27BEfforts
        )
        let qwen24TReasoning = ModelReasoningConfig(
            type: .effort,
            defaultEffort: .xhigh,
            supportedEfforts: qwen24TEfforts
        )
        let toggleReasoning = ModelReasoningConfig(type: .toggle)

        return [
            hosted(
                id: "deepseek-v4-flash",
                displayName: "DeepSeek V4 Flash",
                contextWindow: 1_048_576,
                reasoningConfig: flashReasoning,
                isSeeded: true
            ),
            hosted(
                id: "glm-5-3-flash",
                displayName: "GLM 5.3 Flash",
                contextWindow: 1_048_576,
                reasoningConfig: toggleReasoning,
                isSeeded: true
            ),
            hosted(
                id: "deepseek-v4-pro",
                displayName: "DeepSeek V4 Pro",
                contextWindow: 1_048_576,
                reasoningConfig: toggleReasoning,
                isSeeded: true
            ),
            hosted(
                id: "qwen3-8-27b",
                displayName: "Qwen3.8 27B",
                contextWindow: 262_144,
                reasoningConfig: qwen27BReasoning,
                isSeeded: true,
                capabilities: hostedVisionChat
            ),
            // Live Model APIs quickstart (2026-08-31) + library page
            // runinfra.ai/inference-api/qwen3-8-flash-next (2026-08-30). Served
            // window is unpublished in crawlable HTML; use the HF native 262,144
            // (Qwen/Qwen3.8-Flash-Next). Fetch overlays live `context_window`.
            // Chat Completions names image parts only for `qwen3-8-27b`, so
            // vision stays off. Effort band is unpublished for this exact ID —
            // toggle only (`none` is still the documented off switch except on
            // `qwen3-8-2-4t-a95b`). Hugging Face mapping is not yet in the
            // published repository table, so no unseeded HF alias.
            hosted(
                id: "qwen3-8-flash-next",
                displayName: "Qwen3.8 Flash Next",
                contextWindow: 262_144,
                reasoningConfig: toggleReasoning,
                isSeeded: true
            ),
            hosted(
                id: "ornith-1-5-35b",
                displayName: "Ornith 1.5 35B",
                contextWindow: 262_144,
                reasoningConfig: toggleReasoning,
                isSeeded: true
            ),
            hosted(
                id: "nemotron-3-5-lightning-30b",
                displayName: "Nemotron 3.5 Lightning 30B",
                contextWindow: 262_144,
                reasoningConfig: toggleReasoning,
                isSeeded: true
            ),
            hosted(
                id: "qwen3-8-2-4t-a95b",
                displayName: "Qwen3.8 2.4T A95B",
                contextWindow: 262_144,
                reasoningConfig: qwen24TReasoning,
                isSeeded: true
            ),

            // Hugging Face repository IDs the gateway also accepts in `model`.
            hosted(
                id: "deepseek-ai/DeepSeek-V4-Flash-0731",
                displayName: "DeepSeek V4 Flash",
                contextWindow: 1_048_576,
                reasoningConfig: flashReasoning,
                isSeeded: false
            ),
            hosted(
                id: "zai-org/GLM-5.3-Flash",
                displayName: "GLM 5.3 Flash",
                contextWindow: 1_048_576,
                reasoningConfig: toggleReasoning,
                isSeeded: false
            ),
            hosted(
                id: "deepseek-ai/DeepSeek-V4-Pro-0813",
                displayName: "DeepSeek V4 Pro",
                contextWindow: 1_048_576,
                reasoningConfig: toggleReasoning,
                isSeeded: false
            ),
            hosted(
                id: "Qwen/Qwen3.8-27B",
                displayName: "Qwen3.8 27B",
                contextWindow: 262_144,
                reasoningConfig: qwen27BReasoning,
                isSeeded: false,
                capabilities: hostedVisionChat
            ),
            hosted(
                id: "ornith-ai/Ornith-1.5-35B-A3B",
                displayName: "Ornith 1.5 35B",
                contextWindow: 262_144,
                reasoningConfig: toggleReasoning,
                isSeeded: false
            ),
            hosted(
                id: "nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-BF16",
                displayName: "Nemotron 3.5 Lightning 30B",
                contextWindow: 262_144,
                reasoningConfig: toggleReasoning,
                isSeeded: false
            ),
            hosted(
                id: "Inferact/Qwen3.8-2.4T-A95B-NVFP4",
                displayName: "Qwen3.8 2.4T A95B",
                contextWindow: 262_144,
                reasoningConfig: qwen24TReasoning,
                isSeeded: false
            ),
        ]
    }()
}
