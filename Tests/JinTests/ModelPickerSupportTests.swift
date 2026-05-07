import XCTest
@testable import Jin

final class ModelPickerSupportTests: XCTestCase {
    func testManagedAgentFilteringUsesNameIDAndModelFields() {
        let agents = [
            agent(id: "build-agent", name: "Build Agent", modelID: "claude-sonnet-4-6", modelDisplayName: "Sonnet 4.6"),
            agent(id: "review-agent", name: "Review Agent", modelID: "claude-opus-4-1", modelDisplayName: "Opus 4.1")
        ]

        XCTAssertEqual(
            ModelPickerSupport.filteredManagedAgents(agents, searchText: " opus ").map(\.id),
            ["review-agent"]
        )
        XCTAssertEqual(
            ModelPickerSupport.filteredManagedAgents(agents, searchText: "build").map(\.id),
            ["build-agent"]
        )
        XCTAssertEqual(
            ModelPickerSupport.filteredManagedAgents(agents, searchText: "   ").map(\.id),
            ["build-agent", "review-agent"]
        )
    }

    func testManagedAgentSectionVisibilityAndSelectedNameFallback() {
        XCTAssertFalse(
            ModelPickerSupport.shouldShowManagedAgentSection(
                hasManagedAgentContext: false,
                trimmedSearchText: "",
                filteredManagedAgents: [agent(id: "a", name: "A")]
            )
        )
        XCTAssertTrue(
            ModelPickerSupport.shouldShowManagedAgentSection(
                hasManagedAgentContext: true,
                trimmedSearchText: "",
                filteredManagedAgents: []
            )
        )
        XCTAssertFalse(
            ModelPickerSupport.shouldShowManagedAgentSection(
                hasManagedAgentContext: true,
                trimmedSearchText: "missing",
                filteredManagedAgents: []
            )
        )

        XCTAssertEqual(
            ModelPickerSupport.selectedManagedAgentName(
                selectedAgentID: "review-agent",
                availableAgents: [agent(id: "review-agent", name: "Review Agent")]
            ),
            "Review Agent"
        )
        XCTAssertEqual(
            ModelPickerSupport.selectedManagedAgentName(
                selectedAgentID: "unknown",
                availableAgents: []
            ),
            "unknown"
        )
        XCTAssertNil(
            ModelPickerSupport.selectedManagedAgentName(
                selectedAgentID: nil,
                availableAgents: []
            )
        )
    }

    func testFilteredSectionsSortProvidersSkipManagedProviderAndIgnoreDisabledOrEmptyProviders() {
        let sections = ModelPickerSupport.filteredSections(
            providers: [
                provider(id: "z", name: "Zeta", isEnabled: true, models: [model(id: "z1", name: "Z One")]),
                provider(id: "managed", name: "Managed", isEnabled: true, models: [model(id: "m1", name: "Managed One")]),
                provider(id: "disabled", name: "Alpha Disabled", isEnabled: false, models: [model(id: "d1", name: "D One")]),
                provider(id: "empty", name: "Beta Empty", isEnabled: true, models: []),
                provider(id: "a", name: "Alpha", isEnabled: true, models: [model(id: "a1", name: "A One")])
            ],
            scope: .all,
            searchText: "",
            managedAgentProviderID: "managed",
            isFavorite: { _, _ in false }
        )

        XCTAssertEqual(sections.map(\.providerID), ["a", "z"])
        XCTAssertEqual(sections.flatMap { $0.models.map(\.id) }, ["a1", "z1"])
    }

    func testFavoritesScopeFiltersPerProviderAndSearchUsesProviderOrModelMatches() {
        let providers = [
            provider(
                id: "openai",
                name: "OpenAI",
                typeRaw: "openai",
                models: [
                    model(id: "gpt-5", name: "GPT 5"),
                    model(id: "gpt-image-1", name: "Image")
                ]
            ),
            provider(
                id: "anthropic",
                name: "Anthropic",
                typeRaw: "anthropic",
                models: [
                    model(id: "claude-sonnet-4-6", name: "Claude Sonnet"),
                    model(id: "claude-opus-4-1", name: "Claude Opus")
                ]
            )
        ]
        let favorites: Set<FavoriteModelKey> = [
            FavoriteModelKey(providerID: "openai", modelID: "gpt-5"),
            FavoriteModelKey(providerID: "anthropic", modelID: "claude-opus-4-1")
        ]

        let favoriteSections = ModelPickerSupport.filteredSections(
            providers: providers,
            scope: .favorites,
            searchText: "",
            managedAgentProviderID: nil,
            isFavorite: { providerID, modelID in favorites.contains(FavoriteModelKey(providerID: providerID, modelID: modelID)) }
        )
        XCTAssertEqual(favoriteSections.map(\.providerID), ["anthropic", "openai"])
        XCTAssertEqual(favoriteSections.flatMap { $0.models.map(\.id) }, ["claude-opus-4-1", "gpt-5"])

        let providerMatchedSections = ModelPickerSupport.filteredSections(
            providers: providers,
            scope: .all,
            searchText: "open",
            managedAgentProviderID: nil,
            isFavorite: { _, _ in false }
        )
        XCTAssertEqual(providerMatchedSections.map(\.providerID), ["openai"])
        XCTAssertEqual(providerMatchedSections.first?.models.map(\.id), ["gpt-5", "gpt-image-1"])

        let modelMatchedSections = ModelPickerSupport.filteredSections(
            providers: providers,
            scope: .all,
            searchText: "opus",
            managedAgentProviderID: nil,
            isFavorite: { _, _ in false }
        )
        XCTAssertEqual(modelMatchedSections.map(\.providerID), ["anthropic"])
        XCTAssertEqual(modelMatchedSections.first?.models.map(\.id), ["claude-opus-4-1"])
    }

    func testCopyAndScopedIDsMatchPopoverBehavior() {
        XCTAssertEqual(ModelPickerSupport.searchPlaceholder, "Search")
        XCTAssertEqual(ModelPickerSupport.trimmedSearchText(" model "), "model")
        XCTAssertEqual(ModelPickerSupport.emptyStateTitle(scope: .favorites), "No favorite models")
        XCTAssertEqual(ModelPickerSupport.emptyStateTitle(scope: .all), "No results")
        XCTAssertEqual(ModelPickerSupport.emptyStateDescription(scope: .favorites), "Star a model to pin it here.")
        XCTAssertEqual(ModelPickerSupport.emptyStateDescription(scope: .all), "Try another search.")
        XCTAssertEqual(ModelPickerSupport.managedAgentEmptyRowText(trimmedSearchText: ""), "No agents")
        XCTAssertEqual(ModelPickerSupport.managedAgentEmptyRowText(trimmedSearchText: "x"), "No matches")

        let scoped = ModelPickerSupport.scopedModels(
            providerID: "openai",
            models: [
                model(id: "gpt", name: "GPT"),
                model(id: "gpt", name: "GPT Duplicate")
            ]
        )
        XCTAssertEqual(scoped.map(\.id), ["openai::gpt::0", "openai::gpt::1"])
    }

    private func provider(
        id: String,
        name: String,
        typeRaw: String = "openai",
        isEnabled: Bool = true,
        models: [ModelInfo]
    ) -> ModelPickerSupport.ProviderSnapshot {
        ModelPickerSupport.ProviderSnapshot(
            id: id,
            name: name,
            typeRaw: typeRaw,
            isEnabled: isEnabled,
            selectableModels: models
        )
    }

    private func model(id: String, name: String) -> ModelInfo {
        ModelInfo(id: id, name: name, contextWindow: 128_000)
    }

    private func agent(
        id: String,
        name: String,
        modelID: String? = nil,
        modelDisplayName: String? = nil
    ) -> ClaudeManagedAgentDescriptor {
        ClaudeManagedAgentDescriptor(
            id: id,
            name: name,
            modelID: modelID,
            modelDisplayName: modelDisplayName
        )
    }
}
