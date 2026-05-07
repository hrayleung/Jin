import XCTest
@testable import Jin

final class ContextCacheUtilitiesTests: XCTestCase {
    func testNormalizedSystemPromptTrimsJoinedSystemText() {
        let messages = [
            Message(role: .system, content: [.text("  first  "), .text("\nsecond\n")]),
            Message(role: .user, content: [.text("ignored")])
        ]

        XCTAssertEqual(
            ContextCacheUtilities.normalizedSystemPrompt(in: messages),
            "first  \n\nsecond"
        )
    }

    func testNormalizedSystemPromptReturnsNilForWhitespaceOnlyText() {
        let messages = [
            Message(role: .system, content: [.text("  \n\t  ")])
        ]

        XCTAssertNil(ContextCacheUtilities.normalizedSystemPrompt(in: messages))
    }

    func testNormalizedGoogleCachedContentModelsTrimWhitespaceAndPreservePrefixes() {
        XCTAssertEqual(
            ContextCacheUtilities.normalizedGeminiCachedContentModel("  gemini-2.5-pro  "),
            "models/gemini-2.5-pro"
        )
        XCTAssertEqual(
            ContextCacheUtilities.normalizedGeminiCachedContentModel("  models/gemini-2.5-pro  "),
            "models/gemini-2.5-pro"
        )
        XCTAssertEqual(
            ContextCacheUtilities.normalizedVertexCachedContentModel("  gemini-2.5-pro  "),
            "publishers/google/models/gemini-2.5-pro"
        )
        XCTAssertEqual(
            ContextCacheUtilities.normalizedVertexCachedContentModel("  models/gemini-2.5-pro  "),
            "publishers/google/models/gemini-2.5-pro"
        )
        XCTAssertEqual(
            ContextCacheUtilities.normalizedVertexCachedContentModel("  publishers/google/models/gemini-2.5-pro  "),
            "publishers/google/models/gemini-2.5-pro"
        )
    }

    func testAnthropicAutomaticOptimizationUsesPrefixWindowStrategy() async {
        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )
        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key")
        let controls = GenerationControls(
            contextCache: ContextCacheControls(
                mode: .implicit,
                strategy: .systemOnly,
                ttl: .providerDefault
            )
        )

        let optimized = await ContextCacheUtilities.applyAutomaticContextCacheOptimizations(
            adapter: adapter,
            providerType: .anthropic,
            modelID: "claude-sonnet-4-6",
            messages: [Message(role: .user, content: [.text("hi")])],
            controls: controls,
            tools: []
        )

        XCTAssertEqual(optimized.controls.contextCache?.strategy, .prefixWindow)
    }
}
