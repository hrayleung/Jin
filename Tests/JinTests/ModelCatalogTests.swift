import XCTest
@testable import Jin

final class ModelCatalogTests: XCTestCase {
    func testUnknownGeminiAndVertexIDsUseConservativeFallback() {
        let gemini = ModelCatalog.modelInfo(
            for: "gemini-3-pro-preview-custom",
            provider: .gemini,
            name: "Custom Gemini"
        )
        XCTAssertEqual(gemini.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(gemini.contextWindow, 128_000)
        XCTAssertNil(gemini.reasoningConfig)

        let vertex = ModelCatalog.modelInfo(
            for: "gemini-2.5-pro-experimental",
            provider: .vertexai,
            name: "Custom Vertex"
        )
        XCTAssertEqual(vertex.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(vertex.contextWindow, 128_000)
        XCTAssertNil(vertex.reasoningConfig)
    }

    func testCloudflareRequiresExactCompoundIDMatches() {
        let known = ModelCatalog.modelInfo(
            for: "openai/gpt-5.2",
            provider: .cloudflareAIGateway
        )
        XCTAssertTrue(known.capabilities.contains(.vision))
        XCTAssertFalse(known.capabilities.contains(.nativePDF))

        let unknown = ModelCatalog.modelInfo(
            for: "openai/gpt-5.2-custom",
            provider: .cloudflareAIGateway
        )
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.reasoningConfig)
    }

    func testOpenAIAudioModelsAreCatalogBackedByExactIDs() {
        let audioPreview = ModelCatalog.modelInfo(
            for: "gpt-4o-audio-preview",
            provider: .openai
        )
        XCTAssertTrue(audioPreview.capabilities.contains(.audio))

        let realtime = ModelCatalog.modelInfo(
            for: "gpt-realtime-mini",
            provider: .openai
        )
        XCTAssertTrue(realtime.capabilities.contains(.audio))
    }

    func testNanoBanana2CatalogMetadataUsesExactIDs() {
        let proImage = ModelCatalog.modelInfo(
            for: "gemini-3-pro-image-preview",
            provider: .gemini
        )
        XCTAssertEqual(proImage.contextWindow, 65_536)
        XCTAssertTrue(proImage.capabilities.contains(.imageGeneration))
        XCTAssertTrue(proImage.capabilities.contains(.reasoning))
        XCTAssertNil(proImage.reasoningConfig)

        let gemini = ModelCatalog.modelInfo(
            for: "gemini-3.1-flash-image-preview",
            provider: .gemini
        )
        XCTAssertEqual(gemini.contextWindow, 131_072)
        XCTAssertTrue(gemini.capabilities.contains(.imageGeneration))
        XCTAssertTrue(gemini.capabilities.contains(.nativePDF))
        XCTAssertTrue(gemini.capabilities.contains(.reasoning))
        XCTAssertFalse(gemini.capabilities.contains(.toolCalling))
        XCTAssertEqual(gemini.reasoningConfig?.defaultEffort, .minimal)

        let vertex = ModelCatalog.modelInfo(
            for: "gemini-3.1-flash-image-preview",
            provider: .vertexai
        )
        XCTAssertEqual(vertex.contextWindow, 131_072)
        XCTAssertTrue(vertex.capabilities.contains(.imageGeneration))
        XCTAssertTrue(vertex.capabilities.contains(.nativePDF))
        XCTAssertTrue(vertex.capabilities.contains(.reasoning))
        XCTAssertFalse(vertex.capabilities.contains(.toolCalling))
        XCTAssertNil(vertex.reasoningConfig)
    }
}
