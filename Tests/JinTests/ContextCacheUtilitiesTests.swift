import XCTest
@testable import Jin

final class ContextCacheUtilitiesTests: XCTestCase {
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
