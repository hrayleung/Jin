import XCTest
@testable import Jin

final class ChatMCPToolCapabilitySupportTests: XCTestCase {
    func testSupportsMCPToolsRequiresToolCallingCapability() {
        XCTAssertTrue(supportsMCPTools(capabilities: [.streaming, .toolCalling]))
        XCTAssertFalse(supportsMCPTools(capabilities: [.streaming]))
        XCTAssertFalse(
            ChatMCPToolCapabilitySupport.supportsMCPTools(
                providerType: .openai,
                resolvedModelSettings: nil
            )
        )
    }

    func testSupportsMCPToolsRejectsInternalAndCodexProviders() {
        XCTAssertFalse(
            supportsMCPTools(
                providerType: .claudeManagedAgents,
                capabilities: [.streaming, .toolCalling]
            )
        )
        XCTAssertFalse(
            supportsMCPTools(
                providerType: .codexAppServer,
                capabilities: [.streaming, .toolCalling]
            )
        )
    }

    func testSupportsMCPToolsRejectsMediaGenerationModels() {
        XCTAssertFalse(supportsMCPTools(capabilities: [.streaming, .toolCalling, .imageGeneration]))
        XCTAssertFalse(supportsMCPTools(capabilities: [.streaming, .toolCalling, .videoGeneration]))
    }

    private func supportsMCPTools(
        providerType: ProviderType? = .openai,
        capabilities: ModelCapability
    ) -> Bool {
        ChatMCPToolCapabilitySupport.supportsMCPTools(
            providerType: providerType,
            resolvedModelSettings: resolvedSettings(capabilities: capabilities)
        )
    }

    private func resolvedSettings(capabilities: ModelCapability) -> ResolvedModelSettings {
        ResolvedModelSettings(
            modelType: .chat,
            capabilities: capabilities,
            contextWindow: 128_000,
            maxOutputTokens: nil,
            reasoningConfig: nil,
            reasoningCanDisable: true,
            supportsWebSearch: false,
            requestShape: .openAICompatible,
            supportsOpenAIStyleReasoningEffort: false,
            supportsOpenAIStyleExtremeEffort: false
        )
    }
}
