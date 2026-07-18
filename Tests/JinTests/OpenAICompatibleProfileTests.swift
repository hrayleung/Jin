import XCTest
@testable import Jin

final class OpenAICompatibleProfileTests: XCTestCase {
    func testDeepSeekUsesReasoningContentField() {
        let profile = OpenAICompatibleProfile.profile(for: .deepseek)
        XCTAssertEqual(profile?.reasoningField, .reasoningContent)
        XCTAssertTrue(profile?.capabilities.contains(.reasoning) == true)
        XCTAssertFalse(profile?.disablesStreamingWithTools == true)
    }

    func testCerebrasDisablesStreamingWithTools() {
        let profile = OpenAICompatibleProfile.profile(for: .cerebras)
        XCTAssertEqual(profile?.reasoningField, .reasoning)
        XCTAssertTrue(profile?.disablesStreamingWithTools == true)
    }

    func testMorphLLMIsStreamingOnly() {
        let profile = OpenAICompatibleProfile.profile(for: .morphllm)
        XCTAssertEqual(profile?.capabilities, [.streaming])
        XCTAssertEqual(profile?.reasoningField, .reasoning)
    }

    func testGenericOpenAICompatibleUsesDefaultReasoningField() {
        let profile = OpenAICompatibleProfile.profile(for: .openaiCompatible)
        XCTAssertEqual(profile?.reasoningField, .reasoningOrReasoningContent)
    }

    func testSpecialistProvidersHaveNoCompatibleProfile() {
        XCTAssertNil(OpenAICompatibleProfile.profile(for: .anthropic))
        XCTAssertNil(OpenAICompatibleProfile.profile(for: .gemini))
        XCTAssertNil(OpenAICompatibleProfile.profile(for: .xai))
        XCTAssertNil(OpenAICompatibleProfile.profile(for: .openai))
    }

    func testFireworksKeepsVisionAndAudioCapabilities() {
        let profile = OpenAICompatibleProfile.profile(for: .fireworks)
        XCTAssertTrue(profile?.capabilities.contains(.vision) == true)
        XCTAssertTrue(profile?.capabilities.contains(.audio) == true)
        XCTAssertEqual(profile?.reasoningField, .reasoningContent)
    }

    func testChatWithVisionProvidersOmitAudio() {
        for type: ProviderType in [.together, .sambanova, .zyphra, .meta, .perplexity] {
            let profile = OpenAICompatibleProfile.profile(for: type)
            XCTAssertEqual(
                profile?.capabilities,
                [.streaming, .toolCalling, .vision, .reasoning],
                "Unexpected capabilities for \(type)"
            )
            XCTAssertFalse(profile?.capabilities.contains(.audio) == true, "\(type) should not claim audio")
            XCTAssertEqual(profile?.reasoningField, .reasoningOrReasoningContent)
        }
    }

    func testDatabricksAndOpenCodeGoProfiles() {
        let databricks = OpenAICompatibleProfile.profile(for: .databricks)
        XCTAssertEqual(databricks?.capabilities, [.streaming, .toolCalling, .vision, .reasoning])

        let opencode = OpenAICompatibleProfile.profile(for: .opencodeGo)
        XCTAssertTrue(opencode?.capabilities.contains(.audio) == true)
    }
}
