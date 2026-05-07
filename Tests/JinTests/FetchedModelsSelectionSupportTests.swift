import XCTest
@testable import Jin

final class FetchedModelsSelectionSupportTests: XCTestCase {
    func testInitialSelectionPrefillsNewModelsAndChoosesMatchingFilterMode() {
        let models = [
            model(id: "existing", name: "Existing"),
            model(id: "new-a", name: "New A"),
            model(id: "new-b", name: "New B")
        ]

        let selectedIDs = FetchedModelsSelectionSupport.initialSelectedIDs(
            fetchedModels: models,
            existingModelIDs: ["existing"]
        )

        XCTAssertEqual(selectedIDs, ["new-a", "new-b"])
        XCTAssertEqual(FetchedModelsSelectionSupport.initialFilterMode(selectedIDs: selectedIDs), .new)
        XCTAssertEqual(
            FetchedModelsSelectionSupport.initialFilterMode(selectedIDs: []),
            .all
        )
    }

    func testLabelsAndFilterChromeCopyMatchSheetCopy() {
        XCTAssertEqual(FetchedModelsSelectionSupport.selectionLabel(selectedCount: 2), "2 selected")
        XCTAssertEqual(FetchedModelsSelectionSupport.confirmButtonLabel(selectedCount: 0), "Confirm")
        XCTAssertEqual(FetchedModelsSelectionSupport.confirmButtonLabel(selectedCount: 3), "Confirm (3)")
        XCTAssertEqual(FetchedModelsSelectionSupport.filterButtonTitle(for: .all), "Filter")
        XCTAssertEqual(FetchedModelsSelectionSupport.filterButtonTitle(for: .supported), "Fully Supported")
        XCTAssertEqual(FetchedModelsSelectionSupport.filterIconName(for: .all), "line.3.horizontal.decrease")
        XCTAssertEqual(
            FetchedModelsSelectionSupport.filterIconName(for: .existing),
            "line.3.horizontal.decrease.circle.fill"
        )
    }

    func testOrderedModelsGroupsNewModelsFirstThenSortsByDisplayName() {
        let models = [
            model(id: "existing-zeta", name: "Zeta"),
            model(id: "new-beta", name: "Beta"),
            model(id: "existing-alpha", name: "Alpha"),
            model(id: "new-alpha", name: "Alpha")
        ]

        let ordered = FetchedModelsSelectionSupport.orderedModels(
            models,
            existingModelIDs: ["existing-alpha", "existing-zeta"]
        )

        XCTAssertEqual(ordered.map(\.id), ["new-alpha", "new-beta", "existing-alpha", "existing-zeta"])
    }

    func testVisibleModelsApplyFilterModeAfterExistingAwareOrdering() {
        let models = [
            model(id: "existing", name: "Existing"),
            model(id: "supported", name: "Supported"),
            model(id: "new-alpha", name: "Alpha")
        ]
        let existingModelIDs: Set<String> = ["existing"]
        let isFullySupported: (String) -> Bool = { $0 == "supported" }

        XCTAssertEqual(
            visibleIDs(
                in: models,
                existingModelIDs: existingModelIDs,
                filterMode: .all,
                isFullySupported: isFullySupported
            ),
            ["new-alpha", "supported", "existing"]
        )
        XCTAssertEqual(
            visibleIDs(
                in: models,
                existingModelIDs: existingModelIDs,
                filterMode: .new,
                isFullySupported: isFullySupported
            ),
            ["new-alpha", "supported"]
        )
        XCTAssertEqual(
            visibleIDs(
                in: models,
                existingModelIDs: existingModelIDs,
                filterMode: .supported,
                isFullySupported: isFullySupported
            ),
            ["supported"]
        )
        XCTAssertEqual(
            visibleIDs(
                in: models,
                existingModelIDs: existingModelIDs,
                filterMode: .existing,
                isFullySupported: isFullySupported
            ),
            ["existing"]
        )
    }

    func testVisibleModelsSearchesNamesAndIDsWithTrimmedFuzzyQuery() {
        let models = [
            model(id: "gpt-4o", name: "GPT 4o"),
            model(id: "claude-3-5-sonnet", name: "Claude Sonnet")
        ]

        XCTAssertEqual(
            visibleIDs(in: models, searchText: " son "),
            ["claude-3-5-sonnet"]
        )
        XCTAssertEqual(
            visibleIDs(in: models, searchText: "gpt4"),
            ["gpt-4o"]
        )
        XCTAssertEqual(
            visibleIDs(in: models, searchText: "   "),
            ["claude-3-5-sonnet", "gpt-4o"]
        )
    }

    func testCountsAndDisabledStatesPreserveSheetBehavior() {
        let models = [
            model(id: "existing", name: "Existing"),
            model(id: "new", name: "New")
        ]

        XCTAssertEqual(
            FetchedModelsSelectionSupport.existingModelsCount(in: models, existingModelIDs: ["existing"]),
            1
        )
        XCTAssertTrue(FetchedModelsSelectionSupport.isConfirmDisabled(selectedCount: 0, existingModelsCount: 0))
        XCTAssertFalse(FetchedModelsSelectionSupport.isConfirmDisabled(selectedCount: 1, existingModelsCount: 0))
        XCTAssertFalse(FetchedModelsSelectionSupport.isConfirmDisabled(selectedCount: 0, existingModelsCount: 1))
        XCTAssertTrue(FetchedModelsSelectionSupport.isSelectAllDisabled(models: [], selectedIDs: []))
        XCTAssertTrue(FetchedModelsSelectionSupport.isSelectAllDisabled(models: models, selectedIDs: ["existing", "new"]))
        XCTAssertFalse(FetchedModelsSelectionSupport.isSelectAllDisabled(models: models, selectedIDs: ["existing"]))
    }

    private func visibleIDs(
        in models: [ModelInfo],
        existingModelIDs: Set<String> = [],
        filterMode: FetchedModelsSelectionFilterMode = .all,
        searchText: String = "",
        isFullySupported: (String) -> Bool = { _ in false }
    ) -> [String] {
        FetchedModelsSelectionSupport.visibleModels(
            in: models,
            existingModelIDs: existingModelIDs,
            filterMode: filterMode,
            searchText: searchText,
            isFullySupported: isFullySupported
        )
        .map(\.id)
    }

    private func model(id: String, name: String) -> ModelInfo {
        ModelInfo(id: id, name: name, contextWindow: 128_000)
    }
}
