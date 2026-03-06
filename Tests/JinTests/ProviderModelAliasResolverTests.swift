import XCTest
@testable import Jin

final class ProviderModelAliasResolverTests: XCTestCase {
    func testGitHubCopilotLegacyUnprefixedModelIDResolvesToCatalogModel() {
        let models = [
            ModelInfo(
                id: "ai21-labs/ai21-jamba-1.5-large",
                name: "AI21 Jamba 1.5 Large",
                capabilities: [.toolCalling],
                contextWindow: 256_000,
                maxOutputTokens: 4_096,
                reasoningConfig: nil,
                isEnabled: true
            )
        ]

        let resolved = ProviderModelAliasResolver.resolvedModel(
            for: "ai21-jamba-1.5-large",
            providerType: .githubCopilot,
            availableModels: models
        )

        XCTAssertEqual(resolved?.id, "ai21-labs/ai21-jamba-1.5-large")
    }

    func testGitHubCopilotLegacySuffixMatchRequiresUniqueCandidate() {
        let models = [
            ModelInfo(id: "vendor-a/shared-model", name: "Shared A", capabilities: [], contextWindow: 128_000, isEnabled: true),
            ModelInfo(id: "vendor-b/shared-model", name: "Shared B", capabilities: [], contextWindow: 128_000, isEnabled: true),
        ]

        let resolved = ProviderModelAliasResolver.resolvedModel(
            for: "shared-model",
            providerType: .githubCopilot,
            availableModels: models
        )

        XCTAssertNil(resolved)
    }
}
