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
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "anthropic/claude-sonnet-4.6"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "anthropic/claude-opus-4.5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "google/gemini-3.1-pro-preview"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "google/gemini-2.5-pro"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "gpt-5.2"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "anthropic/claude-sonnet-4-6-custom"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "xai/grok-4.1-fast-reasoning-custom"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "google/gemini-3"))
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
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "Qwen/Qwen3.5-9B"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .together, modelID: "openai/gpt-oss-120b-custom"))
    }

    func testTogetherCatalogOnlyRecentModelsUseExactIDs() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "zai-org/GLM-4.7"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "zai-org/GLM-4.5-Air-FP8"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "openai/gpt-oss-20b"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "Qwen/Qwen3-Next-80B-A3B-Instruct"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .together, modelID: "meta-llama/Llama-4-Maverick-17B-128E-Instruct-FP8"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .together, modelID: "meta-llama/Llama-4-Maverick-17B-128E-Instruct-FP8-custom"))
    }

    func testOpenRouterGoogleGeminiPreviewIsMarkedAsFullySupported() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "google/gemini-3-pro-preview"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "google/gemini-3.1-pro-preview"))
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

    func testGeminiProvider3Point1PreviewIsMarkedAsFullySupported() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .gemini, modelID: "gemini-3.1-pro-preview"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .gemini, modelID: "gemini-3.1-flash-image-preview"))
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
