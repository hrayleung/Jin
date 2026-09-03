import Foundation

enum ModelRequestShape {
    case openAICompatible
    case openAIResponses
    case anthropic
    case gemini
}

private extension ModelRequestShape {
    var supportsOpenAIStyleReasoningEffort: Bool {
        switch self {
        case .openAICompatible, .openAIResponses:
            return true
        case .anthropic, .gemini:
            return false
        }
    }
}

enum ModelCapabilityRegistry {
    private static let openAINoneDefaultReasoningModelIDs: Set<String> = [
        "gpt-5.2",
        "gpt-5.2-2025-12-11",
        "gpt-5.4",
        "gpt-5.4-2026-03-05",
        "gpt-5.4-image-2",
        "gpt-5.4-mini",
        "gpt-5.4-mini-2026-03-17",
        "gpt-5.4-nano",
        "gpt-5.4-nano-2026-03-17",
    ]

    private static let openAIHighDefaultReasoningModelIDs: Set<String> = [
        "gpt-5.5-pro",
        "gpt-5.5-pro-2026-04-23",
        "gpt-5.4-pro",
        "gpt-5.4-pro-2026-03-05",
    ]

    private static let openAIStyleExtremeEffortModelIDs: Set<String> = [
        "gpt-5.6",
        "gpt-5.6-sol",
        "gpt-5.6-sol-pro",
        "gpt-5.6-terra",
        "gpt-5.6-terra-pro",
        "gpt-5.6-luna",
        "gpt-5.6-luna-pro",
        "gpt-5.5",
        "gpt-5.5-2026-04-23",
        "gpt-5.5-pro",
        "gpt-5.5-pro-2026-04-23",
        "gpt-5.4",
        "gpt-5.4-2026-03-05",
        "gpt-5.4-image-2",
        "gpt-5.4-pro",
        "gpt-5.4-pro-2026-03-05",
        "gpt-5.4-mini",
        "gpt-5.4-mini-2026-03-17",
        "gpt-5.4-nano",
        "gpt-5.4-nano-2026-03-17",
        "gpt-5.2",
        "gpt-5.2-2025-12-11",
        "gpt-5.2-codex",
        "gpt-5.2-pro",
        "gpt-5.3-codex",
        "gpt-5.3-codex-spark",
    ]

    /// Models accepting the `max` reasoning effort value, introduced with GPT-5.6
    /// (Sol/Terra/Luna support none|low|medium|high|xhigh|max; `minimal` was dropped).
    /// Older 5.x models reject "max", so it stays clamped to xhigh for them.
    private static let openAIStyleMaxEffortModelIDs: Set<String> = [
        "gpt-5.6",
        "gpt-5.6-sol",
        "gpt-5.6-sol-pro",
        "gpt-5.6-terra",
        "gpt-5.6-terra-pro",
        "gpt-5.6-luna",
        "gpt-5.6-luna-pro",
    ]

    /// Models that accept Responses API `reasoning.mode = "pro"` (GPT-5.6 family).
    /// Pro is a request-time mode on the same model ID, not a separate OpenAI slug.
    private static let openAIStyleProModeModelIDs: Set<String> = [
        "gpt-5.6",
        "gpt-5.6-sol",
        "gpt-5.6-terra",
        "gpt-5.6-luna",
    ]

    /// Models that accept Responses API `reasoning.context` (multi-turn reasoning reuse).
    /// Keep conservative to GPT-5.6 family until broader model docs list the field.
    private static let openAIStyleReasoningContextModelIDs: Set<String> = [
        "gpt-5.6",
        "gpt-5.6-sol",
        "gpt-5.6-terra",
        "gpt-5.6-luna",
    ]

    /// Models that accept Responses API `text.verbosity`.
    private static let openAIStyleVerbosityModelIDs: Set<String> = [
        "gpt-5.6",
        "gpt-5.6-sol",
        "gpt-5.6-terra",
        "gpt-5.6-luna",
        "gpt-5.5",
        "gpt-5.5-2026-04-23",
        "gpt-5.5-pro",
        "gpt-5.5-pro-2026-04-23",
        "gpt-5.4",
        "gpt-5.4-2026-03-05",
        "gpt-5.4-pro",
        "gpt-5.4-pro-2026-03-05",
        "gpt-5.4-mini",
        "gpt-5.4-mini-2026-03-17",
        "gpt-5.4-nano",
        "gpt-5.4-nano-2026-03-17",
        "gpt-5.2",
        "gpt-5.2-2025-12-11",
    ]

    /// Gemini 3 Flash family supports MINIMAL/LOW/MEDIUM/HIGH.
    private static let gemini3FlashEffortModelIDs: Set<String> = [
        "gemini-3-flash-preview",
        "gemini-3.5-flash",
        "gemini-3.5-flash-lite",
        "gemini-3.6-flash",
    ]

    /// Gemini 3.7 & 3.8 Flash support LOW/MEDIUM/HIGH only — the model page states that
    /// `thinking_level="MINIMAL"` returns an API validation error.
    private static let gemini37FlashEffortModelIDs: Set<String> = [
        "gemini-3.7-flash",
        "gemini-3.8-flash",
        "gemini-3.8-flash-preview",
    ]

    /// Gemini 3.1 Flash Image supports MINIMAL/HIGH.
    private static let gemini31FlashImageEffortModelIDs: Set<String> = [
        "gemini-3.1-flash-image",
        "gemini-3.1-flash-image-preview",
        "gemini-3.1-flash-lite-image",
    ]

    /// Gemini 3.1 Pro supports LOW/MEDIUM/HIGH.
    private static let gemini31ProEffortModelIDs: Set<String> = [
        "gemini-3.1-pro-preview",
    ]

    /// Gemini 3 Pro family supports LOW/HIGH.
    private static let gemini3ProLowHighEffortModelIDs: Set<String> = [
        "gemini-3",
        "gemini-3-pro",
        "gemini-3-pro-preview",
        "gemini-3-pro-image",
        "gemini-3-pro-image-preview",
    ]

    /// Models documented by Google as supporting grounding with Google Search in Gemini API,
    /// plus narrow runtime trials we intentionally enable in Jin.
    private static let geminiGoogleSearchSupportedModelIDs: Set<String> = [
        "gemini-3.1-pro-preview",
        "gemini-3-pro-preview",
        "gemini-3-flash-preview",
        "gemini-3-pro-image",
        "gemini-3-pro-image-preview",
        "gemini-3.1-flash-image",
        "gemini-3.1-flash-image-preview",
        "gemini-3.1-flash-lite-preview",
        "gemini-3.1-flash-lite",
        "gemini-3.5-flash",
        "gemini-3.5-flash-lite",
        "gemini-3.6-flash",
        "gemini-3.7-flash",
        "gemini-3.8-flash",
        "gemini-3.8-flash-preview",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.0-flash",
        "gemini-2.0-flash-001",
        "gemma-4-26b-a4b-it",
        "gemma-4-31b-it",
    ]

    /// Models supporting grounding with Google Search in Vertex AI.
    /// Includes Gemini 3.1 Flash Image based on runtime validation.
    private static let vertexGoogleSearchSupportedModelIDs: Set<String> = [
        "gemini-3.1-pro-preview",
        "gemini-3-pro-preview",
        "gemini-3-flash-preview",
        "gemini-3-pro-image",
        "gemini-3-pro-image-preview",
        "gemini-3.1-flash-image",
        "gemini-3.1-flash-image-preview",
        "gemini-3.1-flash-lite",
        "gemini-3.1-flash-lite-preview",
        "gemini-3.5-flash",
        "gemini-3.5-flash-lite",
        "gemini-3.6-flash",
        "gemini-3.7-flash",
        "gemini-3.8-flash",
        "gemini-3.8-flash-preview",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.5-flash-preview",
        "gemini-2.5-flash-lite-preview",
        "gemini-2.0-flash",
    ]

    /// OpenRouter `plugins: [{id: "web"}]` support stays conservative and does not
    /// inherit Gemini-only runtime trials automatically.
    private static let openRouterGoogleSearchSupportedModelIDs: Set<String> = [
        "gemini-3.1-pro-preview",
        "gemini-3-pro-preview",
        "gemini-3-flash-preview",
        "gemini-3-pro-image",
        "gemini-3-pro-image-preview",
        "gemini-3.1-flash-image",
        "gemini-3.1-flash-image-preview",
        "gemini-3.1-flash-lite-preview",
        "gemini-3.1-flash-lite",
        "gemini-3.5-flash",
        "gemini-3.5-flash-lite",
        "gemini-3.6-flash",
        "gemini-3.7-flash",
        "gemini-3.8-flash",
        "gemini-3.8-flash-preview",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.5-flash-preview",
        "gemini-2.5-flash-lite-preview",
        "gemini-2.0-flash",
        "gemini-2.0-flash-001",
    ]

    /// Fallback used by proxy providers other than explicit provider-specific allowlists.
    private static let proxiedGoogleSearchSupportedModelIDs: Set<String> =
        geminiGoogleSearchSupportedModelIDs.union(vertexGoogleSearchSupportedModelIDs)

    /// Models documented by Google as supporting grounding with Google Maps in Gemini API.
    private static let geminiGoogleMapsSupportedModelIDs: Set<String> = [
        "gemini-3.8-flash",
        "gemini-3.8-flash-preview",
        "gemini-3.7-flash",
        "gemini-3.6-flash",
        "gemini-3.5-flash",
        "gemini-3.5-flash-lite",
        "gemini-3.1-pro-preview",
        "gemini-3.1-flash-lite",
        "gemini-3.1-flash-lite-preview",
        "gemini-3-flash-preview",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.0-flash",
        "gemini-2.0-flash-001",
    ]

    // Note: image-generation models intentionally omitted from Maps (docs: not supported).

    /// Models supporting grounding with Google Maps in Vertex AI.
    /// Align with Vertex generative-ai Maps page + Enterprise model cards (2026-07).
    /// Keep exact IDs only; legacy aliases retained for persisted conversations.
    private static let vertexGoogleMapsSupportedModelIDs: Set<String> = [
        "gemini-3-pro-preview",
        "gemini-3.1-pro-preview",
        "gemini-3-flash-preview",
        "gemini-3.8-flash",
        "gemini-3.8-flash-preview",
        "gemini-3.7-flash",
        "gemini-3.6-flash",
        "gemini-3.5-flash",
        "gemini-3.5-flash-lite",
        "gemini-3.1-flash-lite",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.5-flash-preview",
        "gemini-2.5-flash-preview-09-2025",
        "gemini-2.5-flash-lite-preview",
        "gemini-2.5-flash-lite-preview-09-2025",
        "gemini-live-2.5-flash-native-audio",
        "gemini-live-2.5-flash-preview-native-audio-09-2025",
        "gemini-2.0-flash",
        "gemini-2.0-flash-001",
        "gemini-2.0-flash-live-preview-04-09",
    ]

    /// Models documented by Google as supporting code execution in Gemini API.
    private static let geminiCodeExecutionSupportedModelIDs: Set<String> = [
        "gemini-3-pro",
        "gemini-3-pro-preview",
        "gemini-3.1-pro",
        "gemini-3.1-pro-preview",
        "gemini-3-flash",
        "gemini-3-flash-preview",
        "gemini-3.1-flash-lite",
        "gemini-3.1-flash-lite-preview",
        "gemini-3.5-flash",
        "gemini-3.5-flash-lite",
        "gemini-3.6-flash",
        "gemini-3.7-flash",
        "gemini-3.8-flash",
        "gemini-3.8-flash-preview",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.0-flash",
        "gemini-2.0-flash-001",
    ]

    /// Models documented by Google as supporting code execution in Vertex AI.
    private static let vertexCodeExecutionSupportedModelIDs: Set<String> = [
        "gemini-3-pro",
        "gemini-3-pro-preview",
        "gemini-3.1-pro",
        "gemini-3.1-pro-preview",
        "gemini-3-flash",
        "gemini-3-flash-preview",
        "gemini-3.1-flash-lite",
        "gemini-3.1-flash-lite-preview",
        "gemini-3.5-flash",
        "gemini-3.5-flash-lite",
        "gemini-3.6-flash",
        "gemini-3.7-flash",
        "gemini-3.8-flash",
        "gemini-3.8-flash-preview",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.5-flash-preview",
        "gemini-2.5-flash-lite-preview",
        "gemini-2.0-flash",
        "gemini-2.0-flash-001",
    ]

    // Note: OpenAI code interpreter set continues below.

    /// Exact model IDs that OpenAI currently documents as supporting the built-in Code interpreter tool.
    /// Keep this conservative: do not broaden to unlisted realtime/audio families.
    private static let openAICodeInterpreterSupportedModelIDs: Set<String> = [
        "gpt-4.1",
        "gpt-4.1-2025-04-14",
        "gpt-5",
        "gpt-5-2025-08-07",
        "gpt-5.6",
        "gpt-5.6-sol",
        "gpt-5.6-terra",
        "gpt-5.6-luna",
        "gpt-5.6-cyber",
        "gpt-daybreak-red-latest",
        "gpt-daybreak-blue-latest",
        "gpt-5.5",
        "gpt-5.5-2026-04-23",
        "gpt-5.5-pro",
        "gpt-5.5-pro-2026-04-23",
        "gpt-5.2",
        "gpt-5.2-2025-12-11",
        "gpt-5.4",
        "gpt-5.4-2026-03-05",
        "gpt-5.4-mini",
        "gpt-5.4-mini-2026-03-17",
        "gpt-5.4-nano",
        "gpt-5.4-nano-2026-03-17",
        "gpt-5-mini",
        "gpt-5-mini-2025-08-07",
        "gpt-5-nano",
        "gpt-5-nano-2025-08-07",
        "o3",
        "o4-mini",
    ]

    /// Exact model IDs that Anthropic currently documents as supporting the code execution tool.
    /// Includes Fable 5 / Mythos 5 (restored 2026-07 docs list code execution under Supported features).
    private static let anthropicCodeExecutionSupportedModelIDs: Set<String> = [
        "claude-fable-5-1",
        "claude-mythos-5-1",
        "claude-fable-5",
        "claude-mythos-5",
        "claude-opus-5",
        "claude-opus-4-8",
        "claude-opus-4-7",
        "claude-opus-4-6",
        "claude-sonnet-5",
        "claude-sonnet-4-6",
        "claude-sonnet-4-5-20250929",
        "claude-opus-4-5-20251101",
        "claude-haiku-4-5-20251001",
        "claude-opus-4-1-20250805",
        "claude-opus-4-20250514",
        "claude-sonnet-4-20250514",
        "claude-3-7-sonnet-20250219",
        "claude-3-5-haiku-latest",
    ]

    private static let reasoningEffortRank: [ReasoningEffort: Int] = [
        .none: 0,
        .minimal: 1,
        .low: 2,
        .medium: 3,
        .high: 4,
        .xhigh: 5,
        .max: 6,
    ]

    private static let defaultReasoningEfforts: [ReasoningEffort] = [.low, .medium, .high]
    private static let defaultGeminiReasoningEfforts: [ReasoningEffort] = [.minimal, .low, .medium, .high]
    private static let deepSeekV4ReasoningEffortModelIDs: Set<String> = [
        "deepseek-v4-flash",
        "deepseek-v4-flash-0731",
        "deepseek-v4-flash-vision-exp",
        "deepseek-v4-pro",
        "deepseek-v4-pro-0813",
    ]
    /// OpenCode Go GLM models whose `reasoning_effort` is restricted to `high`/`max`
    /// (Z.AI documents only these two for GLM-5.2; `max` is the native default).
    private static let opencodeGoGLMHighMaxReasoningEffortModelIDs: Set<String> = [
        "glm-5.2",
    ]
    /// GLM-5.3 / GLM-5.3-Flash official band is `low`/`high`/`max` (default `max`).
    /// Thinking cannot be disabled — `thinking.type: disabled` is rejected
    /// (z.ai/blog/glm-5.3, docs.z.ai/guides/vlm/glm-5.3-flash). Exact IDs only.
    private static let glm53LowHighMaxReasoningEffortModelIDs: Set<String> = [
        "glm-5.3",
        "glm-5.3[1m]",
        "glm-5.3-flash",
        "z-ai/glm-5.3",
        "z-ai/glm-5.3-flash",
        "zai/glm-5.3",
        "zai/glm-5.3-flash",
        "zai-org/glm-5.3",
        "zai-org/glm-5.3-flash",
    ]
    /// Ox Alpha on OpenRouter (`stealth/ox-alpha`): live `/models` supported_efforts
    /// are max/high/low (default max, mandatory=true). Exact ID only — the Go slug
    /// `ox-alpha-free` is a different product on a different gateway.
    private static let openRouterOxAlphaReasoningEffortModelIDs: Set<String> = [
        "stealth/ox-alpha",
    ]
    /// Ox Alpha Free on OpenCode Go (`ox-alpha-free`): models.dev `opencode-go`
    /// reasoning_options are low/high/max (default max). Exact ID only.
    private static let opencodeGoOxAlphaReasoningEffortModelIDs: Set<String> = [
        "ox-alpha-free",
    ]
    /// Zhipu / Z.AI Coding Plan GLM-5.2 IDs: `reasoning_effort` is high/max only,
    /// matching the OpenCode Go 5.2 band and docs.z.ai/devpack/latest-model.
    private static let zhipuGLM52HighMaxReasoningEffortModelIDs: Set<String> = [
        "glm-5.2",
        "glm-5.2[1m]",
    ]
    /// OpenCode Go's Tencent Hy3 line accepts only `low`/`high` — `medium` is not a valid
    /// value (models.dev `opencode-go` reasoning_options for `hy3`, and OpenRouter's live
    /// supported_efforts for `tencent/hy3`, agree). `none` is expressed by disabling
    /// reasoning, which omits the field entirely. Mirrors `openRouterLowHighEffortModelIDs`
    /// below, which encodes the same band for the same family on the other gateway.
    private static let opencodeGoHy3ReasoningEffortModelIDs: Set<String> = [
        "hy3",
        "hy3-preview",
    ]
    /// OpenCode Go Hy4 preview: only `high` is a verified wire value. Disable by
    /// omitting `reasoning_effort` (HF `no_think`). Do not inherit Hy3's `low`.
    private static let opencodeGoHy4ReasoningEffortModelIDs: Set<String> = [
        "hy4-preview",
    ]
    private static let openRouterDeepSeekV4ReasoningEffortModelIDs: Set<String> = [
        "deepseek/deepseek-v4-flash",
        "deepseek/deepseek-v4-pro",
    ]
    /// DeepSeek V4 GA snapshots on OpenRouter: live `/models` supported_efforts
    /// are max/high/low (default high). Distinct from the April preview slug.
    private static let openRouterDeepSeekV4GAReasoningEffortModelIDs: Set<String> = [
        "deepseek/deepseek-v4-pro-0813",
        "deepseek/deepseek-v4-flash-0731",
        "deepseek/deepseek-v4-flash-vision-exp",
    ]
    /// Open-weight Qwen3.8-2.4T-A95B + 27B on OpenRouter: xhigh/medium/low
    /// (default xhigh). Cloud Max is a different product (see below).
    private static let openRouterQwen38OpenWeightReasoningEffortModelIDs: Set<String> = [
        "qwen/qwen3.8-2.4t-a95b",
        "qwen/qwen3.8-27b",
    ]
    /// Alibaba Cloud Qwen3.8 Max on OpenRouter: xhigh/high/medium/low/minimal.
    private static let openRouterQwen38CloudMaxReasoningEffortModelIDs: Set<String> = [
        "qwen/qwen3.8-max",
    ]
    /// Sakana Fugu Ultra only accepts the high/xhigh/max band (OpenRouter
    /// supported_efforts, verified 2026-07-11).
    private static let openRouterHighBandEffortModelIDs: Set<String> = [
        "sakana/fugu-ultra",
    ]
    /// Tencent Hy3 accepts only high/low ("none" is expressed by disabling
    /// reasoning) — OpenRouter supported_efforts, verified 2026-07-11.
    private static let openRouterLowHighEffortModelIDs: Set<String> = [
        "tencent/hy3",
        "tencent/hy3:free",
        "tencent/hy4-preview",
    ]
    /// Gemini 3.1 Flash Lite Image on OpenRouter accepts only minimal/high
    /// (matches the native gemini31FlashImageEffortModelIDs band).
    private static let openRouterMinimalHighEffortModelIDs: Set<String> = [
        "google/gemini-3.1-flash-lite-image",
    ]
    /// Thinking Machines Inkling accepts the full none/minimal/low/medium/high/max
    /// band with no xhigh (OpenRouter supported_efforts, verified 2026-07-18).
    private static let openRouterMinimalMaxEffortModelIDs: Set<String> = [
        "thinkingmachines/inkling",
    ]
    /// Claude models whose OpenRouter `supported_efforts` is the full low…max ladder
    /// (verified 2026-07-25). Without an explicit band these fall through to the
    /// low/medium/high default, which silently clamps `xhigh`/`max` down to `high`
    /// even though the gateway accepts both.
    ///
    /// NOTE: the same clamp still affects the other Claude models on OpenRouter
    /// (opus-4.8/4.7 and their `-fast` twins, fable-5, sonnet-5 — all live-verified as
    /// low…max) and on the Vercel/Cloudflare gateways. That is a pre-existing gap, not
    /// an Opus 5 regression, and widening it for those models is deliberately left to a
    /// separate change so this one stays scoped to the model it ships.
    private static let openRouterFullLadderEffortModelIDs: Set<String> = [
        "anthropic/claude-opus-5",
        "anthropic/claude-opus-5-fast",
    ]
    private static let togetherDeepSeekV4ReasoningEffortModelIDs: Set<String> = [
        "deepseek-ai/deepseek-v4-pro",
    ]
    /// Together GA DeepSeek V4 snapshots: low/high/max (Together model pages,
    /// 2026-08-16 / 2026-07-30). Preview `DeepSeek-V4-Pro` stays on the older
    /// high-only band above.
    private static let togetherDeepSeekV4GAReasoningEffortModelIDs: Set<String> = [
        "deepseek-ai/deepseek-v4-pro-0813",
        "deepseek-ai/deepseek-v4-flash-0731",
    ]
    /// Together Qwen3.8-2.4T-A95B: always-on low/high/xhigh (Together model page).
    private static let togetherQwen38TextReasoningEffortModelIDs: Set<String> = [
        "qwen/qwen3.8-2.4t-a95b",
    ]
    /// Kimi K3 on Together: low/high/max (models.dev togetherai, 2026-07-29).
    private static let togetherKimiK3ReasoningEffortModelIDs: Set<String> = [
        "moonshotai/kimi-k3",
    ]
    private static let deepInfraDeepSeekV4ReasoningEffortModelIDs: Set<String> = [
        "deepseek-ai/deepseek-v4-flash",
        "deepseek-ai/deepseek-v4-pro",
    ]
    /// DeepInfra DeepSeek-V4-Pro-0813: low/high/max (HF + DeepSeek thinking docs).
    private static let deepInfraDeepSeekV4Pro0813ReasoningEffortModelIDs: Set<String> = [
        "deepseek-ai/deepseek-v4-pro-0813",
    ]
    /// DeepInfra Qwen3.8-2.4T-A95B: HF low/medium/xhigh, thinking always on.
    private static let deepInfraQwen38TextReasoningEffortModelIDs: Set<String> = [
        "qwen/qwen3.8-2.4t-a95b",
    ]
    /// Kimi K3 on DeepInfra: low/high/max (models.dev deepinfra, 2026-07-29).
    private static let deepInfraKimiK3ReasoningEffortModelIDs: Set<String> = [
        "moonshotai/kimi-k3",
    ]
    /// Fireworks Kimi K3 IDs (canonical + accounts paths + fast router).
    private static let fireworksKimiK3ReasoningEffortModelIDs: Set<String> = [
        "kimi-k3",
        "fireworks/kimi-k3",
        "accounts/fireworks/models/kimi-k3",
        "accounts/fireworks/routers/kimi-k3-fast",
        "fireworks/kimi-k3-fast",
    ]
    /// Fireworks DeepSeek-V4-Pro-0813: low/high/max (same GA band as Together /
    /// DeepInfra / official docs). Preview `deepseek-v4-pro` stays high/max.
    private static let fireworksDeepSeekV4Pro0813ReasoningEffortModelIDs: Set<String> = [
        "deepseek-v4-pro-0813",
        "fireworks/deepseek-v4-pro-0813",
        "accounts/fireworks/models/deepseek-v4-pro-0813",
        "deepseek-ai/deepseek-v4-pro-0813",
    ]
    /// Fireworks Qwen3.8-2.4T-A95B aliases. Fireworks page does not list effort
    /// values; inherit the HF/Modal same-weights band (low/medium/xhigh).
    private static let fireworksQwen38TextReasoningEffortModelIDs: Set<String> = [
        "qwen3p8-2p4t-a95b",
        "fireworks/qwen3p8-2p4t-a95b",
        "accounts/fireworks/models/qwen3p8-2p4t-a95b",
        "qwen3p8-max",
        "fireworks/qwen3p8-max",
    ]
    /// Vercel Kimi K3 Fast: low/high/max (models.dev vercel, 2026-07-29).
    private static let vercelKimiK3FastReasoningEffortModelIDs: Set<String> = [
        "moonshotai/kimi-k3-fast",
    ]
    /// Baseten Kimi K3: none/low/high/max (docs.baseten.co reasoning, 2026-07-29).
    private static let basetenKimiK3ReasoningEffortModelIDs: Set<String> = [
        "moonshotai/kimi-k3",
    ]
    /// Baseten Inkling: none/minimal/low/medium/high/xhigh/max.
    private static let basetenInklingReasoningEffortModelIDs: Set<String> = [
        "thinkingmachines/inkling",
        "thinkingmachines/inkling-small",
    ]
    /// Baseten DeepSeek V4 Pro + GPT-OSS: wide effort band including none.
    private static let basetenWideEffortModelIDs: Set<String> = [
        "deepseek-ai/deepseek-v4-pro",
        "deepseek-ai/deepseek-v4-flash-0731",
        "openai/gpt-oss-120b",
    ]
    /// Baseten DeepSeek V4 Pro 0813: narrow effort band (none/low/high/max).
    private static let basetenDeepSeekV4Pro0813ReasoningEffortModelIDs: Set<String> = [
        "deepseek-ai/deepseek-v4-pro-0813",
    ]
    /// Baseten GLM-5.2 family: none/high/max only. GLM-5.3-Flash is always-on
    /// low/high/max via `glm53LowHighMaxReasoningEffortModelIDs`.
    private static let basetenGLMEffortModelIDs: Set<String> = [
        "zai-org/glm-5.2",
        "zai-org/glm-5.2-fast",
    ]
    /// Modal Shared API Kimi K3. Modal doesn't publish a per-model effort matrix, so
    /// this inherits the band documented for the same weights on Baseten.
    private static let modalKimiK3ReasoningEffortModelIDs: Set<String> = [
        "moonshotai/kimi-k3",
    ]
    /// Modal Shared API Inkling: full none/minimal/low/medium/high/xhigh/max band,
    /// same weights as the Inkling served elsewhere (note Modal's NVFP4 slug).
    private static let modalInklingReasoningEffortModelIDs: Set<String> = [
        "thinkingmachines/inkling-nvfp4",
    ]
    /// Modal Shared API Qwen3.8-2.4T-A95B. HF card + Modal library (2026-08-12):
    /// `reasoning_effort` is only low / medium / xhigh. Thinking cannot be
    /// disabled — do not offer `none`, `high`, or `max`.
    private static let modalQwen38TextReasoningEffortModelIDs: Set<String> = [
        "qwen/qwen3.8-2.4t-a95b",
    ]
    /// RunInfra DeepSeek V4 Flash: `none` disables thinking; omitting effort applies
    /// `max`; `high`/`xhigh`/`max` all go upstream as `max`. Medium is distinct.
    private static let runinfraDeepSeekV4FlashReasoningEffortModelIDs: Set<String> = [
        "deepseek-v4-flash",
        "deepseek-ai/deepseek-v4-flash-0731",
    ]
    /// RunInfra Qwen3.8 27B: none/low/medium/xhigh (models.dev + chat-completions docs).
    private static let runinfraQwen3827BReasoningEffortModelIDs: Set<String> = [
        "qwen3-8-27b",
        "qwen/qwen3.8-27b",
    ]
    /// RunInfra Qwen3.8 2.4T A95B: thinking cannot be disabled; low/medium/xhigh only.
    private static let runinfraQwen3824TReasoningEffortModelIDs: Set<String> = [
        "qwen3-8-2-4t-a95b",
        "inferact/qwen3.8-2.4t-a95b-nvfp4",
    ]
    /// Baseten Mercury 2 / 2.5: none/low/medium/high (Inception + OpenRouter, 2026-07/2026-08).
    private static let basetenMercury2ReasoningEffortModelIDs: Set<String> = [
        "inception/mercury-2",
        "inception/mercury-2.5-preview",
    ]

    // MARK: Router (Ramp) effort bands
    //
    // Transcribed from `GET https://api.router.com/v1/models` on 2026-08-22, where
    // each model carries an exact `capabilities.reasoning.efforts` array. Router
    // ENFORCES these — an out-of-band value returns `400 Invalid reasoning effort.`
    // rather than being clamped, so a wrong band is a broken send, not a cosmetic
    // menu bug. Router also re-labels upstream models, so these IDs deliberately do
    // not match any other provider's (`claude-opus-5`, not `claude-opus-5-20260115`;
    // `accounts/fireworks/models/kimi-k3`, not `moonshotai/kimi-k3`).

    /// Router band `none, minimal, low, medium, high, xhigh, max`.
    private static let routerFullLadderEffortModelIDs: Set<String> = [
        "accounts/fireworks/models/deepseek-v4-flash",
        "accounts/fireworks/models/deepseek-v4-flash-0731",
        "accounts/fireworks/models/deepseek-v4-pro",
        "accounts/fireworks/models/deepseek-v4-pro-0813",
        "accounts/fireworks/models/glm-5p2",
        "accounts/fireworks/routers/glm-5p2-fast",
        "accounts/fireworks/models/glm-5p3",
        "accounts/fireworks/routers/glm-5p3-fast",
        "claude-opus-4-6",
        "claude-opus-4-7",
        "claude-opus-4-8",
        "claude-opus-5",
        "claude-sonnet-4-6",
        "claude-sonnet-5",
        "grok-4.20-multi-agent-0309",
    ]
    /// Router band `none, minimal, low, medium, high, xhigh`.
    private static let routerNoneToExtremeEffortModelIDs: Set<String> = [
        "accounts/fireworks/models/gpt-oss-20b",
        "accounts/fireworks/models/kimi-k2p6",
        "accounts/fireworks/models/kimi-k2p7-code",
        "accounts/fireworks/models/minimax-m2p7",
        "accounts/fireworks/models/minimax-m3",
        "accounts/fireworks/models/nemotron-3-ultra-nvfp4",
        "accounts/fireworks/models/qwen3p7-plus",
        "accounts/fireworks/models/qwen3p8-max",
        "accounts/fireworks/routers/kimi-k2p6-turbo",
        "accounts/fireworks/routers/kimi-k2p7-code-fast",
        "claude-haiku-4-5",
        "grok-4.3",
    ]
    /// Router band `minimal, low, medium, high, xhigh, max`.
    private static let routerMinimalToMaxEffortModelIDs: Set<String> = [
        "accounts/fireworks/models/kimi-k3",
        "accounts/fireworks/routers/kimi-k3-fast",
        "claude-fable-5",
    ]
    /// Router band `minimal, low, medium, high, xhigh`.
    private static let routerMinimalToExtremeEffortModelIDs: Set<String> = [
        "accounts/fireworks/models/gpt-oss-120b",
        "grok-4.5",
        "grok-4.6",
    ]
    /// Router band `none, low, medium, high, xhigh, max` (GPT-5.6 family).
    private static let routerNoneLowToMaxEffortModelIDs: Set<String> = [
        "gpt-5.6-luna",
        "gpt-5.6-sol",
        "gpt-5.6-terra",
    ]
    /// Router band `none, low, medium, high, xhigh`. Note Router drops `minimal`
    /// on these, unlike OpenAI's own GPT-5.4/5.5 ladder.
    private static let routerNoneLowToExtremeEffortModelIDs: Set<String> = [
        "gpt-5.2",
        "gpt-5.3-codex",
        "gpt-5.4",
        "gpt-5.4-mini",
        "gpt-5.4-nano",
        "gpt-5.5",
    ]
    /// Router band `medium, high, xhigh` (Pro models — no low, no off).
    private static let routerMediumToExtremeEffortModelIDs: Set<String> = [
        "gpt-5.2-pro",
        "gpt-5.4-pro",
        "gpt-5.5-pro",
    ]
    /// Router band `none, low, medium, high`.
    private static let routerNoneLowToHighEffortModelIDs: Set<String> = [
        "gpt-5.1",
    ]
    /// Router band `minimal, low, medium, high`.
    private static let routerMinimalToHighEffortModelIDs: Set<String> = [
        "gpt-5",
        "gpt-5-mini",
        "gpt-5-nano",
    ]
    /// Router band `high` only.
    private static let routerHighOnlyEffortModelIDs: Set<String> = [
        "gpt-5-pro",
    ]
    /// Router band `low, medium, high`.
    private static let routerLowToHighEffortModelIDs: Set<String> = [
        "o3",
        "o3-pro",
    ]
    /// Every Router model whose band includes `max`. Kept as one flat set so
    /// `supportsOpenAIStyleMaxEffort` can answer without recursing into
    /// `supportedReasoningEfforts`.
    private static let routerMaxEffortModelIDs: Set<String> =
        routerFullLadderEffortModelIDs
            .union(routerMinimalToMaxEffortModelIDs)
            .union(routerNoneLowToMaxEffortModelIDs)
    /// Router models accepting Responses `text.verbosity` — `/v1/models` reports
    /// `verbosity.supported: true` for exactly the GPT-5 family (verified accepted
    /// on gpt-5.4, 2026-08-22).
    private static let routerVerbosityModelIDs: Set<String> = [
        "gpt-5", "gpt-5-mini", "gpt-5-nano", "gpt-5-pro",
        "gpt-5.1", "gpt-5.2", "gpt-5.2-pro", "gpt-5.3-codex",
        "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano", "gpt-5.4-pro",
        "gpt-5.5", "gpt-5.5-pro",
        "gpt-5.6-luna", "gpt-5.6-sol", "gpt-5.6-terra",
    ]
    /// Router models that reach OpenAI's hosted web search. Router's capability
    /// table lists basic web search as OpenAI-only; the Fireworks-served
    /// `gpt-oss-*` share the naming but not the backend, so they are excluded.
    private static let routerWebSearchModelIDs: Set<String> = [
        "gpt-4.1", "gpt-4.1-mini", "gpt-4o", "gpt-4o-mini",
        "gpt-5", "gpt-5-mini", "gpt-5-nano", "gpt-5-pro",
        "gpt-5.1", "gpt-5.2", "gpt-5.2-pro", "gpt-5.3-codex",
        "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano", "gpt-5.4-pro",
        "gpt-5.5", "gpt-5.5-pro",
        "gpt-5.6-luna", "gpt-5.6-sol", "gpt-5.6-terra",
        "o3", "o3-pro",
    ]
    private static let xAIMultiAgentReasoningEffortModelIDs: Set<String> = [
        "grok-4.20-multi-agent",
        "grok-4.20-multi-agent-0309",
        "x-ai/grok-4.20-multi-agent",
        "xai/grok-4.20-multi-agent",
    ]
    /// grok-4.6 reasoning is always-on with low/medium/high/xhigh (docs.x.ai
    /// 2026-08-12). Distinct from grok-4.5, which rejects xhigh (treated as high).
    private static let xAIAlwaysOnStandardEffortWithXHighModelIDs: Set<String> = [
        "grok-4.6",
        "x-ai/grok-4.6",
        "xai/grok-4.6",
    ]
    private static let xAIAlwaysOnStandardEffortModelIDs: Set<String> = [
        "grok-4.5",
        "x-ai/grok-4.5",
        "xai/grok-4.5",
    ]
    private static let xAIStandardEffortWithNoneModelIDs: Set<String> = [
        "grok-4.3",
        "x-ai/grok-4.3",
        "xai/grok-4.3",
    ]

    /// Whether effort labels should describe multi-agent agent count rather than thinking depth.
    static func usesXAIMultiAgentEffortLabels(for providerType: ProviderType?, modelID: String) -> Bool {
        switch providerType {
        case .xai, .openrouter, .vercelAIGateway:
            return xAIMultiAgentReasoningEffortModelIDs.contains(modelID.lowercased())
        default:
            return false
        }
    }
    private static let mistralHighOnlyReasoningEffortModelIDs: Set<String> = [
        "mistral-medium-3.5",
        "mistral-small-4-0-26-03",
        "magistral-medium-1-2-25-09",
    ]
    private static let googleModelPrefixes = [
        "google/",
        "google-ai-studio/",
        "google-vertex-ai/google/",
        "models/",
    ]
    private static let searchKeywords = ["search", "sonar", ":online"]
    private static let reasoningKeywords = ["deepseek-r1", "reasoning", "thinking"]
    private static let mediaGenerationKeywords = [
        "-image",
        "imagen",
        "veo",
        "-video",
        "video-generation",
        "imagine-image",
        "imagine-video",
    ]

    static func requestShape(for providerType: ProviderType?, modelID _: String) -> ModelRequestShape {
        switch providerType {
        case .openai, .openaiWebSocket, .router:
            // Router is Responses-only — `POST /v1/chat/completions` 404s there.
            return .openAIResponses
        case .anthropic, .claudeManagedAgents, .mimoTokenPlanAnthropic, .kimiForCoding:
            return .anthropic
        case .gemini, .vertexai:
            return .gemini
        case .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter,
             .groq, .cohere, .mistral, .deepinfra, .together, .baseten, .xai, .deepseek,
             .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .mimoTokenPlanOpenAI, .fireworks, .cerebras, .sambanova, .databricks, .perplexity, .modal, .morphllm, .opencodeGo,
             .zyphra, .makora, .meta, .runinfra, .none:
            return .openAICompatible
        }
    }

    static func supportsOpenAIStyleReasoningEffort(for providerType: ProviderType?, modelID: String) -> Bool {
        requestShape(for: providerType, modelID: modelID).supportsOpenAIStyleReasoningEffort
    }

    static func supportsOpenAIStyleExtremeEffort(for providerType: ProviderType?, modelID: String) -> Bool {
        guard supportsOpenAIStyleReasoningEffort(for: providerType, modelID: modelID) else {
            return false
        }

        let canonicalLowerModelID = canonicalOpenAIModelID(lowerModelID: modelID.lowercased())
        return openAIStyleExtremeEffortModelIDs.contains(canonicalLowerModelID)
    }

    static func supportsOpenAIStyleMaxEffort(for providerType: ProviderType?, modelID: String) -> Bool {
        guard supportsOpenAIStyleReasoningEffort(for: providerType, modelID: modelID) else {
            return false
        }

        let lowerModelID = modelID.lowercased()
        if providerType == .openrouter,
           openRouterHighBandEffortModelIDs.contains(lowerModelID)
            || openRouterMinimalMaxEffortModelIDs.contains(lowerModelID)
            || openRouterFullLadderEffortModelIDs.contains(lowerModelID)
            || openRouterDeepSeekV4GAReasoningEffortModelIDs.contains(lowerModelID)
            || glm53LowHighMaxReasoningEffortModelIDs.contains(lowerModelID)
            || openRouterOxAlphaReasoningEffortModelIDs.contains(lowerModelID) {
            return true
        }

        // Hosted Kimi K3 / Baseten effort bands include an explicit `max` wire value
        // (Together, DeepInfra, Fireworks, Vercel Fast, Baseten — verified 2026-07-29).
        // Branch by provider first so one provider's ID set cannot enable max on another
        // (e.g. Baseten's Inkling ID must not grant max on Together).
        // Do not call supportedReasoningEfforts here (recursion).
        switch providerType {
        case .together:
            if togetherKimiK3ReasoningEffortModelIDs.contains(lowerModelID)
                || togetherDeepSeekV4GAReasoningEffortModelIDs.contains(lowerModelID)
                || glm53LowHighMaxReasoningEffortModelIDs.contains(lowerModelID) {
                return true
            }
        case .deepinfra:
            if deepInfraKimiK3ReasoningEffortModelIDs.contains(lowerModelID)
                || deepInfraDeepSeekV4Pro0813ReasoningEffortModelIDs.contains(lowerModelID)
                || lowerModelID == "deepseek-ai/deepseek-v4-flash-0731"
                || glm53LowHighMaxReasoningEffortModelIDs.contains(lowerModelID) {
                return true
            }
        case .fireworks:
            if fireworksKimiK3ReasoningEffortModelIDs.contains(lowerModelID)
                || fireworksDeepSeekV4Pro0813ReasoningEffortModelIDs.contains(lowerModelID)
                || lowerModelID == "accounts/fireworks/models/glm-5p3"
                || lowerModelID == "fireworks/glm-5p3"
                || lowerModelID == "accounts/fireworks/routers/glm-5p3-fast"
                || lowerModelID == "accounts/fireworks/models/glm-5p3-flash"
                || lowerModelID == "fireworks/glm-5p3-flash"
                || lowerModelID == "accounts/fireworks/models/deepseek-v4-flash-0731"
                || lowerModelID == "fireworks/deepseek-v4-flash-0731"
                || fireworksCanonicalModelID(lowerModelID)
                    .map({
                        fireworksKimiK3ReasoningEffortModelIDs.contains($0)
                            || fireworksDeepSeekV4Pro0813ReasoningEffortModelIDs.contains($0)
                            || $0 == "glm-5p3"
                            || $0 == "glm-5p3-fast"
                            || $0 == "glm-5p3-flash"
                            || $0 == "deepseek-v4-flash-0731"
                    }) == true {
                return true
            }
        case .vercelAIGateway:
            if vercelKimiK3FastReasoningEffortModelIDs.contains(lowerModelID)
                || glm53LowHighMaxReasoningEffortModelIDs.contains(lowerModelID)
                || lowerModelID == "deepseek/deepseek-v4-pro-0813"
                || lowerModelID == "deepseek/deepseek-v4-flash-0731" {
                return true
            }
        case .cloudflareAIGateway:
            if lowerModelID == "moonshotai/kimi-k3-fast"
                || lowerModelID == "z-ai/glm-5.3"
                || lowerModelID == "deepseek/deepseek-v4-pro-0813"
                || lowerModelID == "deepseek/deepseek-v4-flash-0731" {
                return true
            }
        case .baseten:
            if basetenKimiK3ReasoningEffortModelIDs.contains(lowerModelID)
                || basetenInklingReasoningEffortModelIDs.contains(lowerModelID)
                || basetenWideEffortModelIDs.contains(lowerModelID)
                || basetenDeepSeekV4Pro0813ReasoningEffortModelIDs.contains(lowerModelID)
                || glm53LowHighMaxReasoningEffortModelIDs.contains(lowerModelID)
                || basetenGLMEffortModelIDs.contains(lowerModelID) {
                return true
            }
        case .modal:
            if modalKimiK3ReasoningEffortModelIDs.contains(lowerModelID)
                || modalInklingReasoningEffortModelIDs.contains(lowerModelID)
                || lowerModelID == "zai-org/glm-5.3"
                || lowerModelID == "zai-org/glm-5.3-flash"
                || lowerModelID == "deepseek-ai/deepseek-v4-pro-0813"
                || lowerModelID == "deepseek-ai/deepseek-v4-flash-0731" {
                return true
            }
        case .runinfra:
            if runinfraDeepSeekV4FlashReasoningEffortModelIDs.contains(lowerModelID) {
                return true
            }
        case .router:
            // Early return, not a fall-through `if`: Router relabels OpenAI models
            // under their bare public names, so the generic tail below would grant
            // `max` to any Router ID that happens to collide with the GPT-5.6 set —
            // and would never be able to deny it for Router IDs that lack the band.
            return routerMaxEffortModelIDs.contains(lowerModelID)
        default:
            break
        }

        let canonicalLowerModelID = canonicalOpenAIModelID(lowerModelID: lowerModelID)
        return openAIStyleMaxEffortModelIDs.contains(canonicalLowerModelID)
    }

    /// GPT-5.6 Responses API `reasoning.mode = "pro"` (not a separate model slug on OpenAI).
    /// Limited to native OpenAI / OpenAI WebSocket providers — gateways may not forward the
    /// field, and the strict OpenCode Go proxy rejects fields it does not know. Matches the
    /// gating `supportsOpenAIStyleVerbosity` already applies.
    static func supportsOpenAIStyleProMode(for providerType: ProviderType?, modelID: String) -> Bool {
        switch providerType {
        case .openai, .openaiWebSocket, .none:
            break
        default:
            return false
        }
        guard supportsOpenAIStyleReasoningEffort(for: providerType, modelID: modelID) else {
            return false
        }
        let canonicalLowerModelID = canonicalOpenAIModelID(lowerModelID: modelID.lowercased())
        return openAIStyleProModeModelIDs.contains(canonicalLowerModelID)
    }

    /// Responses API `reasoning.context` support (exact IDs).
    /// Native OpenAI / OpenAI WebSocket only, for the same reason as `reasoning.mode` above.
    static func supportsOpenAIStyleReasoningContext(for providerType: ProviderType?, modelID: String) -> Bool {
        switch providerType {
        case .openai, .openaiWebSocket, .none:
            break
        default:
            return false
        }
        guard supportsOpenAIStyleReasoningEffort(for: providerType, modelID: modelID) else {
            return false
        }
        let canonicalLowerModelID = canonicalOpenAIModelID(lowerModelID: modelID.lowercased())
        return openAIStyleReasoningContextModelIDs.contains(canonicalLowerModelID)
    }

    /// Responses API `text.verbosity` support (exact IDs).
    /// Limited to native OpenAI / OpenAI WebSocket providers — gateways may not forward the field.
    static func supportsOpenAIStyleVerbosity(for providerType: ProviderType?, modelID: String) -> Bool {
        switch providerType {
        case .openai, .openaiWebSocket, .none:
            break
        case .router:
            // Router's own /v1/models reports verbosity.supported for exactly the
            // GPT-5 family; verified accepted on gpt-5.4 (2026-08-22).
            return routerVerbosityModelIDs.contains(modelID.lowercased())
        default:
            return false
        }
        let canonicalLowerModelID = canonicalOpenAIModelID(lowerModelID: modelID.lowercased())
        return openAIStyleVerbosityModelIDs.contains(canonicalLowerModelID)
    }

    /// - Parameter declaredEfforts: the band the provider itself reported for this
    ///   model (`ModelReasoningConfig.supportedEfforts`). When present it wins
    ///   outright: it is live truth for a model the bundled catalog may predate, and
    ///   on providers that enforce their bands the derived ladder below would happily
    ///   offer a value the model rejects. Callers without a model in hand pass nil.
    static func supportedReasoningEfforts(
        for providerType: ProviderType?,
        modelID: String,
        declaredEfforts: [ReasoningEffort]? = nil
    ) -> [ReasoningEffort] {
        if let declaredEfforts, !declaredEfforts.isEmpty {
            return declaredEfforts
        }

        let lowerModelID = modelID.lowercased()

        // Gateway-prefixed Gemini IDs (google/…, google-ai-studio/…, etc.) share the
        // native Gemini thinking-level bands so catalog defaults like `.minimal` stick.
        if let geminiEfforts = geminiThinkingEffortsIfApplicable(
            for: providerType,
            lowerModelID: lowerModelID
        ) {
            return geminiEfforts
        }

        switch providerType {
        case .perplexity:
            return defaultGeminiReasoningEfforts
        case .anthropic, .claudeManagedAgents:
            return supportedAnthropicEfforts(lowerModelID: lowerModelID)
        case .groq where lowerModelID == "qwen/qwen3.8-27b":
            // Groq Chat API: none/low/medium/high (default none). `high` is native xhigh.
            return [.none, .low, .medium, .high]
        case .groq where lowerModelID == "qwen/qwen3.6-27b":
            // Groq: `none` disables; omit/`default` uses the model default.
            return [.none]
        case .deepseek where deepSeekV4ReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .high, .max]
        case .openrouter where openRouterDeepSeekV4GAReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .high, .max]
        case .openrouter where glm53LowHighMaxReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .high, .max]
        case .openrouter where openRouterOxAlphaReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .high, .max]
        case .openrouter where openRouterQwen38OpenWeightReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .medium, .xhigh]
        case .openrouter where openRouterQwen38CloudMaxReasoningEffortModelIDs.contains(lowerModelID):
            return [.minimal, .low, .medium, .high, .xhigh]
        case .openrouter where openRouterDeepSeekV4ReasoningEffortModelIDs.contains(lowerModelID):
            return [.high, .xhigh]
        case .openrouter where xAIMultiAgentReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .medium, .high, .xhigh]
        case .openrouter where xAIAlwaysOnStandardEffortWithXHighModelIDs.contains(lowerModelID):
            return [.low, .medium, .high, .xhigh]
        case .openrouter where xAIAlwaysOnStandardEffortModelIDs.contains(lowerModelID):
            return [.low, .medium, .high]
        case .openrouter where xAIStandardEffortWithNoneModelIDs.contains(lowerModelID):
            return [.none, .low, .medium, .high]
        case .openrouter where openRouterFullLadderEffortModelIDs.contains(lowerModelID):
            return [.low, .medium, .high, .xhigh, .max]
        case .openrouter where openRouterHighBandEffortModelIDs.contains(lowerModelID):
            return [.high, .xhigh, .max]
        case .openrouter where openRouterMinimalHighEffortModelIDs.contains(lowerModelID):
            return [.minimal, .high]
        case .openrouter where openRouterMinimalMaxEffortModelIDs.contains(lowerModelID):
            return [.none, .minimal, .low, .medium, .high, .max]
        case .openrouter where openRouterLowHighEffortModelIDs.contains(lowerModelID):
            return [.low, .high]
        case .together where togetherDeepSeekV4GAReasoningEffortModelIDs.contains(lowerModelID)
            || glm53LowHighMaxReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .high, .max]
        case .together where togetherDeepSeekV4ReasoningEffortModelIDs.contains(lowerModelID):
            return [.high]
        case .together where togetherQwen38TextReasoningEffortModelIDs.contains(lowerModelID) || lowerModelID == "qwen/qwen3.8-27b":
            return [.low, .high, .xhigh]
        case .together where togetherKimiK3ReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .high, .max]
        case .deepinfra where deepInfraDeepSeekV4Pro0813ReasoningEffortModelIDs.contains(lowerModelID)
            || lowerModelID == "deepseek-ai/deepseek-v4-flash-0731"
            || glm53LowHighMaxReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .high, .max]
        case .deepinfra where deepInfraQwen38TextReasoningEffortModelIDs.contains(lowerModelID) || lowerModelID == "qwen/qwen3.8-27b":
            return [.low, .medium, .xhigh]
        case .deepinfra where deepInfraDeepSeekV4ReasoningEffortModelIDs.contains(lowerModelID):
            return [.high]
        case .deepinfra where deepInfraKimiK3ReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .high, .max]
        case .fireworks where fireworksDeepSeekV4Pro0813ReasoningEffortModelIDs.contains(lowerModelID)
            || lowerModelID == "accounts/fireworks/models/glm-5p3"
            || lowerModelID == "fireworks/glm-5p3"
            || lowerModelID == "accounts/fireworks/routers/glm-5p3-fast"
            || lowerModelID == "accounts/fireworks/models/glm-5p3-flash"
            || lowerModelID == "fireworks/glm-5p3-flash"
            || lowerModelID == "accounts/fireworks/models/deepseek-v4-flash-0731"
            || lowerModelID == "fireworks/deepseek-v4-flash-0731"
            || fireworksCanonicalModelID(lowerModelID).map({
                fireworksDeepSeekV4Pro0813ReasoningEffortModelIDs.contains($0)
                    || $0 == "glm-5p3"
                    || $0 == "glm-5p3-fast"
                    || $0 == "glm-5p3-flash"
                    || $0 == "deepseek-v4-flash-0731"
            }) == true:
            return [.low, .high, .max]
        case .fireworks where fireworksQwen38TextReasoningEffortModelIDs.contains(lowerModelID)
            || lowerModelID == "accounts/fireworks/models/qwen3p8-27b"
            || lowerModelID == "fireworks/qwen3p8-27b"
            || fireworksCanonicalModelID(lowerModelID).map({
                fireworksQwen38TextReasoningEffortModelIDs.contains($0)
                    || $0 == "qwen3p8-27b"
            }) == true:
            return [.low, .medium, .xhigh]
        case .fireworks where fireworksKimiK3ReasoningEffortModelIDs.contains(lowerModelID)
            || fireworksCanonicalModelID(lowerModelID).map({ fireworksKimiK3ReasoningEffortModelIDs.contains($0) }) == true:
            return [.none, .low, .medium, .high, .max]
        case .vercelAIGateway where vercelKimiK3FastReasoningEffortModelIDs.contains(lowerModelID)
            || glm53LowHighMaxReasoningEffortModelIDs.contains(lowerModelID)
            || lowerModelID == "deepseek/deepseek-v4-pro-0813"
            || lowerModelID == "deepseek/deepseek-v4-flash-0731":
            return [.low, .high, .max]
        case .vercelAIGateway where lowerModelID == "qwen/qwen3.8-2.4t-a95b" || lowerModelID == "qwen/qwen3.8-27b":
            return [.low, .medium, .xhigh]
        case .vercelAIGateway where lowerModelID == "qwen/qwen3.8-max":
            return [.minimal, .low, .medium, .high, .xhigh]
        case .cloudflareAIGateway where lowerModelID == "moonshotai/kimi-k3-fast"
            || lowerModelID == "z-ai/glm-5.3"
            || lowerModelID == "deepseek/deepseek-v4-pro-0813"
            || lowerModelID == "deepseek/deepseek-v4-flash-0731":
            return [.low, .high, .max]
        case .cloudflareAIGateway where lowerModelID == "qwen/qwen3.8-2.4t-a95b" || lowerModelID == "qwen/qwen3.8-27b":
            return [.low, .medium, .xhigh]
        case .cloudflareAIGateway where lowerModelID == "qwen/qwen3.8-max":
            return [.minimal, .low, .medium, .high, .xhigh]
        case .baseten where basetenKimiK3ReasoningEffortModelIDs.contains(lowerModelID):
            return [.none, .low, .high, .max]
        case .baseten where basetenInklingReasoningEffortModelIDs.contains(lowerModelID):
            return [.none, .minimal, .low, .medium, .high, .xhigh, .max]
        case .baseten where basetenWideEffortModelIDs.contains(lowerModelID):
            return [.none, .minimal, .low, .medium, .high, .xhigh, .max]
        case .baseten where basetenDeepSeekV4Pro0813ReasoningEffortModelIDs.contains(lowerModelID):
            return [.none, .low, .high, .max]
        case .baseten where glm53LowHighMaxReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .high, .max]
        case .baseten where basetenGLMEffortModelIDs.contains(lowerModelID):
            return [.none, .high, .max]
        case .baseten where lowerModelID == "qwen/qwen3.8-2.4t-a95b" || lowerModelID == "qwen/qwen3.8-27b":
            return [.none, .low, .medium, .xhigh]
        case .baseten where basetenMercury2ReasoningEffortModelIDs.contains(lowerModelID):
            return [.none, .low, .medium, .high]
        case .modal where lowerModelID == "zai-org/glm-5.3-flash":
            // Official Flash band; Modal does not publish an effort matrix.
            // `none` is rejected on the native weights.
            return [.low, .high, .max]
        case .modal where modalKimiK3ReasoningEffortModelIDs.contains(lowerModelID)
            || lowerModelID == "zai-org/glm-5.3"
            || lowerModelID == "deepseek-ai/deepseek-v4-pro-0813"
            || lowerModelID == "deepseek-ai/deepseek-v4-flash-0731":
            return [.none, .low, .high, .max]
        case .modal where modalInklingReasoningEffortModelIDs.contains(lowerModelID):
            return [.none, .minimal, .low, .medium, .high, .xhigh, .max]
        case .modal where modalQwen38TextReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .medium, .xhigh]
        case .runinfra where runinfraDeepSeekV4FlashReasoningEffortModelIDs.contains(lowerModelID):
            return [.none, .low, .medium, .max]
        case .runinfra where runinfraQwen3827BReasoningEffortModelIDs.contains(lowerModelID):
            return [.none, .low, .medium, .xhigh]
        case .runinfra where runinfraQwen3824TReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .medium, .xhigh]
        case .xai where xAIMultiAgentReasoningEffortModelIDs.contains(lowerModelID):
            // Multi-agent: low/medium → 4 agents, high/xhigh → 16 agents.
            return [.low, .medium, .high, .xhigh]
        case .xai where xAIAlwaysOnStandardEffortWithXHighModelIDs.contains(lowerModelID):
            return [.low, .medium, .high, .xhigh]
        case .xai where xAIAlwaysOnStandardEffortModelIDs.contains(lowerModelID):
            return [.low, .medium, .high]
        case .xai where xAIStandardEffortWithNoneModelIDs.contains(lowerModelID):
            return [.none, .low, .medium, .high]
        case .vercelAIGateway where xAIMultiAgentReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .medium, .high, .xhigh]
        case .vercelAIGateway where xAIAlwaysOnStandardEffortWithXHighModelIDs.contains(lowerModelID):
            return [.low, .medium, .high, .xhigh]
        case .vercelAIGateway where xAIAlwaysOnStandardEffortModelIDs.contains(lowerModelID):
            return [.low, .medium, .high]
        case .vercelAIGateway where xAIStandardEffortWithNoneModelIDs.contains(lowerModelID):
            return [.none, .low, .medium, .high]
        case .mistral where mistralHighOnlyReasoningEffortModelIDs.contains(lowerModelID):
            return [.high]
        case .fireworks where fireworksDeepSeekV4ProModelIDs.contains(lowerModelID):
            return [.high, .max]
        case .opencodeGo where deepSeekV4ReasoningEffortModelIDs.contains(lowerModelID):
            return [.high, .max]
        case .opencodeGo where glm53LowHighMaxReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .high, .max]
        case .opencodeGo where opencodeGoOxAlphaReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .high, .max]
        case .opencodeGo where opencodeGoGLMHighMaxReasoningEffortModelIDs.contains(lowerModelID):
            return [.high, .max]
        case .opencodeGo where opencodeGoHy3ReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .high]
        case .opencodeGo where opencodeGoHy4ReasoningEffortModelIDs.contains(lowerModelID):
            return [.high]
        case .opencodeGo where xAIAlwaysOnStandardEffortWithXHighModelIDs.contains(lowerModelID):
            // grok-4.6 on Go: always-on low/medium/high/xhigh (docs.x.ai/developers/grok-4-6).
            // Distinct from grok-4.5, which rejects xhigh. Exact ID via the shared set.
            return [.low, .medium, .high, .xhigh]
        case .opencodeGo where xAIAlwaysOnStandardEffortModelIDs.contains(lowerModelID):
            return [.low, .medium, .high]
        case .opencodeGo where isOpenCodeGoMuseSparkModelID(lowerModelID):
            // Live Go `/models` serves muse-spark-1.2 and muse-spark-1.2-contributor.
            // Same Meta band (minimal..xhigh). "none" is HTTP 400; "max" is not accepted.
            return [.minimal, .low, .medium, .high, .xhigh]
        case .zhipuCodingPlan where glm53LowHighMaxReasoningEffortModelIDs.contains(lowerModelID):
            return [.low, .high, .max]
        case .zhipuCodingPlan where zhipuGLM52HighMaxReasoningEffortModelIDs.contains(lowerModelID):
            return [.high, .max]
        case .meta:
            // Muse Spark accepts minimal..xhigh ("none" returns HTTP 400 and is handled
            // by omitting the field; "max" is not accepted).
            return [.minimal, .low, .medium, .high, .xhigh]
        // Router bands are enforced by the gateway (`400 Invalid reasoning effort.`),
        // so every band it publishes gets an explicit arm rather than falling through
        // to the derived OpenAI ladder below.
        case .router where routerFullLadderEffortModelIDs.contains(lowerModelID):
            return [.none, .minimal, .low, .medium, .high, .xhigh, .max]
        case .router where routerNoneToExtremeEffortModelIDs.contains(lowerModelID):
            return [.none, .minimal, .low, .medium, .high, .xhigh]
        case .router where routerMinimalToMaxEffortModelIDs.contains(lowerModelID):
            return [.minimal, .low, .medium, .high, .xhigh, .max]
        case .router where routerMinimalToExtremeEffortModelIDs.contains(lowerModelID):
            return [.minimal, .low, .medium, .high, .xhigh]
        case .router where routerNoneLowToMaxEffortModelIDs.contains(lowerModelID):
            return [.none, .low, .medium, .high, .xhigh, .max]
        case .router where routerNoneLowToExtremeEffortModelIDs.contains(lowerModelID):
            return [.none, .low, .medium, .high, .xhigh]
        case .router where routerMediumToExtremeEffortModelIDs.contains(lowerModelID):
            return [.medium, .high, .xhigh]
        case .router where routerNoneLowToHighEffortModelIDs.contains(lowerModelID):
            return [.none, .low, .medium, .high]
        case .router where routerMinimalToHighEffortModelIDs.contains(lowerModelID):
            return [.minimal, .low, .medium, .high]
        case .router where routerHighOnlyEffortModelIDs.contains(lowerModelID):
            return [.high]
        case .router where routerLowToHighEffortModelIDs.contains(lowerModelID):
            return [.low, .medium, .high]
        default:
            break
        }

        guard supportsOpenAIStyleReasoningEffort(for: providerType, modelID: modelID) else {
            return defaultReasoningEfforts
        }

        var efforts = defaultReasoningEfforts
        if supportsOpenAIStyleExtremeEffort(for: providerType, modelID: modelID) {
            efforts.append(.xhigh)
        }
        if supportsOpenAIStyleMaxEffort(for: providerType, modelID: modelID) {
            efforts.append(.max)
        }
        return efforts
    }

    private static func supportedAnthropicEfforts(lowerModelID: String) -> [ReasoningEffort] {
        if AnthropicModelLimits.supportsXHighEffort(for: lowerModelID) {
            return [.low, .medium, .high, .xhigh, .max]
        }
        if AnthropicModelLimits.supportsMaxEffort(for: lowerModelID) {
            return [.low, .medium, .high, .max]
        }
        return defaultReasoningEfforts
    }

    private static func geminiThinkingEffortsIfApplicable(
        for providerType: ProviderType?,
        lowerModelID: String
    ) -> [ReasoningEffort]? {
        switch providerType {
        case .gemini, .vertexai:
            return supportedGeminiThinkingEfforts(lowerModelID: lowerModelID)
        case .openrouter, .vercelAIGateway, .cloudflareAIGateway:
            let canonical = canonicalGoogleModelID(lowerModelID: lowerModelID)
            guard isKnownGeminiEffortPolicyModel(canonical) else { return nil }
            return supportedGeminiThinkingEfforts(lowerModelID: canonical)
        default:
            return nil
        }
    }

    private static func isKnownGeminiEffortPolicyModel(_ lowerModelID: String) -> Bool {
        gemini31FlashImageEffortModelIDs.contains(lowerModelID)
            || gemini3FlashEffortModelIDs.contains(lowerModelID)
            || gemini37FlashEffortModelIDs.contains(lowerModelID)
            || gemini31ProEffortModelIDs.contains(lowerModelID)
            || gemini3ProLowHighEffortModelIDs.contains(lowerModelID)
    }

    private static func supportedGeminiThinkingEfforts(lowerModelID: String) -> [ReasoningEffort] {
        let id = canonicalGoogleModelID(lowerModelID: lowerModelID)
        if gemini31FlashImageEffortModelIDs.contains(id) {
            return [.minimal, .high]
        }
        if gemini3FlashEffortModelIDs.contains(id) {
            return defaultGeminiReasoningEfforts
        }
        if gemini37FlashEffortModelIDs.contains(id) {
            return defaultReasoningEfforts
        }
        if gemini31ProEffortModelIDs.contains(id) {
            return defaultReasoningEfforts
        }
        if gemini3ProLowHighEffortModelIDs.contains(id) {
            return [.low, .high]
        }
        return defaultGeminiReasoningEfforts
    }

    static func normalizedReasoningEffort(
        _ effort: ReasoningEffort,
        for providerType: ProviderType?,
        modelID: String,
        declaredEfforts: [ReasoningEffort]? = nil
    ) -> ReasoningEffort {
        guard effort != .none else { return .none }

        let supportedEfforts = supportedReasoningEfforts(
            for: providerType,
            modelID: modelID,
            declaredEfforts: declaredEfforts
        )
        guard !supportedEfforts.isEmpty else { return effort }
        if supportedEfforts.contains(effort) {
            return effort
        }

        return closestSupportedEffort(to: effort, in: supportedEfforts)
    }

    private static func closestSupportedEffort(
        to effort: ReasoningEffort,
        in supportedEfforts: [ReasoningEffort]
    ) -> ReasoningEffort {
        guard let targetRank = reasoningEffortRank[effort] else {
            return supportedEfforts.last ?? effort
        }

        var best: (effort: ReasoningEffort, distance: Int, rank: Int)?
        for candidate in supportedEfforts {
            guard let candidateRank = reasoningEffortRank[candidate] else { continue }
            let distance = abs(candidateRank - targetRank)

            if let currentBest = best {
                if distance < currentBest.distance
                    || (distance == currentBest.distance && candidateRank > currentBest.rank) {
                    best = (candidate, distance, candidateRank)
                }
                continue
            }

            best = (candidate, distance, candidateRank)
        }

        return best?.effort ?? supportedEfforts.last ?? effort
    }

    static func supportsWebSearch(for providerType: ProviderType?, modelID: String) -> Bool {
        let lowerModelID = modelID.lowercased()

        switch providerType {
        case .openai, .openaiWebSocket:
            return supportsOpenAIWebSearch(lowerModelID: lowerModelID)
        case .openrouter:
            return supportsOpenRouterWebSearch(lowerModelID: lowerModelID)
        case .anthropic:
            // Server-side web search is available on current Claude models including Fable 5.1 /
            // Mythos 5.1 and Fable 5 / Mythos 5 (dynamic filtering docs list them as of 2026-07).
            return isAnthropicModelID(lowerModelID)
        case .claudeManagedAgents:
            return false
        case .perplexity:
            return true
        case .xai:
            return !isLikelyMediaGenerationModelID(lowerModelID)
        case .gemini:
            return supportsGoogleSearch(lowerModelID: lowerModelID, providerType: .gemini)
        case .vertexai:
            return supportsGoogleSearch(lowerModelID: lowerModelID, providerType: .vertexai)
        case .opencodeGo:
            return MiMoModelIDs.tokenPlanExactModelIDs.contains(lowerModelID)
        case .mimoTokenPlanOpenAI:
            return MiMoModelIDs.tokenPlanExactModelIDs.contains(lowerModelID)
        case .meta:
            return isMetaMuseSparkModelID(lowerModelID)
        case .router:
            // Router's capability table lists basic web search as OpenAI-only, and the
            // `{"type":"web_search"}` tool comes back fully populated on gpt-5.4-mini
            // (verified 2026-08-22). Fireworks-served `gpt-oss-*` share the naming but
            // not the backend, so the allowlist is by exact ID.
            return routerWebSearchModelIDs.contains(lowerModelID)
        case .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .groq,
             .cohere, .mistral, .deepinfra, .together, .baseten, .runinfra, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan,
             .mimoTokenPlanAnthropic, .fireworks, .cerebras, .sambanova, .databricks, .modal, .morphllm, .zyphra, .makora, .kimiForCoding, .none:
            return false
        }
    }

    /// Exact Muse Spark IDs live on OpenCode Go (`GET /zen/go/v1/models`, 2026-08-20, 2026-09-03).
    /// `muse-spark-1.1` is not served.
    static func isOpenCodeGoMuseSparkModelID(_ lowerModelID: String) -> Bool {
        switch lowerModelID {
        case "muse-spark-1.2", "muse-spark-1.2-contributor", "muse-spark-1.3", "muse-spark-1.3-contributor":
            return true
        default:
            return false
        }
    }

    /// Exact Muse Spark IDs on the Meta Model API (and bare IDs without gateway prefix).
    static func isMetaMuseSparkModelID(_ lowerModelID: String) -> Bool {
        let bare = lowerModelID.hasPrefix("meta/")
            ? String(lowerModelID.dropFirst("meta/".count))
            : lowerModelID
        switch bare {
        case "muse-spark-1.1", "muse-spark-1.2", "muse-spark-1.2-contributor", "muse-spark-1.3", "muse-spark-1.3-contributor":
            return true
        default:
            return false
        }
    }

    static func defaultReasoningConfig(for providerType: ProviderType?, modelID: String) -> ModelReasoningConfig? {
        let lowerModelID = modelID.lowercased()
        let shape = requestShape(for: providerType, modelID: modelID)

        if providerType == .mistral,
           mistralHighOnlyReasoningEffortModelIDs.contains(lowerModelID) {
            return ModelReasoningConfig(type: .effort, defaultEffort: .high)
        }

        guard isReasoningModelID(lowerModelID, shape: shape) else {
            return nil
        }

        switch shape {
        case .anthropic:
            return defaultAnthropicReasoningConfig(lowerModelID: lowerModelID, shape: shape)
        case .gemini:
            return defaultGeminiReasoningConfig(lowerModelID: lowerModelID)
        case .openAICompatible, .openAIResponses:
            return defaultOpenAIFamilyReasoningConfig(lowerModelID: lowerModelID)
        }
    }

    private static func defaultAnthropicReasoningConfig(
        lowerModelID: String,
        shape: ModelRequestShape
    ) -> ModelReasoningConfig {
        if shape == .anthropic {
            if AnthropicModelLimits.supportsAdaptiveThinking(for: lowerModelID) {
                return ModelReasoningConfig(type: .effort, defaultEffort: .high)
            }
            return ModelReasoningConfig(type: .budget, defaultBudget: 2048)
        }

        if AnthropicModelLimits.supportsAdaptiveThinking(for: lowerModelID) {
            return ModelReasoningConfig(type: .effort, defaultEffort: .high)
        }
        return ModelReasoningConfig(type: .effort, defaultEffort: .medium)
    }

    private static func defaultGeminiReasoningConfig(lowerModelID: String) -> ModelReasoningConfig {
        if lowerModelID.contains("gemini-3-pro") {
            return ModelReasoningConfig(type: .effort, defaultEffort: .high)
        }
        return ModelReasoningConfig(type: .effort, defaultEffort: .medium)
    }

    private static func defaultOpenAIFamilyReasoningConfig(lowerModelID: String) -> ModelReasoningConfig {
        if deepSeekV4ReasoningEffortModelIDs.contains(lowerModelID) {
            return ModelReasoningConfig(type: .effort, defaultEffort: .high)
        }
        if isGeminiReasoningModelID(lowerModelID) {
            return defaultGeminiReasoningConfig(lowerModelID: lowerModelID)
        }
        if isAnthropicModelID(lowerModelID) {
            return defaultAnthropicReasoningConfig(lowerModelID: lowerModelID, shape: .openAICompatible)
        }

        let canonicalLowerModelID = canonicalOpenAIModelID(lowerModelID: lowerModelID)
        if openAINoneDefaultReasoningModelIDs.contains(canonicalLowerModelID) {
            return ModelReasoningConfig(type: .effort, defaultEffort: ReasoningEffort.none)
        }
        if openAIHighDefaultReasoningModelIDs.contains(canonicalLowerModelID) {
            return ModelReasoningConfig(type: .effort, defaultEffort: .high)
        }

        return ModelReasoningConfig(type: .effort, defaultEffort: .medium)
    }

    private static func isReasoningModelID(_ lowerModelID: String, shape: ModelRequestShape) -> Bool {
        switch shape {
        case .anthropic:
            return isAnthropicModelID(lowerModelID)
        case .gemini:
            return isGeminiReasoningModelID(lowerModelID)
        case .openAICompatible, .openAIResponses:
            return isAnthropicModelID(lowerModelID)
                || isGeminiReasoningModelID(lowerModelID)
                || isOpenAIReasoningModelID(lowerModelID)
                || containsAnyFragment(in: lowerModelID, fragments: reasoningKeywords)
        }
    }

    private static func isAnthropicModelID(_ lowerModelID: String) -> Bool {
        lowerModelID.contains("claude") || lowerModelID.contains("anthropic/")
    }

    private static func isGeminiModelID(_ lowerModelID: String) -> Bool {
        lowerModelID.contains("gemini")
    }

    private static func isGeminiReasoningModelID(_ lowerModelID: String) -> Bool {
        isGeminiModelID(lowerModelID)
            && !lowerModelID.contains("-image")
            && !lowerModelID.contains("imagen")
    }

    private static func isOpenAIReasoningModelID(_ lowerModelID: String) -> Bool {
        lowerModelID.contains("gpt-5") || hasPrefixOrScopedPrefix(lowerModelID, prefixes: ["o1", "o3", "o4"])
    }

    private static func supportsOpenAIWebSearch(lowerModelID: String) -> Bool {
        guard lowerModelID.hasPrefix("gpt-")
            || lowerModelID.contains("/gpt-")
            || hasPrefixOrScopedPrefix(lowerModelID, prefixes: ["o3", "o4"]) else {
            return false
        }

        return !isLikelyMediaGenerationModelID(lowerModelID)
    }

    private static func supportsOpenRouterWebSearch(lowerModelID rawModelID: String) -> Bool {
        // OpenRouter "latest"-family aliases are prefixed with `~` (e.g. `~openai/gpt-latest`).
        // Strip it so they share the same web-search policy as their canonical twins.
        let lowerModelID = rawModelID.hasPrefix("~") ? String(rawModelID.dropFirst()) : rawModelID

        if containsAnyFragment(in: lowerModelID, fragments: searchKeywords) {
            return true
        }

        if lowerModelID.hasPrefix("openai/") {
            let canonical = String(lowerModelID.dropFirst("openai/".count))
            return supportsOpenAIWebSearch(lowerModelID: canonical)
        }

        if lowerModelID.hasPrefix("anthropic/") {
            return true
        }

        if lowerModelID.hasPrefix("google/") {
            return supportsGoogleSearch(lowerModelID: lowerModelID, providerType: .openrouter)
        }

        if lowerModelID.hasPrefix("x-ai/") || lowerModelID.hasPrefix("xai/") || lowerModelID.hasPrefix("perplexity/") {
            return !isLikelyMediaGenerationModelID(lowerModelID)
        }

        return false
    }

    private static func supportsGoogleSearch(lowerModelID: String, providerType: ProviderType?) -> Bool {
        let canonical = canonicalGoogleModelID(lowerModelID: lowerModelID)
        return googleSearchSupportedModelIDs(for: providerType).contains(canonical)
    }

    private static func googleSearchSupportedModelIDs(for providerType: ProviderType?) -> Set<String> {
        switch providerType {
        case .gemini:
            return geminiGoogleSearchSupportedModelIDs
        case .vertexai:
            return vertexGoogleSearchSupportedModelIDs
        case .openrouter:
            return openRouterGoogleSearchSupportedModelIDs
        default:
            return proxiedGoogleSearchSupportedModelIDs
        }
    }

    private static func supportsGoogleCodeExecution(lowerModelID: String, providerType: ProviderType?) -> Bool {
        let canonical = canonicalGoogleModelID(lowerModelID: lowerModelID)
        return googleCodeExecutionSupportedModelIDs(for: providerType).contains(canonical)
    }

    private static func googleCodeExecutionSupportedModelIDs(for providerType: ProviderType?) -> Set<String> {
        switch providerType {
        case .gemini:
            return geminiCodeExecutionSupportedModelIDs
        case .vertexai:
            return vertexCodeExecutionSupportedModelIDs
        default:
            return []
        }
    }

    private static func canonicalGoogleModelID(lowerModelID: String) -> String {
        for prefix in googleModelPrefixes where lowerModelID.hasPrefix(prefix) {
            return String(lowerModelID.dropFirst(prefix.count))
        }
        return lowerModelID
    }

    private static func isLikelyMediaGenerationModelID(_ lowerModelID: String) -> Bool {
        containsAnyFragment(in: lowerModelID, fragments: mediaGenerationKeywords)
    }

    private static func canonicalOpenAIModelID(lowerModelID: String) -> String {
        if lowerModelID.hasPrefix("openai/") {
            return String(lowerModelID.dropFirst("openai/".count))
        }
        return lowerModelID
    }

    private static func containsAnyFragment(in value: String, fragments: [String]) -> Bool {
        fragments.contains(where: value.contains)
    }

    private static func hasPrefixOrScopedPrefix(_ value: String, prefixes: [String]) -> Bool {
        prefixes.contains { prefix in
            value.hasPrefix(prefix) || value.contains("/\(prefix)")
        }
    }

    /// Whether the provider/model supports native code execution (OpenAI Code Interpreter, Anthropic Code Execution).
    static func supportsCodeExecution(for providerType: ProviderType?, modelID: String) -> Bool {
        let lowerModelID = modelID.lowercased()

        switch providerType {
        case .openai, .openaiWebSocket:
            // OpenAI Responses API code_interpreter tool uses an exact documented model allowlist.
            // WebSocket mode uses the same Responses API and supports code_interpreter for non-realtime models.
            return supportsOpenAICodeInterpreter(lowerModelID: lowerModelID)
        case .anthropic:
            // Anthropic code_execution tool uses an exact documented model allowlist.
            return supportsAnthropicCodeExecution(lowerModelID: lowerModelID)
        case .claudeManagedAgents:
            return false
        case .xai:
            return ModelCatalog.entry(for: modelID, provider: .xai)?.capabilities.contains(.codeExecution) ?? false
        case .gemini:
            // Gemini API `tools.code_execution`
            return supportsGoogleCodeExecution(lowerModelID: lowerModelID, providerType: .gemini)
        case .vertexai:
            // Vertex AI `tools.codeExecution`
            return supportsGoogleCodeExecution(lowerModelID: lowerModelID, providerType: .vertexai)
        case .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together, .baseten, .runinfra,
             .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks, .cerebras, .sambanova, .databricks, .modal, .morphllm,
             .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI, .opencodeGo, .router, .zyphra, .makora, .meta, .kimiForCoding, .none:
            return false
        }
    }

    private static func supportsOpenAICodeInterpreter(lowerModelID: String) -> Bool {
        let canonical = canonicalOpenAIModelID(lowerModelID: lowerModelID)
        return openAICodeInterpreterSupportedModelIDs.contains(canonical)
    }

    private static func supportsAnthropicCodeExecution(lowerModelID: String) -> Bool {
        let canonical: String
        if lowerModelID.hasPrefix("anthropic/") {
            canonical = String(lowerModelID.dropFirst("anthropic/".count))
        } else {
            canonical = lowerModelID
        }
        return anthropicCodeExecutionSupportedModelIDs.contains(canonical)
    }

    /// Whether the provider/model supports grounding with Google Maps.
    static func supportsGoogleMaps(for providerType: ProviderType?, modelID: String) -> Bool {
        let lowerModelID = modelID.lowercased()

        switch providerType {
        case .gemini:
            return supportsGoogleMapsGrounding(lowerModelID: lowerModelID, providerType: .gemini)
        case .vertexai:
            return supportsGoogleMapsGrounding(lowerModelID: lowerModelID, providerType: .vertexai)
        case .openai, .openaiWebSocket, .anthropic, .claudeManagedAgents, .xai, .githubCopilot,
             .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .perplexity,
             .groq, .cohere, .mistral, .deepinfra, .together, .baseten, .runinfra, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan,
             .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI, .fireworks, .cerebras, .sambanova, .databricks, .modal, .morphllm, .opencodeGo,
             .router, .zyphra, .makora, .meta, .kimiForCoding, .none:
            return false
        }
    }

    private static func supportsGoogleMapsGrounding(lowerModelID: String, providerType: ProviderType?) -> Bool {
        let canonical = canonicalGoogleModelID(lowerModelID: lowerModelID)
        return googleMapsSupportedModelIDs(for: providerType).contains(canonical)
    }

    private static func googleMapsSupportedModelIDs(for providerType: ProviderType?) -> Set<String> {
        switch providerType {
        case .gemini:
            return geminiGoogleMapsSupportedModelIDs
        case .vertexai:
            return vertexGoogleMapsSupportedModelIDs
        default:
            return []
        }
    }

    /// Models that support the `web_search_20260209` tool with dynamic filtering.
    /// Documented list includes Fable 5.1 / Mythos 5.1, Fable 5, Mythos 5, Opus 5,
    /// Opus 4.8/4.7/4.6, Sonnet 5/4.6. Dynamic filtering is "Claude 4.6 and later"
    /// plus Mythos; Fable 5.1 is the Fable 5 successor (2026-09-01).
    static func supportsWebSearchDynamicFiltering(for providerType: ProviderType?, modelID: String) -> Bool {
        guard providerType == .anthropic || providerType == .claudeManagedAgents else { return false }
        let lower = modelID.lowercased()
        return lower == "claude-fable-5-1"
            || lower == "claude-mythos-5-1"
            || lower == "claude-fable-5"
            || lower == "claude-mythos-5"
            || lower == "claude-opus-5"
            || lower == "claude-opus-4-8"
            || lower == "claude-opus-4-7"
            || lower == "claude-opus-4-6"
            || lower == "claude-sonnet-5"
            || lower == "claude-sonnet-4-6"
    }
}
