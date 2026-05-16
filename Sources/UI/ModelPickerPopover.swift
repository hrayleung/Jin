import SwiftUI
import SwiftData

struct ModelPickerPopover: View {
    struct ManagedAgentContext {
        let provider: ProviderConfigEntity
        let selectedAgentID: String?
        let availableAgents: [ClaudeManagedAgentDescriptor]
        let isRefreshing: Bool
        let onRefresh: () -> Void
        let onOpenSettings: () -> Void
        let onSelectAgent: (ClaudeManagedAgentDescriptor) -> Void
    }

    @ObservedObject var favoritesStore: FavoriteModelsStore

    let providers: [ProviderConfigEntity]
    let selectedProviderID: String
    let selectedModelID: String
    let managedAgentContext: ManagedAgentContext?
    let onSelect: (_ providerID: String, _ modelID: String) -> Void

    @State private var scope: ModelPickerScope = .all
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 12) {
            if let managedAgentContext {
                ModelPickerManagedAgentSummaryCard(
                    provider: managedAgentContext.provider,
                    selectedAgentID: managedAgentContext.selectedAgentID,
                    selectedAgentName: selectedManagedAgentName(in: managedAgentContext),
                    isRefreshing: managedAgentContext.isRefreshing,
                    onRefresh: managedAgentContext.onRefresh,
                    onOpenSettings: managedAgentContext.onOpenSettings
                )
            }

            ModelPickerSearchField(
                searchText: $searchText,
                placeholder: searchPlaceholder
            )

            Picker("", selection: $scope) {
                ForEach(ModelPickerScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            modelList
        }
        .padding(12)
        .frame(width: 360, height: 520)
        .jinAdaptiveBackground(
            RoundedRectangle(cornerRadius: 14, style: .continuous),
            material: .ultraThinMaterial
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(JinSemanticColor.borderEmphasized, lineWidth: JinStrokeWidth.hairline)
        )
    }

    private var trimmedSearchText: String {
        ModelPickerSupport.trimmedSearchText(searchText)
    }

    private var searchPlaceholder: String {
        ModelPickerSupport.searchPlaceholder
    }

    private var shouldShowManagedAgentSection: Bool {
        ModelPickerSupport.shouldShowManagedAgentSection(
            hasManagedAgentContext: managedAgentContext != nil,
            trimmedSearchText: trimmedSearchText,
            filteredManagedAgents: filteredManagedAgents
        )
    }

    private var filteredManagedAgents: [ClaudeManagedAgentDescriptor] {
        guard let managedAgentContext else { return [] }
        return ModelPickerSupport.filteredManagedAgents(
            managedAgentContext.availableAgents,
            searchText: searchText
        )
    }

    private func selectedManagedAgentName(in managedAgentContext: ManagedAgentContext) -> String? {
        ModelPickerSupport.selectedManagedAgentName(
            selectedAgentID: managedAgentContext.selectedAgentID,
            availableAgents: managedAgentContext.availableAgents
        )
    }

    private var modelList: some View {
        let sections = filteredSections

        return Group {
            if sections.isEmpty && !shouldShowManagedAgentSection {
                ModelPickerEmptyStateView(
                    title: emptyStateTitle,
                    systemImage: scope == .favorites ? "star" : "magnifyingglass",
                    description: emptyStateDescription
                )
            } else {
                List {
                    if let managedAgentContext, shouldShowManagedAgentSection {
                        Section {
                            managedAgentSectionRows(managedAgentContext)
                        } header: {
                            ModelPickerManagedAgentSectionHeader()
                        }
                    }

                    ForEach(sections) { section in
                        Section {
                            ForEach(
                                ModelPickerSupport.scopedModels(
                                    providerID: section.provider.id,
                                    models: section.models
                                )
                            ) { scopedModel in
                                let model = scopedModel.model
                                ModelPickerRow(
                                    model: model,
                                    isSelected: isSelected(providerID: section.provider.id, modelID: model.id),
                                    isFavorite: favoritesStore.isFavorite(providerID: section.provider.id, modelID: model.id),
                                    onToggleFavorite: {
                                        favoritesStore.toggle(providerID: section.provider.id, modelID: model.id)
                                    },
                                    onSelect: {
                                        onSelect(section.provider.id, model.id)
                                    }
                                )
                                .modelPickerListRowStyle()
                            }
                        } header: {
                            ModelPickerProviderSectionHeader(provider: section.provider)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .modelPickerListSurface()
            }
        }
        .task(id: managedAgentContext?.provider.id ?? "") {
            guard let managedAgentContext,
                  managedAgentContext.availableAgents.isEmpty,
                  !managedAgentContext.isRefreshing,
                  trimmedSearchText.isEmpty else { return }
            managedAgentContext.onRefresh()
        }
    }

    @ViewBuilder
    private func managedAgentSectionRows(_ managedAgentContext: ManagedAgentContext) -> some View {
        if managedAgentContext.isRefreshing && filteredManagedAgents.isEmpty {
            ModelPickerManagedAgentLoadingRow()
                .modelPickerListRowStyle()
        } else if filteredManagedAgents.isEmpty {
            ModelPickerManagedAgentEmptyRow(
                text: ModelPickerSupport.managedAgentEmptyRowText(trimmedSearchText: trimmedSearchText)
            )
            .modelPickerListRowStyle(leading: 12)
        } else {
            ForEach(filteredManagedAgents) { agent in
                ModelPickerManagedAgentRow(
                    agent: agent,
                    isSelected: agent.id == managedAgentContext.selectedAgentID,
                    onSelect: {
                        managedAgentContext.onSelectAgent(agent)
                    }
                )
                .modelPickerListRowStyle()
            }
        }
    }

    private var emptyStateTitle: String {
        ModelPickerSupport.emptyStateTitle(scope: scope)
    }

    private var emptyStateDescription: String {
        ModelPickerSupport.emptyStateDescription(scope: scope)
    }

    private var filteredSections: [ProviderSection] {
        let providerByID = Dictionary(
            providers.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return ModelPickerSupport.filteredSections(
            providers: providers.map(ModelPickerSupport.ProviderSnapshot.init),
            scope: scope,
            searchText: searchText,
            managedAgentProviderID: managedAgentContext?.provider.id,
            isFavorite: { providerID, modelID in
                favoritesStore.isFavorite(providerID: providerID, modelID: modelID)
            }
        )
        .compactMap { section in
            providerByID[section.providerID].map {
                ProviderSection(provider: $0, models: section.models)
            }
        }
    }

    private func isSelected(providerID: String, modelID: String) -> Bool {
        providerID == selectedProviderID && modelID == selectedModelID
    }
}

private extension ModelPickerSupport.ProviderSnapshot {
    init(provider: ProviderConfigEntity) {
        self.init(
            id: provider.id,
            name: provider.name,
            typeRaw: provider.typeRaw,
            isEnabled: provider.isEnabled,
            selectableModels: provider.selectableModels
        )
    }
}

private struct ProviderSection: Identifiable {
    let provider: ProviderConfigEntity
    let models: [ModelInfo]

    var id: String { provider.id }
}
