import Foundation

enum FetchedModelsSelectionFilterMode: String, CaseIterable {
    case all = "All Models"
    case new = "New Only"
    case supported = "Fully Supported"
    case existing = "Already Added"
}

enum FetchedModelsSelectionSupport {
    static func initialSelectedIDs(
        fetchedModels: [ModelInfo],
        existingModelIDs: Set<String>
    ) -> Set<String> {
        Set(fetchedModels.lazy.filter { !isExisting($0, in: existingModelIDs) }.map(\.id))
    }

    static func initialFilterMode(selectedIDs: Set<String>) -> FetchedModelsSelectionFilterMode {
        selectedIDs.isEmpty ? .all : .new
    }

    static func selectionLabel(selectedCount: Int) -> String {
        "\(selectedCount) selected"
    }

    static func confirmButtonLabel(selectedCount: Int) -> String {
        selectedCount == 0 ? "Confirm" : "Confirm (\(selectedCount))"
    }

    static func filterButtonTitle(for mode: FetchedModelsSelectionFilterMode) -> String {
        mode == .all ? "Filter" : mode.rawValue
    }

    static func filterIconName(for mode: FetchedModelsSelectionFilterMode) -> String {
        mode == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill"
    }

    static func visibleModels(
        in fetchedModels: [ModelInfo],
        existingModelIDs: Set<String>,
        filterMode: FetchedModelsSelectionFilterMode,
        searchText: String,
        isFullySupported: (String) -> Bool
    ) -> [ModelInfo] {
        let orderedModels = orderedModels(fetchedModels, existingModelIDs: existingModelIDs)
        let filteredModels = modelsMatchingFilter(
            orderedModels,
            existingModelIDs: existingModelIDs,
            filterMode: filterMode,
            isFullySupported: isFullySupported
        )
        return modelsMatchingSearch(filteredModels, searchText: searchText)
    }

    private static func modelsMatchingFilter(
        _ orderedModels: [ModelInfo],
        existingModelIDs: Set<String>,
        filterMode: FetchedModelsSelectionFilterMode,
        isFullySupported: (String) -> Bool
    ) -> [ModelInfo] {
        switch filterMode {
        case .all:
            return orderedModels
        case .new:
            return orderedModels.filter { !isExisting($0, in: existingModelIDs) }
        case .supported:
            return orderedModels.filter { isFullySupported($0.id) }
        case .existing:
            return orderedModels.filter { isExisting($0, in: existingModelIDs) }
        }
    }

    private static func modelsMatchingSearch(
        _ models: [ModelInfo],
        searchText: String
    ) -> [ModelInfo] {
        guard let query = searchText.trimmedNonEmpty else { return models }

        return models
            .compactMap { model in
                searchResult(for: model, query: query)
            }
            .sorted { $0.score > $1.score }
            .map(\.model)
    }

    private static func searchResult(
        for model: ModelInfo,
        query: String
    ) -> (model: ModelInfo, score: Int)? {
        let result = FuzzyMatch.bestMatch(query: query, candidates: [model.name, model.id])
        guard result.matched else { return nil }
        return (model, result.score)
    }

    static func orderedModels(
        _ fetchedModels: [ModelInfo],
        existingModelIDs: Set<String>
    ) -> [ModelInfo] {
        fetchedModels.sorted {
            sortsBefore($0, $1, existingModelIDs: existingModelIDs)
        }
    }

    static func existingModelsCount(
        in fetchedModels: [ModelInfo],
        existingModelIDs: Set<String>
    ) -> Int {
        fetchedModels.filter { isExisting($0, in: existingModelIDs) }.count
    }

    static func isConfirmDisabled(selectedCount: Int, existingModelsCount: Int) -> Bool {
        selectedCount == 0 && existingModelsCount == 0
    }

    static func isSelectAllDisabled(models: [ModelInfo], selectedIDs: Set<String>) -> Bool {
        models.allSatisfy { selectedIDs.contains($0.id) }
    }

    private static func sortsBefore(
        _ lhs: ModelInfo,
        _ rhs: ModelInfo,
        existingModelIDs: Set<String>
    ) -> Bool {
        let lhsExisting = isExisting(lhs, in: existingModelIDs)
        let rhsExisting = isExisting(rhs, in: existingModelIDs)
        if lhsExisting != rhsExisting {
            return !lhsExisting
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func isExisting(_ model: ModelInfo, in existingModelIDs: Set<String>) -> Bool {
        existingModelIDs.contains(model.id)
    }
}
