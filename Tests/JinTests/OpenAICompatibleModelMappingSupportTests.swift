import Foundation
import XCTest
@testable import Jin

final class OpenAICompatibleModelMappingSupportTests: XCTestCase {
    func testGitHubModelInfoMapsCapabilitiesAndCatalogMetadata() throws {
        let data = Data(
            """
            {
              "id": "example/reasoning-vision-model",
              "name": " Reasoning Vision ",
              "supported_input_modalities": ["text", "image", "pdf"],
              "supported_output_modalities": ["text", "image"],
              "capabilities": ["streaming", "tool-calling", "prompt-caching", "reasoning"],
              "limits": {
                "max_input_tokens": 64000,
                "max_output_tokens": 8192
              },
              "publisher": " Example AI ",
              "summary": " Multimodal test model ",
              "rate_limit_tier": " free "
            }
            """.utf8
        )
        let model = try JSONDecoder().decode(GitHubModelsCatalogModel.self, from: data)

        let info = try XCTUnwrap(OpenAICompatibleModelMappingSupport.gitHubModelInfo(from: model))

        XCTAssertEqual(info.id, "example/reasoning-vision-model")
        XCTAssertEqual(info.name, "Reasoning Vision")
        XCTAssertEqual(info.contextWindow, 64_000)
        XCTAssertEqual(info.maxOutputTokens, 8_192)
        XCTAssertTrue(info.capabilities.contains(.streaming))
        XCTAssertTrue(info.capabilities.contains(.vision))
        XCTAssertTrue(info.capabilities.contains(.nativePDF))
        XCTAssertTrue(info.capabilities.contains(.imageGeneration))
        XCTAssertTrue(info.capabilities.contains(.toolCalling))
        XCTAssertTrue(info.capabilities.contains(.reasoning))
        XCTAssertTrue(info.capabilities.contains(.promptCaching))
        XCTAssertEqual(info.reasoningConfig?.type, .effort)
        XCTAssertEqual(
            info.catalogMetadata?.availabilityMessage,
            "Example AI\nMultimodal test model\nRate limit tier: free"
        )
    }

    func testGitHubModelInfoDropsNonTextOutputModels() throws {
        let data = Data(
            """
            {
              "id": "example/embedding-model",
              "supported_input_modalities": ["text"],
              "supported_output_modalities": ["embeddings"],
              "capabilities": []
            }
            """.utf8
        )
        let model = try JSONDecoder().decode(GitHubModelsCatalogModel.self, from: data)

        XCTAssertNil(OpenAICompatibleModelMappingSupport.gitHubModelInfo(from: model))
    }

    func testVercelModelInfoUsesCatalogForKnownModelsAndDerivesUnknownModels() {
        let known = OpenAIModelsResponse.Model(
            id: "openai/gpt-5.2",
            name: "GPT 5.2 (Gateway)",
            contextWindow: 400_000,
            maxTokens: 128_000,
            type: "language",
            tags: ["reasoning", "vision", "implicit-caching"]
        )
        let knownInfo = OpenAICompatibleModelMappingSupport.modelInfo(
            from: known,
            providerType: .vercelAIGateway
        )

        XCTAssertEqual(knownInfo.name, "GPT-5.2")
        XCTAssertEqual(knownInfo.contextWindow, 400_000)
        XCTAssertTrue(knownInfo.capabilities.contains(.reasoning))
        XCTAssertTrue(knownInfo.capabilities.contains(.promptCaching))

        let unknown = OpenAIModelsResponse.Model(
            id: "example/unknown-thinking-model",
            name: " ",
            contextWindow: 321_000,
            maxTokens: nil,
            type: "language",
            tags: ["reasoning", "implicit-caching", "vision"]
        )
        let unknownInfo = OpenAICompatibleModelMappingSupport.modelInfo(
            from: unknown,
            providerType: .vercelAIGateway
        )

        XCTAssertEqual(unknownInfo.name, "example/unknown-thinking-model")
        XCTAssertEqual(unknownInfo.contextWindow, 321_000)
        XCTAssertTrue(unknownInfo.capabilities.contains(.streaming))
        XCTAssertTrue(unknownInfo.capabilities.contains(.toolCalling))
        XCTAssertTrue(unknownInfo.capabilities.contains(.vision))
        XCTAssertTrue(unknownInfo.capabilities.contains(.reasoning))
        XCTAssertTrue(unknownInfo.capabilities.contains(.promptCaching))
        XCTAssertEqual(unknownInfo.reasoningConfig?.type, .effort)
    }

    func testVercelMediaModelsDoNotKeepFunctionToolCapability() {
        let image = OpenAIModelsResponse.Model(
            id: "example/image-model",
            name: "Image Model",
            contextWindow: 8_192,
            maxTokens: nil,
            type: "image",
            tags: ["image-generation", "tool-use"]
        )

        let info = OpenAICompatibleModelMappingSupport.modelInfo(
            from: image,
            providerType: .vercelAIGateway
        )

        XCTAssertEqual(info.capabilities, [.imageGeneration])
        XCTAssertNil(info.reasoningConfig)
    }

    func testMiMoTTSModelFilterUsesSharedModelIDRules() {
        XCTAssertTrue(OpenAICompatibleModelMappingSupport.isMiMoTTSModelID("mimo-v2.5-tts"))
        XCTAssertTrue(OpenAICompatibleModelMappingSupport.isMiMoTTSModelID("mimo-v2.5-tts-voicedesign"))
        XCTAssertFalse(OpenAICompatibleModelMappingSupport.isMiMoTTSModelID("mimo-v2.5"))
    }
}
