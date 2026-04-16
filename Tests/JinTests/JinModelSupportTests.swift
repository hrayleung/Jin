import XCTest
@testable import Jin

final class JinModelSupportTests: XCTestCase {
    func testOpenAIUsesExactMatchForFullySupportedTag() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openai, modelID: "gpt-5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openai, modelID: "gpt-5.3-codex"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openai, modelID: "gpt-5.3-chat-latest"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openai, modelID: "gpt-5.3-codex-spark"))
    }

    func testOpenAIWebSocketUsesExactMatchForFullySupportedTag() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openaiWebSocket, modelID: "gpt-5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openaiWebSocket, modelID: "gpt-5.3-codex"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openaiWebSocket, modelID: "gpt-5.3-chat-latest"))
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
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "zai-org/GLM-5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "Qwen/Qwen3.5-397B-A17B"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "Qwen/Qwen3.5-122B-A10B"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "Qwen/Qwen3.5-35B-A3B"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "Qwen/Qwen3.5-27B"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "Qwen/Qwen3.5-9B"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .deepinfra, modelID: "moonshotai/Kimi-K2.5"))
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

    func testOpenRouterSeedanceModelsUseExactFullySupportedIDs() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "bytedance/seedance-1-5-pro"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "bytedance/seedance-2.0"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "bytedance/seedance-2.0-fast"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "bytedance/seedance-2.0-fast-preview"))
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
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .xai, modelID: "grok-4-1-fast-non-reasoning"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .xai, modelID: "grok-4-1-fast-reasoning"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .xai, modelID: "grok-imagine-image-pro"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .xai, modelID: "grok-5"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .xai, modelID: "grok-imagine-image-pro-v2"))
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
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .xai, modelID: "grok-4-1-fast-reasoning"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .xai, modelID: "grok-5"))
    }

    func testNanoBanana2NativePDFSupportUsesExactMatch() {
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .gemini, modelID: "gemini-3.1-flash-image-preview"))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .vertexai, modelID: "gemini-3.1-flash-image-preview"))
    }
}
