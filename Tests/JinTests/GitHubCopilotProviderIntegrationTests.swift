import XCTest
@testable import Jin

final class GitHubCopilotProviderIntegrationTests: XCTestCase {
    func testGitHubCopilotProviderTypeDefaultsAndIconMapping() {
        XCTAssertEqual(ProviderType.githubCopilot.displayName, "GitHub Copilot")
        XCTAssertEqual(ProviderType.githubCopilot.defaultBaseURL, "https://models.github.ai/inference")
        XCTAssertEqual(LobeProviderIconCatalog.defaultIconID(for: .githubCopilot), "GithubCopilot")
    }

    func testProviderManagerCreatesOpenAICompatibleAdapterForGitHubCopilot() async throws {
        let config = ProviderConfig(
            id: "github-copilot",
            name: "GitHub Copilot",
            type: .githubCopilot,
            apiKey: "test-token",
            baseURL: ProviderType.githubCopilot.defaultBaseURL,
            models: []
        )

        let manager = ProviderManager()
        let adapter = try await manager.createAdapter(for: config)

        XCTAssertTrue(adapter is OpenAICompatibleAdapter)
    }

    func testDefaultProviderSeedsIncludeGitHubCopilotWithoutSeededModels() {
        let providers = DefaultProviderSeeds.allProviders()
        guard let provider = providers.first(where: { $0.type == .githubCopilot }) else {
            return XCTFail("Expected GitHub Copilot in default provider seeds.")
        }

        XCTAssertEqual(provider.id, "github-copilot")
        XCTAssertEqual(provider.baseURL, ProviderType.githubCopilot.defaultBaseURL)
        XCTAssertTrue(provider.models.isEmpty)
    }
}
