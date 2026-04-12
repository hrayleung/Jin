import SwiftUI
import SwiftData

struct ModelPickerPopover: View {
    enum Scope: String, CaseIterable, Identifiable {
        case all = "All"
        case favorites = "Favorites"

        var id: String { rawValue }
    }

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

    @State private var scope: Scope = .all
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 12) {
            searchField

            Picker("", selection: $scope) {
                ForEach(Scope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            modelList
        }
        .padding(12)
        .frame(width: 360, height: 520)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
        )
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchPlaceholder: String {
        "Search"
    }

    private var shouldShowManagedAgentSection: Bool {
        guard managedAgentContext != nil else { return false }
        return trimmedSearchText.isEmpty || !filteredManagedAgents.isEmpty
    }

    private var filteredManagedAgents: [ClaudeManagedAgentDescriptor] {
        guard let managedAgentContext else { return [] }
        let query = trimmedSearchText
        guard !query.isEmpty else { return managedAgentContext.availableAgents }

        return managedAgentContext.availableAgents
            .compactMap { agent -> (ClaudeManagedAgentDescriptor, Int)? in
                let result = FuzzyMatch.bestMatch(
                    query: query,
                    candidates: [agent.name, agent.id, agent.modelDisplayName ?? "", agent.modelID ?? ""]
                )
                guard result.matched else { return nil }
                return (agent, result.score)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(searchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
        )
    }

    private var modelList: some View {
        let sections = filteredSections

        return Group {
            if sections.isEmpty && !shouldShowManagedAgentSection {
                ContentUnavailableView(
                    emptyStateTitle,
                    systemImage: scope == .favorites ? "star" : "magnifyingglass",
                    description: Text(emptyStateDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.thinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
                )
            } else {
                List {
                    if let managedAgentContext, shouldShowManagedAgentSection {
                        Section {
                            managedAgentSectionRows(managedAgentContext)
                        } header: {
                            ManagedAgentSectionHeader(
                                provider: managedAgentContext.provider,
                                isRefreshing: managedAgentContext.isRefreshing,
                                onRefresh: managedAgentContext.onRefresh
                            )
                        }
                    }

                    ForEach(sections) { section in
                        Section {
                            ForEach(section.scopedModels) { scopedModel in
                                let model = scopedModel.model
                                ModelPickerRow(
                                    provider: section.provider,
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
                                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        } header: {
                            ProviderSectionHeader(provider: section.provider)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.thinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
                )
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
            HStack {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Spacer()
            }
            .padding(.vertical, 10)
            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if filteredManagedAgents.isEmpty {
            Text(trimmedSearchText.isEmpty ? "No agents" : "No matches")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else {
            ForEach(filteredManagedAgents) { agent in
                ManagedAgentPickerRow(
                    agent: agent,
                    isSelected: agent.id == managedAgentContext.selectedAgentID,
                    onSelect: {
                        managedAgentContext.onSelectAgent(agent)
                    }
                )
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }

        if trimmedSearchText.isEmpty {
            Button {
                managedAgentContext.onOpenSettings()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.secondary)

                    Text("Agent Settings")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 2, trailing: 8))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    private var emptyStateTitle: String {
        if scope == .favorites {
            return "No favorite models"
        }
        return "No results"
    }

    private var emptyStateDescription: String {
        if scope == .favorites {
            return "Star a model to pin it here."
        }
        return "Try another search."
    }

    private var filteredSections: [ProviderSection] {
        let providersSorted = providers
            .filter(\.isEnabled)
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        let query = trimmedSearchText

        var sections: [ProviderSection] = []
        sections.reserveCapacity(providersSorted.count)

        for provider in providersSorted {
            if provider.id == managedAgentContext?.provider.id {
                continue
            }

            let models = provider.selectableModels
            guard !models.isEmpty else { continue }
            var filtered = models

            if scope == .favorites {
                filtered = filtered.filter { favoritesStore.isFavorite(providerID: provider.id, modelID: $0.id) }
            }

            if !query.isEmpty {
                let providerMatch = FuzzyMatch.bestMatch(
                    query: query,
                    candidates: [provider.name, provider.typeRaw]
                )

                if !providerMatch.matched {
                    let scored: [(model: ModelInfo, score: Int)] = filtered.compactMap { model in
                        let result = FuzzyMatch.bestMatch(query: query, candidates: [model.name, model.id])
                        guard result.matched else { return nil }
                        return (model, result.score)
                    }
                    filtered = scored
                        .sorted { $0.score > $1.score }
                        .map(\.model)
                }
            }

            if !filtered.isEmpty {
                sections.append(ProviderSection(provider: provider, models: filtered))
            }
        }

        return sections
    }

    private func isSelected(providerID: String, modelID: String) -> Bool {
        providerID == selectedProviderID && modelID == selectedModelID
    }
}

private struct ProviderSection: Identifiable {
    let provider: ProviderConfigEntity
    let models: [ModelInfo]

    var id: String { provider.id }

    var scopedModels: [ScopedModel] {
        models.enumerated().map { index, model in
            ScopedModel(providerID: provider.id, model: model, index: index)
        }
    }
}

private struct ScopedModel: Identifiable {
    let providerID: String
    let model: ModelInfo
    let index: Int

    var id: String { "\(providerID)::\(model.id)::\(index)" }
}

private struct ProviderSectionHeader: View {
    let provider: ProviderConfigEntity

    var body: some View {
        HStack(spacing: 6) {
            ProviderIconView(iconID: provider.resolvedProviderIconID, fallbackSystemName: "network", size: 12)
                .frame(width: 12, height: 12)

            Text(provider.name)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .textCase(nil)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

private struct ManagedAgentSectionHeader: View {
    let provider: ProviderConfigEntity
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 6) {
                ProviderIconView(iconID: provider.resolvedProviderIconID, fallbackSystemName: "network", size: 12)
                    .frame(width: 12, height: 12)

                Text(provider.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onRefresh()
            } label: {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .help("Refresh agents")
        }
        .textCase(nil)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

private struct ManagedAgentPickerRow: View {
    let agent: ClaudeManagedAgentDescriptor
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.name)
                            .font(.system(.body, design: .default))
                            .lineLimit(1)

                        if let subtitle = subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 22, height: 22)
                    } else {
                        Color.clear.frame(width: 22, height: 22)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
            }
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String? {
        if let modelDisplayName = agent.modelDisplayName, !modelDisplayName.isEmpty {
            return modelDisplayName
        }
        return nil
    }
}

private struct ModelPickerRow: View {
    let provider: ProviderConfigEntity
    let model: ModelInfo
    let isSelected: Bool
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onSelect: () -> Void

    var body: some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.clear)
            }

            HStack(spacing: 10) {
                Text(model.name)
                    .font(.system(.body, design: .default))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    onToggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isFavorite ? Color.orange : Color.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(isFavorite ? "Unfavorite" : "Favorite")

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22, height: 22)
                } else {
                    Color.clear.frame(width: 22, height: 22)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}
