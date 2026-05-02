import XCTest
@testable import Jin

final class ConversationTitleGeneratorTests: XCTestCase {
    func testNormalizeTitleTrimsQuotesAndPrefixAndNewline() {
        let raw = "\n\"Title:  深度学习 入门\n第二行\"\n"
        let normalized = ConversationTitleGenerator.normalizeTitle(raw, maxCharacters: 50)
        XCTAssertEqual(normalized, "深度学习 入门")
    }

    func testNormalizeTitleHandlesChineseTitlePrefix() {
        let raw = "标题:   Swift 并发实践"
        let normalized = ConversationTitleGenerator.normalizeTitle(raw, maxCharacters: 50)
        XCTAssertEqual(normalized, "Swift 并发实践")
    }

    func testNormalizeTitleCollapsesSpacesAndCapsLength() {
        let raw = "  This    is    a     very long chat title  "
        let normalized = ConversationTitleGenerator.normalizeTitle(raw, maxCharacters: 12)
        XCTAssertEqual(normalized, "This is a ve")
    }

    func testChatNamingModelSupportRejectsImageAndVideoModels() {
        let chat = ModelInfo(
            id: "chat-model",
            name: "Chat",
            capabilities: [.streaming, .toolCalling],
            contextWindow: 128_000
        )
        let image = ModelInfo(
            id: "image-model",
            name: "Image",
            capabilities: [.imageGeneration],
            contextWindow: 128_000
        )
        let video = ModelInfo(
            id: "video-model",
            name: "Video",
            capabilities: [.videoGeneration],
            contextWindow: 128_000
        )

        XCTAssertTrue(ChatNamingModelSupport.isSupported(model: chat, providerType: .openai))
        XCTAssertFalse(ChatNamingModelSupport.isSupported(model: image, providerType: .openai))
        XCTAssertFalse(ChatNamingModelSupport.isSupported(model: video, providerType: .openrouter))
    }

    func testChatNamingModelSupportUsesOverridesForEligibility() {
        let customImageModel = ModelInfo(
            id: "custom-model",
            name: "Custom",
            capabilities: [.imageGeneration],
            contextWindow: 128_000,
            overrides: ModelOverrides(
                modelType: .chat,
                capabilities: [.streaming]
            )
        )

        XCTAssertTrue(ChatNamingModelSupport.isSupported(model: customImageModel, providerType: .openaiCompatible))
    }

    func testChatNamingStreamingPreferenceUsesResolvedModelCapabilities() {
        let streamingModel = ModelInfo(
            id: "streaming-chat",
            name: "Streaming Chat",
            capabilities: [.streaming],
            contextWindow: 128_000
        )
        let nonStreamingModel = ModelInfo(
            id: "non-streaming-chat",
            name: "Non-streaming Chat",
            capabilities: [.toolCalling],
            contextWindow: 128_000
        )
        let provider = ProviderConfig(
            id: "test",
            name: "Test",
            type: .openaiCompatible,
            models: [streamingModel, nonStreamingModel]
        )

        XCTAssertTrue(ChatNamingModelSupport.shouldRequestStreaming(providerConfig: provider, modelID: streamingModel.id))
        XCTAssertFalse(ChatNamingModelSupport.shouldRequestStreaming(providerConfig: provider, modelID: nonStreamingModel.id))
    }
}
