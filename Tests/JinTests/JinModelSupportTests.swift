import XCTest
@testable import Jin

final class JinModelSupportTests: XCTestCase {
    func testOpenAIUsesExactMatchForFullySupportedTag() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openai, modelID: "gpt-5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openai, modelID: "gpt-5.3-codex"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openai, modelID: "gpt-5.3-codex-spark"))
    }

    func testOpenAIWebSocketUsesExactMatchForFullySupportedTag() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openaiWebSocket, modelID: "gpt-5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openaiWebSocket, modelID: "gpt-5.3-codex"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openaiWebSocket, modelID: "gpt-5.3-codex-spark"))
    }

    func testCloudflareAIGatewayUsesProviderPrefixedExactModelIDsForFullySupportedTag() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "openai/gpt-5.2"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "anthropic/claude-sonnet-4-6"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "grok/grok-4-1-fast-reasoning"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "deepseek/deepseek-chat"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "google-vertex-ai/google/gemini-2.5-pro"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "gpt-5.2"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "openai/gpt-5.2-custom"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "xai/grok-4-1-fast-reasoning"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "grok/grok-imagine-image-pro"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "google-ai-studio/gemini-3-pro-image-preview"))
    }

    func testCloudflareNativePDFSupportUsesExactCatalogAndStaysDisabled() {
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .cloudflareAIGateway, modelID: "openai/gpt-5.2"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .cloudflareAIGateway, modelID: "anthropic/claude-sonnet-4-6"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .cloudflareAIGateway, modelID: "google-vertex-ai/google/gemini-2.5-pro"))
    }

    func testFireworksGLM5IsMarkedAsFullySupported() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "fireworks/glm-5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "accounts/fireworks/models/glm-5"))
    }

    func testFireworksMiniMaxM2p5IsMarkedAsFullySupported() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "fireworks/minimax-m2p5"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "accounts/fireworks/models/minimax-m2p5"))
    }

    func testOpenRouterGoogleGeminiPreviewIsMarkedAsFullySupported() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "google/gemini-3-pro-preview"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "google/gemini-3.1-pro-preview"))
    }

    func testGeminiProvider3Point1PreviewIsMarkedAsFullySupported() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .gemini, modelID: "gemini-3.1-pro-preview"))
    }

    func testVertexAIProvider3Point1PreviewIsMarkedAsFullySupported() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .vertexai, modelID: "gemini-3.1-pro-preview"))
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
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .openai, modelID: "gpt-5"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .openai, modelID: "o4-mini"))
    }

    func testOpenAIWebSocketNativePDFSupportUsesExactMatch() {
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .openaiWebSocket, modelID: "gpt-4o"))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .openaiWebSocket, modelID: "gpt-5.2"))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .openaiWebSocket, modelID: "gpt-5.3-codex"))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .openaiWebSocket, modelID: "o4"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .openaiWebSocket, modelID: "gpt-5"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .openaiWebSocket, modelID: "o4-mini"))
    }

    func testXAINativePDFSupportUsesExactMatch() {
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .xai, modelID: "grok-4-1-fast-reasoning"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .xai, modelID: "grok-5"))
    }
}
