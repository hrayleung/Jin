import XCTest
@testable import Jin

final class JinModelSupportTests: XCTestCase {
    func testOpenAIUsesExactMatchForFullySupportedTag() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openai, modelID: "gpt-5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openai, modelID: "gpt-5.5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openai, modelID: "gpt-5.5-pro"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openai, modelID: "gpt-5.3-codex"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openai, modelID: "gpt-5.3-chat-latest"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openai, modelID: "gpt-5.5-custom"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openai, modelID: "gpt-5.3-codex-spark"))
    }

    func testOpenAIWebSocketUsesExactMatchForFullySupportedTag() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openaiWebSocket, modelID: "gpt-5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openaiWebSocket, modelID: "gpt-5.5"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openaiWebSocket, modelID: "gpt-5.5-pro"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openaiWebSocket, modelID: "gpt-5.5-pro-2026-04-23"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openaiWebSocket, modelID: "gpt-5.3-codex"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openaiWebSocket, modelID: "gpt-5.3-chat-latest"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openaiWebSocket, modelID: "gpt-5.5-custom"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openaiWebSocket, modelID: "gpt-5.3-codex-spark"))
    }

    func testCloudflareAIGatewayUsesProviderPrefixedExactModelIDsForFullySupportedTag() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "openai/gpt-5.2"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "openai/gpt-5.3-chat-latest"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "anthropic/claude-opus-4-7"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "anthropic/claude-sonnet-4-6"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "anthropic/claude-opus-4-5-20251101"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "google-vertex-ai/google/gemini-2.5-pro"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "google-ai-studio/gemini-3.1-pro-preview"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "gpt-5.2"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "openai/gpt-5.2-custom"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "grok/grok-4-1-fast-reasoning"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "deepseek/deepseek-chat"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "google-ai-studio/gemini-3-pro-image-preview"))
    }

    func testCloudflareNativePDFSupportUsesExactCatalogAndStaysDisabled() {
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .cloudflareAIGateway, modelID: "openai/gpt-5.2"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .cloudflareAIGateway, modelID: "anthropic/claude-sonnet-4-6"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .cloudflareAIGateway, modelID: "google-vertex-ai/google/gemini-2.5-pro"))
    }

    func testVercelAIGatewayUsesProviderPrefixedExactModelIDsForFullySupportedTag() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "openai/gpt-5.2"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "anthropic/claude-opus-4.7"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "anthropic/claude-sonnet-4.6"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "anthropic/claude-opus-4.5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "google/gemini-3.1-pro-preview"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "google/gemini-2.5-pro"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "google/gemma-4-31b-it"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "google/gemma-4-26b-a4b-it"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "gpt-5.2"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "anthropic/claude-sonnet-4-6-custom"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "xai/grok-4.1-fast-reasoning-custom"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "google/gemini-3"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "google/gemma-4-31b-it-custom"))
    }

    func testAnthropicClaude47UsesExactFullySupportedID() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .anthropic, modelID: "claude-opus-4-7"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .anthropic, modelID: "claude-opus-4-7-custom"))
    }

    func testVercelAIGatewayNativePDFSupportStaysDisabledByDefault() {
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .vercelAIGateway, modelID: "openai/gpt-5.2"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .vercelAIGateway, modelID: "anthropic/claude-sonnet-4.6"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .vercelAIGateway, modelID: "google/gemini-3.1-flash-image-preview"))
    }

    func testFireworksGLM5IsMarkedAsFullySupported() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "fireworks/glm-5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "accounts/fireworks/models/glm-5"))
    }

    func testFireworksMiniMaxM2p5IsMarkedAsFullySupported() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "fireworks/minimax-m2p5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "accounts/fireworks/models/minimax-m2p5"))
    }

    func testFireworksLatestExactIDsUseExpectedSupportBadges() {
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "fireworks/qwen3p6-plus"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "accounts/fireworks/models/qwen3p6-plus"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "fireworks/kimi-k2-thinking"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "accounts/fireworks/models/kimi-k2-thinking"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "fireworks/deepseek-v3p2"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "accounts/fireworks/models/deepseek-v3p2"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "fireworks/kimi-k2-instruct-0905"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "accounts/fireworks/models/qwen3-235b-a22b"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "fireworks/qwen3p6-plus-custom"))
    }

    func testZhipuCodingPlanUsesExactMatchForFullySupportedTag() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .zhipuCodingPlan, modelID: "glm-5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .zhipuCodingPlan, modelID: "glm-4.7"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .zhipuCodingPlan, modelID: "glm-4.7-custom"))
    }

    func testTogetherSeededModelsAreMarkedAsFullySupported() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "moonshotai/Kimi-K2.5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "zai-org/GLM-5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "deepseek-ai/DeepSeek-V3.1"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "openai/gpt-oss-120b"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "Qwen/Qwen3.5-397B-A17B"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "Qwen/Qwen3-235B-A22B-Instruct-2507-tput"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "Qwen/Qwen3-Coder-Next-FP8"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .together, modelID: "openai/gpt-oss-120b-custom"))
    }

    func testTogetherCatalogOnlyRecentModelsUseExactIDs() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "zai-org/GLM-4.7"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "zai-org/GLM-4.5-Air-FP8"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "openai/gpt-oss-20b"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "Qwen/Qwen3.5-9B"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "Qwen/Qwen3-Next-80B-A3B-Instruct"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "meta-llama/Llama-4-Maverick-17B-128E-Instruct-FP8"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .together, modelID: "meta-llama/Llama-4-Maverick-17B-128E-Instruct-FP8-custom"))
    }

    func testDeepInfraUsesExactMatchForFullySupportedTag() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "zai-org/GLM-5.1"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "Qwen/Qwen3.6-35B-A3B"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "nvidia/NVIDIA-Nemotron-3-Super-120B-A12B"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "stepfun-ai/Step-3.5-Flash"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "Qwen/Qwen3-Max"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "Qwen/Qwen3-Max-Thinking"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "zai-org/GLM-5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "Qwen/Qwen3.5-397B-A17B"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "Qwen/Qwen3.5-122B-A10B"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "Qwen/Qwen3.5-35B-A3B"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "Qwen/Qwen3.5-27B"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "Qwen/Qwen3.5-9B"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "moonshotai/Kimi-K2.5"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "zai-org/GLM-5.1-custom"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "zai-org/GLM-5-custom"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "Qwen/Qwen3.5-397B-A17B-custom"))
    }

    func testSambaNovaUsesExactMatchForFullySupportedTag() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .sambanova, modelID: "MiniMax-M2.5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .sambanova, modelID: "gpt-oss-120b"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .sambanova, modelID: "DeepSeek-V3.1"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .sambanova, modelID: "Qwen3-235B-A22B-Instruct-2507"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .sambanova, modelID: "Qwen3-32B"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .sambanova, modelID: "DeepSeek-V3.2"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .sambanova, modelID: "Qwen3-235B-A22B-Instruct-2507-custom"))
    }

    func testCerebrasUsesExactMatchForFullySupportedTag() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .cerebras, modelID: "qwen-3-235b-a22b-instruct-2507"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .cerebras, modelID: "zai-glm-4.7"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .cerebras, modelID: "gpt-oss-120b"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .cerebras, modelID: "qwen-3-235b-a22b-instruct-2507-custom"))
    }

    func testOpenRouterGoogleGeminiPreviewIsMarkedAsFullySupported() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "google/gemini-3-pro-preview"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "google/gemini-3.1-pro-preview"))
    }

    func testOpenRouterGemma4ModelsUseExactFullySupportedIDs() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "google/gemma-4-31b-it"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "google/gemma-4-26b-a4b-it"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "google/gemma-4-31b-it-custom"))
    }

    func testOpenRouterLatestXiaomiAndMiniMaxModelsUseExactFullySupportedIDs() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "xiaomi/mimo-v2-omni"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "xiaomi/mimo-v2-pro"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "xiaomi/mimo-v2-flash"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "minimax/minimax-m2.7"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "minimax/minimax-m2.5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "minimax/minimax-m2.5:free"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "minimax/minimax-01"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "xiaomi/mimo-v2-pro-custom"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "minimax/minimax-m2.7-custom"))
    }

    func testOpenRouterGPT54Image2UsesExactFullySupportedID() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "openai/gpt-5.4-image-2"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "openai/gpt-5.4-image-2-custom"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .openrouter, modelID: "openai/gpt-5.4-image-2"))
    }

    func testDeepSeekV4SupportUsesOnlyVerifiedExactProviderIDs() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "deepseek/deepseek-v4-flash"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "deepseek/deepseek-v4-pro"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "deepseek/deepseek-v4-pro-custom"))

        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .together, modelID: "deepseek-ai/DeepSeek-V4-Flash"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "deepseek-ai/DeepSeek-V4-Pro"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .together, modelID: "deepseek-ai/DeepSeek-V4-Pro-custom"))

        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "deepseek-ai/DeepSeek-V4-Flash"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "deepseek-ai/DeepSeek-V4-Pro"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "deepseek-ai/DeepSeek-V4-Flash-custom"))

        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "accounts/fireworks/models/deepseek-v4-pro"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "deepseek-ai/deepseek-v4-pro"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "fireworks/deepseek-v4-pro"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "fireworks/deepseek-v4-flash"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "accounts/fireworks/models/deepseek-v4-flash"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "accounts/fireworks/models/deepseek-v4-pro-custom"))
    }

    func testOpenRouterSeedanceModelsUseExactFullySupportedIDs() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "bytedance/seedance-1-5-pro"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "bytedance/seedance-2.0"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "bytedance/seedance-2.0-fast"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "bytedance/seedance-2.0-fast-preview"))
    }

    func testVerifiedKimiK26ProvidersUseExactFullySupportedIDs() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .opencodeGo, modelID: "kimi-k2.6"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .opencodeGo, modelID: "kimi-k2.6-custom"))

        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "moonshotai/kimi-k2.6"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "moonshotai/kimi-k2.6-custom"))

        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "fireworks/kimi-k2p6"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "accounts/fireworks/models/kimi-k2p6"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "fireworks/kimi-k2p6-custom"))

        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "moonshotai/kimi-k2.6"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "moonshotai/kimi-k2.6-custom"))

        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "@cf/moonshotai/kimi-k2.6"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "@cf/moonshotai/kimi-k2.6-custom"))
    }

    func testOpenCodeGoMiMoV25ModelsUseExactFullySupportedIDs() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .opencodeGo, modelID: "mimo-v2.5-pro"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .opencodeGo, modelID: "mimo-v2.5"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .opencodeGo, modelID: "mimo-v2.5-pro-preview"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .opencodeGo, modelID: "mimo-v2.5-experimental"))
    }

    func testMiMoTokenPlanModelsUseExactFullySupportedIDs() {
        for providerType in [ProviderType.mimoTokenPlanOpenAI, .mimoTokenPlanAnthropic] {
            XCTAssertTrue(JinModelSupport.isFullySupported(providerType: providerType, modelID: "mimo-v2.5-pro"))
            XCTAssertTrue(JinModelSupport.isFullySupported(providerType: providerType, modelID: "mimo-v2.5"))
            XCTAssertTrue(JinModelSupport.isFullySupported(providerType: providerType, modelID: "mimo-v2-pro"))
            XCTAssertTrue(JinModelSupport.isFullySupported(providerType: providerType, modelID: "mimo-v2-omni"))
            XCTAssertTrue(JinModelSupport.isFullySupported(providerType: providerType, modelID: "mimo-v2-flash"))
            XCTAssertFalse(JinModelSupport.isFullySupported(providerType: providerType, modelID: "mimo-v2.5-pro-preview"))
            XCTAssertFalse(JinModelSupport.isFullySupported(providerType: providerType, modelID: "mimo-v2.5-experimental"))
        }
    }

    func testOpenCodeGoDeepSeekV4ModelsUseExactFullySupportedIDs() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .opencodeGo, modelID: "deepseek-v4-pro"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .opencodeGo, modelID: "deepseek-v4-flash"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .opencodeGo, modelID: "deepseek-v4-pro-custom"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .opencodeGo, modelID: "deepseek-v4-flash-preview"))
    }

    func testGeminiProvider3Point1PreviewIsMarkedAsFullySupported() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .gemini, modelID: "gemini-3.1-pro-preview"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .gemini, modelID: "gemini-3.1-flash-image-preview"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .gemini, modelID: "gemma-4-26b-a4b-it"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .gemini, modelID: "gemma-4-31b-it"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .gemini, modelID: "gemma-4-31b-it-custom"))
    }

    func testVertexAIProvider3Point1PreviewIsMarkedAsFullySupported() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .vertexai, modelID: "gemini-3.1-pro-preview"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .vertexai, modelID: "gemini-3.1-flash-image-preview"))
    }

    func testXAIGrok41FastVariantsUseExactMatch() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .xai, modelID: "grok-4.3"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .xai, modelID: "grok-4.20"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .xai, modelID: "grok-4.20-multi-agent"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .xai, modelID: "grok-4.20-multi-agent-0309"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .xai, modelID: "grok-4-1-fast-non-reasoning"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .xai, modelID: "grok-4-1-fast-reasoning"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .xai, modelID: "grok-imagine-image-pro"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .xai, modelID: "grok-4.3-custom"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .xai, modelID: "grok-4.20-custom"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .xai, modelID: "grok-4.2"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .xai, modelID: "grok-4.20-multi-agent-0310"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .xai, modelID: "grok-5"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .xai, modelID: "grok-imagine-image-pro-v2"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "x-ai/grok-4.3"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "x-ai/grok-4.20"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "x-ai/grok-4.20-multi-agent"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "x-ai/grok-4.20-multi-agent-0309"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "x-ai/grok-4.20-multi-agent-custom"))
    }

    func testOpenAINativePDFSupportUsesExactMatch() {
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .openai, modelID: "gpt-4o"))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .openai, modelID: "gpt-5.2"))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .openai, modelID: "gpt-5.3-codex"))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .openai, modelID: "o4"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .openai, modelID: "gpt-5.3-chat-latest"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .openai, modelID: "gpt-5"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .openai, modelID: "o4-mini"))
    }

    func testOpenAIWebSocketNativePDFSupportUsesExactMatch() {
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .openaiWebSocket, modelID: "gpt-4o"))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .openaiWebSocket, modelID: "gpt-5.2"))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .openaiWebSocket, modelID: "gpt-5.3-codex"))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .openaiWebSocket, modelID: "o4"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .openaiWebSocket, modelID: "gpt-5.3-chat-latest"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .openaiWebSocket, modelID: "gpt-5"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .openaiWebSocket, modelID: "o4-mini"))
    }

    func testXAINativePDFSupportUsesExactMatch() {
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .xai, modelID: "grok-4.3"))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .xai, modelID: "grok-4.20"))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .xai, modelID: "grok-4.20-multi-agent"))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .xai, modelID: "grok-4.20-multi-agent-0309"))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .xai, modelID: "grok-4-1-fast-reasoning"))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .openrouter, modelID: "x-ai/grok-4.20"))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .openrouter, modelID: "x-ai/grok-4.20-multi-agent"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .xai, modelID: "grok-4.3-custom"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .xai, modelID: "grok-4.2"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .xai, modelID: "grok-5"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .openrouter, modelID: "x-ai/grok-4.20-multi-agent-0309"))
    }

    func testNanoBanana2NativePDFSupportUsesExactMatch() {
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .gemini, modelID: "gemini-3.1-flash-image-preview"))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .vertexai, modelID: "gemini-3.1-flash-image-preview"))
    }

    func testDeepSeekUsesExactMatchForFullySupportedTag() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepseek, modelID: "deepseek-chat"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepseek, modelID: "deepseek-reasoner"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepseek, modelID: "deepseek-v3.2-exp"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepseek, modelID: "deepseek-v4-flash"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepseek, modelID: "deepseek-v4-pro"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .deepseek, modelID: "deepseek-v4-pro-custom"))
    }
}
