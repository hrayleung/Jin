import XCTest
@testable import Jin

final class ModelCapabilityRegistryTests: XCTestCase {
    func testGeminiWebSearchUsesExactDocumentedModelIDs() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3.1-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3-pro-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3-flash-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3-pro-image-preview"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemini-3.1-flash-image-preview"))
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
}
