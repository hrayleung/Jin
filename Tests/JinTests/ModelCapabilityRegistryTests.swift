import XCTest
@testable import Jin

final class ModelCapabilityRegistryTests: XCTestCase {
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

    func testOpenRouterGoogleModelsUseCanonicalAllowlist() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "google/gemini-3-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "google/gemini-3.1-pro-preview"))

        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "google/veo-3"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "google/gemini-2.0-flash-lite"))
    }

    func testTogetherWebSearchDefaultsToDisabled() {
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .together, modelID: "moonshotai/Kimi-K2.5"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .together, modelID: "zai-org/GLM-5"))
    }

    func testVercelAIGatewayWebSearchDefaultsToDisabledForNativeControls() {
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .vercelAIGateway, modelID: "openai/gpt-5.2"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .vercelAIGateway, modelID: "anthropic/claude-sonnet-4.6"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .vercelAIGateway, modelID: "google/gemini-3.1-pro-preview"))
    }
}
