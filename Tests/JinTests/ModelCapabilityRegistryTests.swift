import XCTest
@testable import Jin

final class ModelCapabilityRegistryTests: XCTestCase {
    func testOpenAICodeExecutionUsesExactDocumentedModelIDs() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-4.1"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-5"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-5.2"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-5.4"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "o3"))

        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-5.4-pro"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-4o"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-4o-audio-preview"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "gpt-realtime"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: "o4"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .openaiWebSocket, modelID: "gpt-realtime"))
    }

    func testAnthropicCodeExecutionUsesExactDocumentedModelIDs() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-opus-4-6"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-sonnet-4-6"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-sonnet-4-5-20250929"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-haiku-4-5-20251001"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-3-7-sonnet-20250219"))

        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-haiku-4"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-sonnet-4-5"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-opus-4-6-20260128"))
    }

    func testGeminiCodeExecutionUsesExactDocumentedModelIDs() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-3-pro"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-3.1-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-3-flash-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-3.1-flash-lite-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-2.5-flash-lite"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-2.0-flash-001"))

        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-3"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-3-pro-image-preview"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-2.5-flash-image"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: "gemini-2.0-flash-lite"))
    }

    func testVertexCodeExecutionUsesExactDocumentedModelIDs() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-3-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-3.1-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-3-flash-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-3.1-flash-lite-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-2.5-flash-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-2.5-flash-lite-preview"))

        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-3"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-3-pro-image-preview"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-2.5-flash-image"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: "gemini-2.0-flash-lite"))
    }

    func testGeminiWebSearchUsesExactDocumentedModelIDs() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3.1-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3-flash-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3-pro-image-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3.1-flash-image-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3.1-flash-lite-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-2.5-flash-lite"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-2.0-flash"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemma-4-31b-it"))

        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-2.5-flash-image"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-2.0-flash-lite"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "veo-3"))
    }

    func testVertexWebSearchUsesExactSupportedModelIDs() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemini-3.1-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemini-3-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemini-3-flash-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemini-3-pro-image-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemini-3.1-flash-image-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemini-3.1-flash-lite-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemini-2.5-flash-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemini-2.5-flash-lite-preview"))

        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "gemini-2.0-flash-lite"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .vertexai, modelID: "veo-2"))
    }

    func testGoogleMapsSupportUsesExactDocumentedModelIDs() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .gemini, modelID: "gemini-2.5-pro"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .gemini, modelID: "gemini-2.5-flash"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .gemini, modelID: "gemini-2.0-flash-001"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsGoogleMaps(for: .gemini, modelID: "gemini-3-pro-preview"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsGoogleMaps(for: .gemini, modelID: "gemini-2.0-flash-lite"))

        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-3-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-3-pro-image-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-3-flash-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-2.5-flash"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-2.5-flash-preview-09-2025"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-2.5-flash-lite-preview-09-2025"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-live-2.5-flash-native-audio"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-live-2.5-flash-preview-native-audio-09-2025"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-2.0-flash-live-preview-04-09"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-2.0-flash-001"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: "gemini-3.1-pro-preview"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsGoogleMaps(for: .openai, modelID: "gpt-5"))
    }

    func testOpenRouterGoogleModelsUseCanonicalAllowlist() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "google/gemini-3-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "google/gemini-3.1-pro-preview"))

        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "google/veo-3"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "google/gemini-2.0-flash-lite"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "google/gemma-4-31b-it"))
    }

    func testTogetherWebSearchDefaultsToDisabled() {
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .together, modelID: "moonshotai/Kimi-K2.5"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .together, modelID: "zai-org/GLM-5"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .together, modelID: "deepseek-ai/DeepSeek-V3.1"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .together, modelID: "openai/gpt-oss-120b"))
    }

    func testVercelAIGatewayWebSearchDefaultsToDisabledForNativeControls() {
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .vercelAIGateway, modelID: "openai/gpt-5.2"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .vercelAIGateway, modelID: "anthropic/claude-sonnet-4.6"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .vercelAIGateway, modelID: "google/gemini-3.1-pro-preview"))
    }
}
