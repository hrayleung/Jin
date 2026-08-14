import Foundation

// MARK: - Independent Provider Records

extension ModelCatalog {

    // MARK: Anthropic

    static let anthropicRecords: [Record] = [
        // Fable/Mythos 5: adaptive thinking always on, effort low…max, no sampling params.
        // Official Supported features (2026-07) include code execution, memory tool, and PTC.
        // Fable may return stop_reason=refusal (HTTP 200). Mythos 5 is Project Glasswing only.
        Record(id: "claude-fable-5", displayName: "Claude Fable 5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 1_000_000,
               maxOutputTokens: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "claude-mythos-5", displayName: "Claude Mythos 5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 1_000_000,
               maxOutputTokens: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
        // Opus 5: successor to Opus 4.8 at the same $5/$25 pricing, 1M context (default AND
        // maximum — there is no separate 1M model ID) / 128k output. Same adaptive-thinking
        // surface as 4.8 with two flips handled in AnthropicModelLimits: thinking is ON when
        // `thinking` is omitted, and an explicit `{type: "disabled"}` is only accepted at
        // effort `high` or below. Full low…max effort ladder; fast mode supported.
        Record(id: "claude-opus-5", displayName: "Claude Opus 5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 1_000_000,
               maxOutputTokens: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "claude-opus-4-8", displayName: "Claude Opus 4.8",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 1_000_000,
               maxOutputTokens: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "claude-opus-4-7", displayName: "Claude Opus 4.7",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 1_000_000,
               maxOutputTokens: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "claude-opus-4-6", displayName: "Claude Opus 4.6",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 1_000_000,
               maxOutputTokens: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        // Sonnet 5: best speed/intelligence combination in the Sonnet tier, near-Opus quality
        // on coding and agentic work. Adaptive thinking (with explicit disable — unlike Fable 5,
        // omitting `thinking` on Sonnet 5 defaults to adaptive-on, not off). Full effort range
        // low...max (first Sonnet-tier model with xhigh). Unlike Fable 5/Mythos 5, Sonnet 5 DOES
        // support server-side code execution and web search (incl. dynamic filtering) at launch.
        Record(id: "claude-sonnet-5", displayName: "Claude Sonnet 5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 1_000_000,
               maxOutputTokens: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 1_000_000,
               maxOutputTokens: 64_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "claude-opus-4-5-20251101", displayName: "Claude Opus 4.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 200_000,
               maxOutputTokens: 64_000,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 1024),
               isFullySupported: true, isSeeded: true),
        Record(id: "claude-sonnet-4-5-20250929", displayName: "Claude Sonnet 4.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 200_000,
               maxOutputTokens: 64_000,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 1024),
               isFullySupported: true, isSeeded: true),
        Record(id: "claude-haiku-4-5-20251001", displayName: "Claude Haiku 4.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 200_000,
               maxOutputTokens: 64_000,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 1024),
               isFullySupported: true, isSeeded: true),
        Record(id: "claude-opus-4-1-20250805", displayName: "Claude Opus 4.1",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 200_000,
               maxOutputTokens: 32_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
        Record(id: "claude-opus-4-20250514", displayName: "Claude Opus 4 (Legacy)",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 200_000,
               maxOutputTokens: 32_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: false, isSeeded: false),
        Record(id: "claude-sonnet-4-20250514", displayName: "Claude Sonnet 4 (Legacy)",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 200_000,
               maxOutputTokens: 64_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: false, isSeeded: false),
        Record(id: "claude-opus-4", displayName: "Claude Opus 4",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
        Record(id: "claude-sonnet-4", displayName: "Claude Sonnet 4",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
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

    static let perplexityRecords: [Record] = [
        // Seeded (capabilities match DefaultProviderSeeds; nativePDF added per JinModelSupport)
        Record(id: "sonar", displayName: "Sonar",
               capabilities: [.streaming, .vision, .nativePDF],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
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

    // MARK: DeepInfra

    static let deepInfraRecords: [Record] = [
        // Seeded
        // Kimi K3 (live on DeepInfra serverless; verified against models.dev `deepinfra`
        // and Moonshot K3 docs, 2026-07-29): 1,048,576 context / 131,072 output,
        // text+image. Reasoning efforts low/high/max (default max). Video is not claimed
        // — OpenAI-compatible message translation has no video part builder here.
        Record(id: "moonshotai/Kimi-K3", displayName: "Kimi K3",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .max),
               isFullySupported: true, isSeeded: true),
        Record(id: "zai-org/GLM-5.2", displayName: "GLM-5.2",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 1_048_576,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "zai-org/GLM-5.1", displayName: "GLM-5.1",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 202_752,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "Qwen/Qwen3.6-35B-A3B", displayName: "Qwen3.6 35B A3B",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning", displayName: "Nemotron 3 Nano Omni 30B A3B Reasoning",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .videoInput, .reasoning],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "zai-org/GLM-5", displayName: "GLM-5",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 202_752,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "Qwen/Qwen3.5-397B-A17B", displayName: "Qwen3.5 397B A17B",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "Qwen/Qwen3.5-122B-A10B", displayName: "Qwen3.5 122B A10B",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "Qwen/Qwen3.5-35B-A3B", displayName: "Qwen3.5 35B A3B",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "Qwen/Qwen3.5-27B", displayName: "Qwen3.5 27B",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "Qwen/Qwen3.5-9B", displayName: "Qwen3.5 9B",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        // Catalog-only
        Record(id: "moonshotai/Kimi-K2-Instruct-0905", displayName: "Kimi K2 Instruct 0905",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 131_072,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "deepseek-ai/DeepSeek-V3.2", displayName: "DeepSeek V3.2",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 163_840,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "deepseek-ai/DeepSeek-V4-Flash", displayName: "DeepSeek V4 Flash",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
        Record(id: "deepseek-ai/DeepSeek-V4-Pro", displayName: "DeepSeek V4 Pro",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 65_536,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
        Record(id: "MiniMaxAI/MiniMax-M2.5", displayName: "MiniMax M2.5",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 196_608,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "openai/gpt-oss-120b", displayName: "GPT-OSS 120B",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 131_072,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "zai-org/GLM-4.7", displayName: "GLM-4.7",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 202_752,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "moonshotai/Kimi-K2.5", displayName: "Kimi K2.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "zai-org/GLM-4.7-Flash", displayName: "GLM-4.7 Flash",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 202_752,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "nvidia/Nemotron-3-Nano-30B-A3B", displayName: "Nemotron 3 Nano 30B A3B",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "openai/gpt-oss-20b", displayName: "GPT-OSS 20B",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 131_072,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "nvidia/NVIDIA-Nemotron-3-Super-120B-A12B", displayName: "NVIDIA Nemotron 3 Super 120B A12B",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "stepfun-ai/Step-3.5-Flash", displayName: "Step 3.5 Flash",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "Qwen/Qwen3-Max", displayName: "Qwen3 Max",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 256_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "Qwen/Qwen3-Max-Thinking", displayName: "Qwen3 Max Thinking",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 256_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
    ]

    // MARK: Together AI

    static let togetherRecords: [Record] = [
        // Seeded
        // Kimi K3 (Together serverless day-0; verified against together.ai/models/kimi-k3
        // and models.dev `togetherai`, 2026-07-29): 1,048,576 context / 131,072 output,
        // text+image (models.dev also lists video — not claimed: message translator has no
        // video part builder). Reasoning efforts low/high/max with top-level
        // `reasoning_effort`; default max. Cached-input pricing → promptCaching.
        Record(id: "moonshotai/Kimi-K3", displayName: "Kimi K3",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .max),
               isFullySupported: true, isSeeded: true),
        Record(id: "moonshotai/Kimi-K2.5", displayName: "Kimi K2.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        // Thinking Machines Inkling (live on Together serverless since 2026-07-15;
        // verified against docs.together.ai serverless-models and the model page,
        // 2026-07-18): 524,288 context on Together's deployment (1M is model-level),
        // text+image+audio input, cached-input pricing. Reasoning uses Together's
        // low/medium/high effort (TML documents the same named presets; the model
        // card default is "high") and has no true off switch, so the ID joins the
        // resolver's togetherAlwaysOnReasoningModelIDs. Max output is unpublished.
        Record(id: "thinkingmachines/Inkling", displayName: "Inkling",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 524_288,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "zai-org/GLM-5.2", displayName: "GLM-5.2",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: "zai-org/GLM-5", displayName: "GLM-5",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 202_752,
               maxOutputTokens: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: "deepseek-ai/DeepSeek-V3.1", displayName: "DeepSeek V3.1",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: "deepseek-ai/DeepSeek-V4-Pro", displayName: "DeepSeek V4 Pro",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 524_288,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "openai/gpt-oss-120b", displayName: "GPT-OSS 120B",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "Qwen/Qwen3.5-397B-A17B", displayName: "Qwen3.5 397B A17B",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "Qwen/Qwen3-235B-A22B-Instruct-2507-tput", displayName: "Qwen3 235B A22B Instruct 2507",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "Qwen/Qwen3-Coder-Next-FP8", displayName: "Qwen3 Coder Next",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        // Catalog-only
        Record(id: "MiniMaxAI/MiniMax-M2.5", displayName: "MiniMax M2.5",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 228_700,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8", displayName: "Qwen3 Coder 480B",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 256_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "Qwen/Qwen3.5-9B", displayName: "Qwen3.5 9B",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
        Record(id: "zai-org/GLM-4.7", displayName: "GLM-4.7",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 202_752,
               maxOutputTokens: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
        Record(id: "zai-org/GLM-4.5-Air-FP8", displayName: "GLM 4.5 Air",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 131_072,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "openai/gpt-oss-20b", displayName: "GPT-OSS 20B",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "Qwen/Qwen3-Next-80B-A3B-Instruct", displayName: "Qwen3 Next 80B A3B",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "meta-llama/Llama-4-Maverick-17B-128E-Instruct-FP8", displayName: "Llama 4 Maverick",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 1_048_576,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        // Together Videos API (POST /v2/videos). Exact IDs from serverless catalog
        // + docs.together.ai Seedance quickstarts / model pages.
        Record(id: "ByteDance/Seedance-2.0", displayName: "Seedance 2.0",
               capabilities: [.videoGeneration],
               contextWindow: 32_768,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "ByteDance/Seedance-2.5", displayName: "Seedance 2.5",
               capabilities: [.videoGeneration],
               contextWindow: 32_768,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
    ]

    // MARK: xAI

    // Verified against docs.x.ai/developers/models + pricing + reasoning
    // (2026-08-12): Chat/Code contexts are 500k (4.6 / 4.5), 1M (4.3 / 4.20 /
    // multi-agent), 256k (build). Multi-agent: built-in tools only (no client
    // function tools), effort = agent count. grok-4.6 reasoning is always-on
    // low/medium/high/xhigh (default high); grok-4.5 is the same band minus
    // xhigh. code_interpreter is documented in tools overview examples for
    // both. presence/frequency/stop rejected on reasoning. Imagine: pro is an
    // alias of quality; video-1.5 is image→video only (1080p supported).
    // Retired 4.1/* slugs still resolve (redirect to 4.3) but are catalog-only,
    // not seeded.
    static let xAIRecords: [Record] = [
        // Seeded
        Record(id: "grok-4.6", displayName: "Grok 4.6",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 500_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "grok-4.5", displayName: "Grok 4.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 500_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "grok-4.3", displayName: "Grok 4.3",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 1_000_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: ReasoningEffort.none),
               isFullySupported: true, isSeeded: true),
        Record(id: "grok-4.20", displayName: "Grok 4.20",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 1_000_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "grok-4.20-0309-non-reasoning", displayName: "Grok 4.20 (Non-Reasoning)",
               capabilities: [.streaming, .toolCalling, .vision, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 1_000_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "grok-4.20-multi-agent", displayName: "Grok 4.20 Multi-Agent",
               capabilities: [.streaming, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 1_000_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .low),
               isFullySupported: true, isSeeded: true),
        // Reasoning is always-on and non-configurable for Build (no effort control).
        Record(id: "grok-build-0.1", displayName: "Grok Build 0.1",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 256_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "grok-imagine-image", displayName: "Grok Imagine Image",
               capabilities: [.imageGeneration],
               contextWindow: 32_768,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "grok-imagine-image-quality", displayName: "Grok Imagine Image Quality",
               capabilities: [.imageGeneration],
               contextWindow: 32_768,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "grok-imagine-video", displayName: "Grok Imagine Video",
               capabilities: [.videoGeneration],
               contextWindow: 32_768,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "grok-imagine-video-1.5", displayName: "Grok Imagine Video 1.5",
               capabilities: [.videoGeneration],
               contextWindow: 32_768,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        // Catalog-only (aliases / snapshots / retired discovery IDs)
        Record(id: "grok-4.20-multi-agent-0309", displayName: "Grok 4.20 Multi-Agent 0309",
               capabilities: [.streaming, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 1_000_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .low),
               isFullySupported: true, isSeeded: false),
        Record(id: "grok-4.20-0309-reasoning", displayName: "Grok 4.20 0309 (Reasoning)",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution],
               contextWindow: 1_000_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "grok-imagine-image-pro", displayName: "Grok Imagine Image Pro",
               capabilities: [.imageGeneration],
               contextWindow: 32_768,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "grok-2-image-1212", displayName: "Grok 2 Image",
               capabilities: [.imageGeneration],
               contextWindow: 131_072,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "grok-imagine-video-1.5-preview", displayName: "Grok Imagine Video 1.5 (Preview)",
               capabilities: [.videoGeneration],
               contextWindow: 32_768,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "grok-imagine-video-1.5-2026-05-30", displayName: "Grok Imagine Video 1.5 (2026-05-30)",
               capabilities: [.videoGeneration],
               contextWindow: 32_768,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        // Retired 2026-05-15 (still resolve via redirect to grok-4.3 / quality / build).
        Record(id: "grok-4-1-fast", displayName: "Grok 4.1 Fast",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 1_000_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "grok-4-1", displayName: "Grok 4.1",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 1_000_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "grok-4-1-fast-non-reasoning", displayName: "Grok 4.1 Fast (Non-Reasoning)",
               capabilities: [.streaming, .toolCalling, .vision, .promptCaching, .nativePDF],
               contextWindow: 1_000_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "grok-4-1-fast-reasoning", displayName: "Grok 4.1 Fast (Reasoning)",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
               contextWindow: 1_000_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
    ]

    // MARK: DeepSeek

    // Official Models & Pricing (2026-07): primary IDs are deepseek-v4-flash / deepseek-v4-pro.
    // deepseek-chat / deepseek-reasoner are aliases of V4 Flash non/thinking modes and are
    // deprecated 2026-07-24 15:59 UTC — keep catalog-only for persisted chats.
    static let deepSeekRecords: [Record] = [
        Record(id: "deepseek-v4-flash", displayName: "DeepSeek V4 Flash",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 1_000_000,
               maxOutputTokens: 384_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "deepseek-v4-pro", displayName: "DeepSeek V4 Pro",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 1_000_000,
               maxOutputTokens: 384_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        // Legacy aliases (deprecated 2026-07-24)
        Record(id: "deepseek-chat", displayName: "DeepSeek Chat (Legacy)",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 1_000_000,
               maxOutputTokens: 384_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "deepseek-reasoner", displayName: "DeepSeek Reasoner (Legacy)",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 1_000_000,
               maxOutputTokens: 384_000,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
        Record(id: "deepseek-v3.2-exp", displayName: "DeepSeek V3.2 Exp",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
    ]

    // MARK: Zhipu Coding Plan

    static let zhipuCodingPlanRecords: [Record] = [
        // Z.ai exposes GLM-5.2 via a two-ID scheme: plain `glm-5.2` runs the standard
        // 200K window, and `glm-5.2[1m]` opts into the full 1,000,000-token context.
        // Both take `reasoning_effort` (high/max). https://docs.z.ai/devpack/latest-model
        Record(id: "glm-5.2[1m]", displayName: "GLM-5.2 (1M)",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 1_000_000,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "glm-5.2", displayName: "GLM-5.2",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 200_000,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "glm-5", displayName: "GLM-5",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: "glm-4.7", displayName: "GLM-4.7",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
    ]

    // MARK: MiniMax

    static let minimaxRecords: [Record] = [
        Record(id: "MiniMax-M3", displayName: "MiniMax M3",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 1_048_576,
               maxOutputTokens: 512_000,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: "MiniMax-M2.7", displayName: "MiniMax M2.7",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 204_800,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: "MiniMax-M2.5", displayName: "MiniMax M2.5",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 204_800,
               maxOutputTokens: 204_800,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: "MiniMax-M2.7-highspeed", displayName: "MiniMax M2.7 Highspeed",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 204_800,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
        Record(id: "MiniMax-M2.5-highspeed", displayName: "MiniMax M2.5 Highspeed",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 204_800,
               maxOutputTokens: 204_800,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
        Record(id: "MiniMax-M2.1", displayName: "MiniMax M2.1",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 204_800,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
        Record(id: "MiniMax-M2.1-highspeed", displayName: "MiniMax M2.1 Highspeed",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 204_800,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
        Record(id: "MiniMax-M2", displayName: "MiniMax M2",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 204_800,
               maxOutputTokens: 204_800,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
    ]

    // MARK: MiniMax Coding Plan

    // The Token Plan uses MiniMax's unified OpenAI-compatible /v1 endpoint, where reasoning
    // is an enum toggle (thinking.type = disabled|adaptive), not an Anthropic thinking budget.
    static let minimaxCodingPlanRecords: [Record] = [
        Record(id: "MiniMax-M3", displayName: "MiniMax M3",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 1_048_576,
               maxOutputTokens: 512_000,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: "MiniMax-M2.7", displayName: "MiniMax M2.7",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 204_800,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: "MiniMax-M2.5", displayName: "MiniMax M2.5",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 204_800,
               maxOutputTokens: 204_800,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: "MiniMax-M2.7-highspeed", displayName: "MiniMax M2.7 Highspeed",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 204_800,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
        Record(id: "MiniMax-M2.5-highspeed", displayName: "MiniMax M2.5 Highspeed",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 204_800,
               maxOutputTokens: 204_800,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
        Record(id: "MiniMax-M2.1", displayName: "MiniMax M2.1",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 204_800,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
        Record(id: "MiniMax-M2.1-highspeed", displayName: "MiniMax M2.1 Highspeed",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 204_800,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
        Record(id: "MiniMax-M2", displayName: "MiniMax M2",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 204_800,
               maxOutputTokens: 204_800,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
    ]

    // MARK: Fireworks

    static let fireworksRecords: [Record] = [
        // Seeded
        // Kimi K3 (Fireworks serverless; verified against fireworks.ai/models/fireworks/kimi-k3
        // and models.dev `fireworks-ai`, 2026-07-29): 1,048,576 context / 131,072 output,
        // text+image. Reasoning: toggle + effort low/medium/high/max via top-level
        // `reasoning_effort`. Seed the accounts/ path (canonical serverless ID) plus the
        // short fireworks/ alias used elsewhere in this catalog.
        Record(id: "accounts/fireworks/models/kimi-k3", displayName: "Kimi K3",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .max),
               isFullySupported: true, isSeeded: true),
        Record(id: "fireworks/kimi-k3", displayName: "Kimi K3",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .max),
               isFullySupported: true, isSeeded: false),
        Record(id: "accounts/fireworks/routers/kimi-k3-fast", displayName: "Kimi K3 Fast",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .max),
               isFullySupported: true, isSeeded: false),
        Record(id: "fireworks/kimi-k2p6", displayName: "Kimi K2.6",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_100,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "fireworks/qwen3p6-plus", displayName: "Qwen3.6 Plus",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: true),
        Record(id: "accounts/fireworks/models/deepseek-v4-pro", displayName: "DeepSeek V4 Pro",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 1_048_600,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "fireworks/deepseek-v3p2", displayName: "DeepSeek V3.2",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 163_800,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "fireworks/kimi-k2-instruct-0905", displayName: "Kimi K2 Instruct 0905",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 262_100,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
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
        Record(id: "fireworks/minimax-m2p7", displayName: "MiniMax M2.7",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 196_608,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "fireworks/glm-5p2", displayName: "GLM-5.2",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 1_040_384,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "fireworks/glm-5p1", displayName: "GLM-5.1",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 202_752,
               maxOutputTokens: 65_536,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        // Catalog-only
        Record(id: "fireworks/kimi-k2p5", displayName: "Kimi K2.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_100,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "fireworks/qwen3-235b-a22b", displayName: "Qwen3 235B A22B",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 131_100,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "fireworks/glm-4p7", displayName: "GLM-4.7",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 202_800,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "deepseek-ai/deepseek-v4-pro", displayName: "DeepSeek V4 Pro",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 1_048_600,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
        Record(id: "fireworks/kimi-k2-thinking", displayName: "Kimi K2 Thinking",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 262_100,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "accounts/fireworks/models/kimi-k2-thinking", displayName: "Kimi K2 Thinking",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 262_100,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        // Alternate "accounts/fireworks/models/" IDs (same capabilities, not seeded separately)
        Record(id: "accounts/fireworks/models/qwen3p6-plus", displayName: "Qwen3.6 Plus",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "accounts/fireworks/models/deepseek-v3p2", displayName: "DeepSeek V3.2",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 163_800,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "accounts/fireworks/models/kimi-k2-instruct-0905", displayName: "Kimi K2 Instruct 0905",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 262_100,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
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
        Record(id: "accounts/fireworks/models/kimi-k2p6", displayName: "Kimi K2.6",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_100,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "accounts/fireworks/models/kimi-k2p5", displayName: "Kimi K2.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_100,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "accounts/fireworks/models/qwen3-235b-a22b", displayName: "Qwen3 235B A22B",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 131_100,
               reasoningConfig: nil,
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
        // Long-form alternate IDs for newly-added flagship serverless models
        Record(id: "accounts/fireworks/models/minimax-m2p7", displayName: "MiniMax M2.7",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 196_608,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "accounts/fireworks/models/glm-5p2", displayName: "GLM-5.2",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 1_040_384,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
        Record(id: "accounts/fireworks/models/glm-5p1", displayName: "GLM-5.1",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 202_752,
               maxOutputTokens: 65_536,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        // New serverless additions (Llama 3.3, Qwen3 8B)
        Record(id: "fireworks/llama-v3p3-70b-instruct", displayName: "Llama 3.3 70B Instruct",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 131_072,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "accounts/fireworks/models/llama-v3p3-70b-instruct", displayName: "Llama 3.3 70B Instruct",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 131_072,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "fireworks/qwen3-8b", displayName: "Qwen3 8B",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 40_960,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "accounts/fireworks/models/qwen3-8b", displayName: "Qwen3 8B",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 40_960,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
    ]

    // MARK: Groq

    static let groqRecords: [Record] = [
        // Seeded — appear in the model picker on first launch
        Record(id: "llama-3.3-70b-versatile", displayName: "Llama 3.3 70B Versatile",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 131_072,
               maxOutputTokens: 32_768,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "llama-3.1-8b-instant", displayName: "Llama 3.1 8B Instant",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 131_072,
               maxOutputTokens: 131_072,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "openai/gpt-oss-120b", displayName: "GPT-OSS 120B",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 131_072,
               maxOutputTokens: 65_536,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "openai/gpt-oss-20b", displayName: "GPT-OSS 20B",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 131_072,
               maxOutputTokens: 65_536,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "groq/compound", displayName: "Groq Compound",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 131_072,
               maxOutputTokens: 8_192,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        // Catalog-only
        Record(id: "groq/compound-mini", displayName: "Groq Compound Mini",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 131_072,
               maxOutputTokens: 8_192,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
    ]

    // MARK: Cerebras

    static let cerebrasRecords: [Record] = [
        // Retires from Cerebras 2026-05-27 — keep record for in-flight chats but drop "fully supported" badge.
        Record(id: "qwen-3-235b-a22b-instruct-2507", displayName: "Qwen 3 235B A22B Instruct 2507 (Deprecated)",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 65_000,
               maxOutputTokens: 32_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "zai-glm-4.7", displayName: "ZAI GLM-4.7",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 64_000,
               maxOutputTokens: 40_000,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
        Record(id: "gpt-oss-120b", displayName: "GPT-OSS 120B",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: false, isSeeded: false),
    ]

    // MARK: SambaNova

    static let sambaNovaRecords: [Record] = [
        // Seeded — appear in the model picker on first launch
        Record(id: "MiniMax-M2.5", displayName: "MiniMax M2.5",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 160_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        // Kept unseeded/unsupported by default due unstable behavior in real-world usage.
        Record(id: "DeepSeek-V3.2", displayName: "DeepSeek V3.2",
               capabilities: [.streaming],
               contextWindow: 8_192,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "gpt-oss-120b", displayName: "GPT-OSS 120B",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        // Catalog-only — recognized when fetched via the API
        Record(id: "DeepSeek-R1-0528", displayName: "DeepSeek R1 0528",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
        Record(id: "DeepSeek-R1-Distill-Llama-70B", displayName: "DeepSeek R1 Distill Llama 70B",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: false, isSeeded: false),
        Record(id: "DeepSeek-V3-0324", displayName: "DeepSeek V3 0324",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "DeepSeek-V3.1", displayName: "DeepSeek V3.1",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
        Record(id: "DeepSeek-V3.1-Terminus", displayName: "DeepSeek V3.1 Terminus",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "Meta-Llama-3.3-70B-Instruct", displayName: "Llama 3.3 70B",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "Meta-Llama-3.1-8B-Instruct", displayName: "Llama 3.1 8B",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 16_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "Llama-4-Maverick-17B-128E-Instruct", displayName: "Llama 4 Maverick 17B",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "Qwen3-235B-A22B-Instruct-2507", displayName: "Qwen3 235B",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 64_000,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
        Record(id: "Qwen3-32B", displayName: "Qwen3 32B",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 32_000,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: false),
    ]

    // MARK: MorphLLM

    // MARK: Xiaomi MiMo Token Plan

    static let mimoTokenPlanOpenAIRecords: [Record] = [
        Record(id: MiMoModelIDs.v25Pro, displayName: "MiMo V2.5 Pro",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: MiMoModelIDs.v25, displayName: "MiMo V2.5",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .videoInput, .reasoning],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: MiMoModelIDs.v2Pro, displayName: "MiMo V2 Pro",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: MiMoModelIDs.v2Omni, displayName: "MiMo V2 Omni",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .videoInput, .reasoning],
               contextWindow: 262_144,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: MiMoModelIDs.v2Flash, displayName: "MiMo V2 Flash",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 262_144,
               maxOutputTokens: 65_536,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
    ]

    static let mimoTokenPlanAnthropicRecords: [Record] = [
        Record(id: MiMoModelIDs.v25Pro, displayName: "MiMo V2.5 Pro",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: MiMoModelIDs.v25, displayName: "MiMo V2.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: MiMoModelIDs.v2Pro, displayName: "MiMo V2 Pro",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: MiMoModelIDs.v2Omni, displayName: "MiMo V2 Omni",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_144,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: MiMoModelIDs.v2Flash, displayName: "MiMo V2 Flash",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 262_144,
               maxOutputTokens: 65_536,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
    ]

    // MARK: Kimi for Coding

    // Model IDs verified against the official Kimi Code docs (kimi.com/code/docs):
    // exactly three IDs exist — the 1M context is an entitlement of `k3`
    // (Allegretto+), not a separate model ID, so no `k3[1m]` record is seeded.
    // `k3` context stays at the Moderato-tier 262,144 (docs: "up to 1M" only on
    // higher tiers). Thinking is always on for the whole lineup: K2.7 Code
    // requests without thinking are silently routed to K2.6, and K3 supports
    // only effort "max" — which the endpoint applies when `thinking` is omitted
    // (docs: null/undefined → max) — so `k3` keeps reasoningConfig nil and Jin
    // sends no thinking shape for it (same pattern as the `kimi-k2.7-code`
    // OpenCode Go record). The K2.7 IDs keep a toggle that the resolver locks
    // on (reasoningCanDisable = false). K2.7 Code vision + 262,144 max output
    // match the repo's existing `kimi-k2.7-code` record (models.dev); K3 vision
    // and max output are undocumented, so they stay conservative.
    static let kimiForCodingRecords: [Record] = [
        Record(id: "k3", displayName: "Kimi K3",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "kimi-for-coding", displayName: "Kimi K2.7 Code",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_144,
               maxOutputTokens: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: "kimi-for-coding-highspeed", displayName: "Kimi K2.7 Code HighSpeed",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_144,
               maxOutputTokens: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
    ]

    // MARK: OpenCode Go

    static let opencodeGoRecords: [Record] = [
        // GLM-5.2 leads OpenCode Go's GLM line (verified on models.dev `opencode-go` and
        // opencode.ai/docs/go): 1M context, 131K output, reasoning via OpenAI-style
        // reasoning_effort on the OpenAI-compatible /chat/completions endpoint. Seeded
        // first so it is OpenCode Go's first-launch default (preferredModelID = models.first).
        Record(id: "glm-5.2", displayName: "GLM-5.2",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 1_000_000,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        // Grok 4.5 joined OpenCode Go's line-up alongside GPT-5.6 Luna (opencode.ai/docs/go,
        // updated 2026-08-02, lists it first in "the current list of models"). That page's
        // endpoint table routes grok-4.5 to /zen/go/v1/chat/completions via
        // @ai-sdk/openai-compatible, and a live unauthenticated probe of /zen/go/v1/messages
        // confirms the gateway rejects it there ("Model grok-4.5 is not supported for format
        // anthropic"), so it must stay out of `anthropicMessagesModelIDs`. 500K context is the
        // real upstream Grok 4.5 number (down from 4.3's 1M), matching Jin's native xAI record.
        // xAI publishes no separate max-output cap — models.dev's `output: 500000` merely
        // echoes the context window — so none is recorded here, exactly as the native xAI,
        // OpenRouter and Vercel grok-4.5 records do; recording it would make
        // GenerationControlsResolver send a default max_tokens equal to the whole window.
        // Reasoning is always-on with the low/medium/high band (docs.x.ai) and default high,
        // which is precisely what the shared `mapReasoningEffortNoneDisabled` already emits,
        // so no mapper arm is needed. .nativePDF/.codeExecution are deliberately not claimed:
        // the Go entry lists no PDF modality, this adapter's OpenAI-compatible translation
        // renders .file parts as text, and `supportsCodeExecution` is false for .opencodeGo.
        Record(id: "grok-4.5", displayName: "Grok 4.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 500_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        // GPT-5.6 Luna is the first OpenCode Go model served on the OpenAI **Responses** API:
        // opencode.ai/docs/go's endpoint table maps it to /zen/go/v1/responses via
        // @ai-sdk/openai, while every other OpenAI-shaped Go model uses /chat/completions.
        // Adding the ID here is NOT sufficient — routing lives in
        // OpenCodeGoAdapter.openAIResponsesModelIDs, which forwards to an OpenAIAdapter
        // delegate pinned to the Go base URL. 1,050,000 context / 128,000 output are OpenAI's
        // published Luna limits (models.dev `opencode-go` agrees); the 272K figure on the Go
        // pricing page is a billing-tier boundary, not a context cap. The effort band is
        // low/medium/high/xhigh/max with a medium default — `xhigh` and `max` come from the
        // provider-agnostic openAIStyle*EffortModelIDs sets, which already list this ID, and
        // the Responses mapper emits both verbatim. temperature/top_p are never sent
        // (models.dev marks the model temperature:false, and the Responses sampling gate
        // already excludes reasoning-enabled gpt-5* models).
        // .nativePDF is deliberately not claimed even though models.dev lists PDF input:
        // .opencodeGo sits in ChatAttachmentCapabilitySupport's native-PDF deny arm, and
        // whether the Go gateway forwards `input_file` (or hosts /files) is unverified — a
        // failed hosted upload rethrows and kills the send, so PDFs go through Jin's
        // text-extraction path instead. .codeExecution and .webSearch are not claimed either:
        // the gateway hosts neither tool.
        Record(id: "gpt-5.6-luna", displayName: "GPT-5.6 Luna",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 1_050_000,
               maxOutputTokens: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "glm-5", displayName: "GLM-5",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 202_752,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        // Kimi K3 (live on the Go /models list since 2026-07-16; verified against
        // models.dev `opencode-go` and Moonshot's K3 docs): 1,048,576 context /
        // 131,072 output, text+image input. Thinking is always-on and
        // reasoning_effort accepts only "max" (models.dev reasoning_options;
        // Moonshot docs) — the endpoint applies max when the field is omitted, so
        // reasoningConfig stays nil and Jin sends no reasoning shape (same pattern
        // as the `k3` Kimi for Coding record). models.dev also lists video input,
        // but this model routes through the OpenAI-compatible endpoint whose message
        // translation has no video part builder, so .videoInput is deliberately not
        // claimed — same rationale as kimi-k2.7-code below.
        Record(id: "kimi-k3", displayName: "Kimi K3",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "kimi-k2.5", displayName: "Kimi K2.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "kimi-k2.6", displayName: "Kimi K2.6",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        // Kimi K2.7 Code (live on the Go /models list since 2026-06-12; verified against
        // models.dev `opencode-go`): 262,144 context AND output, reasoning always-on with
        // NO effort control (empty reasoning_options — the gateway ignores reasoning_effort
        // for it), thinking interleaved via `reasoning_content`. reasoningConfig stays nil
        // so Jin never sends an effort it can't honor. models.dev also lists video input,
        // but this model routes through the OpenAI-compatible endpoint whose message
        // translation has no video part builder, so .videoInput is deliberately not claimed.
        Record(id: "kimi-k2.7-code", displayName: "Kimi K2.7 Code",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_144,
               maxOutputTokens: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "mimo-v2.5-pro", displayName: "MiMo V2.5 Pro",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "mimo-v2.5", displayName: "MiMo V2.5",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "deepseek-v4-pro", displayName: "DeepSeek V4 Pro",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 1_000_000,
               maxOutputTokens: 384_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "deepseek-v4-flash", displayName: "DeepSeek V4 Flash",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 1_000_000,
               maxOutputTokens: 384_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "minimax-m3", displayName: "MiniMax M3",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 1_048_576,
               maxOutputTokens: 512_000,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 10_000),
               isFullySupported: true, isSeeded: true),
        Record(id: "minimax-m2.7", displayName: "MiniMax M2.7",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 204_800,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 10_000),
               isFullySupported: true, isSeeded: true),
        Record(id: "minimax-m2.5", displayName: "MiniMax M2.5",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 204_800,
               maxOutputTokens: 204_800,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 10_000),
               isFullySupported: true, isSeeded: true),
        Record(id: "glm-5.1", displayName: "GLM-5.1",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 202_752,
               maxOutputTokens: 65_536,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        // Qwen + MiniMax are served via OpenCode Go's Anthropic /messages endpoint, where
        // reasoning is an Anthropic thinking budget (matches the minimax-* rows below).
        // Qwen3.8 Max is Alibaba's new flagship (announced 2026-08-03: 2.4T-parameter sparse
        // MoE, 95B active, natively multimodal) and joined the Go /models list the same day.
        // opencode.ai/docs/go's endpoint table routes it to /zen/go/v1/messages via
        // @ai-sdk/anthropic, and a live unauthenticated probe agrees — /messages accepts the
        // model (it answers AuthError) while /responses rejects it outright ("Model
        // qwen3.8-max is not supported for format openai") — so the ID must also be listed in
        // OpenCodeGoAdapter.anthropicMessagesModelIDs; adding it here alone routes every send
        // to the wrong endpoint. 1,000,000 context / 131,072 output per models.dev
        // `opencode-go`, Alibaba Cloud's launch note ("context window of up to 1 million
        // tokens") and Qwen Cloud's model page. The output cap is the Max line's first move
        // off 65,536, so it is deliberately NOT mirrored from qwen3.7-max above.
        // Reasoning is the Anthropic thinking budget shape (models.dev reasoning_options =
        // toggle + budget_tokens up to 262,144), and it is genuinely toggleable — hence no
        // entry in ModelSettingsResolver.opencodeGoAlwaysOnReasoningModelIDs.
        // .videoInput is deliberately not claimed even though models.dev lists video input:
        // this ID routes through /messages, whose translation replaces a .video part with an
        // `unsupportedVideoInputNotice` text block — the exact trap the qwen3.7-plus and
        // qwen3.5-plus records document. .promptCaching is not claimed either, matching every
        // other /messages-routed Qwen/MiniMax row (.opencodeGo supports neither explicit cache
        // mode nor TTL in ChatAuxiliaryControlSupport). Seeded, but placed after glm-5.2 so
        // OpenCode Go's first-launch default (preferredModelID = models.first) is unchanged.
        Record(id: "qwen3.8-max", displayName: "Qwen3.8 Max",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 1_000_000,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 10_000),
               isFullySupported: true, isSeeded: true),
        Record(id: "qwen3.7-max", displayName: "Qwen3.7 Max",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 1_000_000,
               maxOutputTokens: 65_536,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 10_000),
               isFullySupported: true, isSeeded: true),
        // Qwen3.7 Plus (live on the Go /models list since 2026-06-02; verified against
        // models.dev `opencode-go`): 1M context / 65,536 output, served via the Anthropic
        // /messages endpoint (@ai-sdk/anthropic) with a thinking budget like the other
        // qwen3.7 models — it must also be routed in
        // OpenCodeGoAdapter.anthropicMessagesModelIDs. models.dev also lists video input,
        // but the Anthropic /messages translation has no video part builder (it replaces
        // .video parts with a placeholder notice), so .videoInput is deliberately not
        // claimed — same rationale as kimi-k2.7-code above.
        Record(id: "qwen3.7-plus", displayName: "Qwen3.7 Plus",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 1_000_000,
               maxOutputTokens: 65_536,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 10_000),
               isFullySupported: true, isSeeded: true),
        Record(id: "qwen3.6-plus", displayName: "Qwen3.6 Plus",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 262_144,
               maxOutputTokens: 65_536,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        // Hy3 (Tencent's Hunyuan 3 reasoning model) is on opencode.ai/docs/go's current model
        // list, pricing table and privacy table (page updated 2026-08-02), and its endpoint
        // table routes hy3 to /zen/go/v1/chat/completions via @ai-sdk/openai-compatible — so
        // it must NOT join `anthropicMessagesModelIDs`. 256K context / 64K output per
        // models.dev `opencode-go` (OpenRouter's tencent/hy3 reports 262,144/128,000 for a
        // different gateway — deliberately not imported here). Input is text-only
        // (modalities.input = [text], attachment false), so no .vision/.nativePDF/.videoInput.
        // reasoning_effort accepts only low/high — "medium" is NOT a valid value for this
        // family, hence `opencodeGoHy3ReasoningEffortModelIDs` in ModelCapabilityRegistry and
        // the matching mapper arm; "none" is expressed by disabling reasoning, which omits the
        // field entirely (the gateway then applies its own default), the same convention Jin
        // already uses for `tencent/hy3` on OpenRouter.
        Record(id: "hy3", displayName: "Hy3",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 256_000,
               maxOutputTokens: 64_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        // Catalog-only — recognized when fetched via the API
        // .videoInput dropped: qwen3.5-plus is in `anthropicMessagesModelIDs`, and the
        // Anthropic /messages translation replaces a .video part with an
        // `unsupportedVideoInputNotice` text block rather than encoding it — so claiming it
        // only made the attachment picker accept videos that were silently swapped for a
        // sentence. Same policy the qwen3.7-plus record above already documents; this record
        // predates it.
        Record(id: "qwen3.5-plus", displayName: "Qwen3.5 Plus",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 1_000_000,
               maxOutputTokens: 65_536,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        // MiMo V2 (pro/omni) are still served but deprecated on OpenCode Go (superseded by
        // the seeded V2.5 variants), so they are recognized-when-fetched rather than seeded.
        Record(id: "mimo-v2-pro", displayName: "MiMo V2 Pro",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 1_048_576,
               maxOutputTokens: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "mimo-v2-omni", displayName: "MiMo V2 Omni",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning],
               contextWindow: 262_144,
               maxOutputTokens: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        // Still served on the Go /models list but absent from the docs' current-model list —
        // superseded by the seeded `hy3` above, so recognized-when-fetched rather than seeded.
        // Shares Hy3's low/high-only effort band (see `opencodeGoHy3ReasoningEffortModelIDs`),
        // so its default moves off the invalid `medium` it used to carry.
        Record(id: "hy3-preview", displayName: "Hy3 Preview",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 256_000,
               maxOutputTokens: 64_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
        Record(id: "big-pickle", displayName: "Big Pickle",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: false, isSeeded: false),
        Record(id: "deepseek-v4-flash-free", displayName: "DeepSeek V4 Flash (Free)",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 256_000,
               maxOutputTokens: 256_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
        Record(id: "minimax-m2.5-free", displayName: "MiniMax M2.5 (Free)",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 204_800,
               maxOutputTokens: 204_800,
               reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 10_000),
               isFullySupported: true, isSeeded: false),
        Record(id: "ring-2.6-1t-free", displayName: "Ring 2.6 1T (Free)",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 262_144,
               maxOutputTokens: 65_536,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "trinity-large-preview-free", displayName: "Trinity Large Thinking (Free)",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 262_144,
               maxOutputTokens: 80_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
        Record(id: "nemotron-3-super-free", displayName: "Nemotron 3 Super (Free)",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 262_144,
               maxOutputTokens: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: false),
    ]

    // MARK: Meta

    // Muse Spark family (Meta Model API, verified against dev.meta.ai/docs/models
    // 2026-08-06): three IDs share modalities and a 1,048,576-token context window.
    // Max output 131,072 per Meta overview / LiteLLM (not models.dev's stale 32k).
    // Jin targets the Responses API for Meta: text/image/video/PDF input, tool calling,
    // web_search grounding, and always-on reasoning (minimal..xhigh; "none" is rejected —
    // omit the field instead). Contributor tier is the same 1.2 checkpoint at a discount
    // in exchange for training-data consent.
    static let metaRecords: [Record] = [
        Record(id: "muse-spark-1.2", displayName: "Muse Spark 1.2",
               capabilities: [.streaming, .toolCalling, .vision, .videoInput, .nativePDF, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "muse-spark-1.1", displayName: "Muse Spark 1.1",
               capabilities: [.streaming, .toolCalling, .vision, .videoInput, .nativePDF, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "muse-spark-1.2-contributor", displayName: "Muse Spark 1.2 Contributor",
               capabilities: [.streaming, .toolCalling, .vision, .videoInput, .nativePDF, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               maxOutputTokens: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
    ]

    // MARK: MorphLLM

    static let morphLLMRecords: [Record] = [
        // Seeded — appear in the model picker on first launch
        Record(id: "auto", displayName: "Morph Auto",
               capabilities: [.streaming],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "morph-v3-large", displayName: "Morph v3 Large",
               capabilities: [.streaming],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "morph-v3-fast", displayName: "Morph v3 Fast",
               capabilities: [.streaming],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
    ]

    // MARK: Baseten Model APIs

    // Official Model APIs catalog (docs.baseten.co/inference/model-apis/overview +
    // reasoning/vision pages, verified 2026-07-29). Context/output limits are Baseten's
    // live serving caps (not always the model-native maximum). Automatic KV-cache
    // discount → promptCaching on all seeded models. Reasoning wire shapes differ by
    // family — see BasetenRequestSupport.
    static let basetenRecords: [Record] = [
        // Seeded — Kimi K3 first so it is the default preferred model.
        Record(id: "moonshotai/Kimi-K3", displayName: "Kimi K3",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               maxOutputTokens: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .max),
               isFullySupported: true, isSeeded: true),
        Record(id: "moonshotai/Kimi-K2.7-Code", displayName: "Kimi K2.7 Code",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 262_144,
               maxOutputTokens: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: "moonshotai/Kimi-K2.6", displayName: "Kimi K2.6",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 262_144,
               maxOutputTokens: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: "thinkingmachines/inkling", displayName: "Inkling",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               maxOutputTokens: 32_768,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "thinkingmachines/inkling-small", displayName: "Inkling Small",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               maxOutputTokens: 32_768,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "deepseek-ai/DeepSeek-V4-Pro", displayName: "DeepSeek V4 Pro",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 262_144,
               maxOutputTokens: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "deepseek-ai/DeepSeek-V4-Pro-0813", displayName: "DeepSeek V4 Pro 0813",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               maxOutputTokens: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "deepseek-ai/DeepSeek-V4-Flash-0731", displayName: "DeepSeek V4 Flash",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               maxOutputTokens: 384_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "zai-org/GLM-5.2", displayName: "GLM 5.2",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               maxOutputTokens: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "zai-org/GLM-5.2-Fast", displayName: "GLM 5.2 Fast",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               maxOutputTokens: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        Record(id: "zai-org/GLM-4.7", displayName: "GLM 4.7",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 200_000,
               maxOutputTokens: 200_000,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: "nvidia/NVIDIA-Nemotron-3-Ultra-550B-A55B", displayName: "Nemotron Ultra",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 202_000,
               maxOutputTokens: 202_000,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: "openai/gpt-oss-120b", displayName: "OpenAI GPT 120B",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 128_000,
               maxOutputTokens: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),

        // Additional Model API IDs returned by live GET /v1/models (verified against
        // the Baseten account model list + models.dev / OpenRouter metadata, 2026-07-29).
        // Not on the published 10-model overview table, so they are catalog-enriched
        // rather than first-launch seeds — full support when the user adds them.
        //
        // Mercury 2 (Inception dLLM): 128k context / 50k output, text-only, tool calling,
        // tunable reasoning via reasoning_effort low/medium/high (OpenRouter also lists
        // "none"). Cached-input pricing on OpenRouter → promptCaching.
        Record(id: "inception/mercury-2", displayName: "Mercury 2",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 128_000,
               maxOutputTokens: 50_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
        // SID-1 (SID AI agentic retrieval): specialized search/retrieval model exposed
        // on Baseten Model APIs as `sid/sid-1`. Baseten has not published a dedicated
        // context/effort matrix for this slug — keep text + tools only, conservative
        // 128k window, no reasoning/vision claims until docs confirm them.
        Record(id: "sid/sid-1", displayName: "SID-1",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
    ]

    // MARK: Modal Shared API

    // These IDs are recognized when Fetch / Add Endpoint actually returns them.
    // They are NOT first-launch seeds: a proxy token only reaches the endpoints
    // that workspace deployed (or Shared Endpoints the token is allowed to hit).
    // modal.com/docs/guide/endpoints — one token, many endpoint URLs.
    static let modalRecords: [Record] = [
        // Kimi K3: 2.8T MoE with native vision and a 1M window (config.json
        // max_length 1048576). Reasoning is effort-controlled, not a true toggle.
        Record(id: "moonshotai/Kimi-K3", displayName: "Kimi K3",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               maxOutputTokens: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .max),
               isFullySupported: true, isSeeded: false),
        // Qwen3.8-2.4T-A95B (Modal Shared Endpoint, announced 2026-08-12): the
        // open-weight Max-class text model, NOT Alibaba Cloud's multimodal
        // `qwen3.8-max`. Exact HF repo ID is what Modal's library page and
        // `/endpoints?model=Qwen/Qwen3.8-2.4T-A95B` publish. Text-only — the HF
        // card and Modal copy both say multimodal input is unsupported (cloud
        // Qwen3.8-Max adds vision / non-thinking / built-in tools on top of
        // these weights). Thinking cannot be disabled; `reasoning_effort` is
        // only low / medium / xhigh (xhigh default). Context is Modal's 1M
        // Shared Endpoint window (HF native 262,144, extensible to 1,010,000;
        // OpenRouter lists 1,000,000 for the same weights). maxOutputTokens is
        // the HF "Reasoning Content" generation ceiling of 262,144 — the 131,072
        // figure is the recommended *final* answer budget when a runtime splits
        // the two, which Chat Completions `max_tokens` does not.
        Record(id: "Qwen/Qwen3.8-2.4T-A95B", displayName: "Qwen3.8 Max",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 1_000_000,
               maxOutputTokens: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .xhigh),
               isFullySupported: true, isSeeded: false),
        // Thinking Machines Inkling, NVFP4 build. Note the ID differs from the
        // `thinkingmachines/inkling` slug other providers use — catalog lookup is by
        // exact ID, so this one must stay verbatim. Text + image + audio input per
        // models.dev's Modal entry; 1M context / 256k output.
        Record(id: "thinkingmachines/Inkling-NVFP4", displayName: "Inkling",
               capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching],
               contextWindow: 1_048_576,
               maxOutputTokens: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: false),
    ]
}
