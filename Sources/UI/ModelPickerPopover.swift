import SwiftUI
import SwiftData

struct ModelPickerPopover: View {
    enum Scope: String, CaseIterable, Identifiable {
        case all = "All"
        case favorites = "Favorites"

        var id: String { rawValue }
    }

    @ObservedObject var favoritesStore: FavoriteModelsStore

    let providers: [ProviderConfigEntity]
    let selectedProviderID: String
    let selectedModelID: String
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
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search models", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
        )
    }

    private var modelList: some View {
        let sections = filteredSections

        return Group {
            if sections.isEmpty {
                ContentUnavailableView(
                    scope == .favorites ? "No favorite models" : "No models found",
                    systemImage: scope == .favorites ? "star" : "magnifyingglass",
                    description: Text(scope == .favorites ? "Star a model to pin it here." : "Try a different search.")
                )
            } else {
                List {
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
                            }
                        } header: {
                            ProviderSectionHeader(provider: section.provider)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }

    private var filteredSections: [ProviderSection] {
        let providersSorted = providers.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var sections: [ProviderSection] = []
        sections.reserveCapacity(providersSorted.count)

        for provider in providersSorted {
            guard let models = try? JSONDecoder().decode([ModelInfo].self, from: provider.modelsData) else { continue }
            var filtered = models

            if scope == .favorites {
                filtered = filtered.filter { favoritesStore.isFavorite(providerID: provider.id, modelID: $0.id) }
            }

            if !query.isEmpty {
                let providerMatches = provider.name.lowercased().contains(query)
                    || provider.id.lowercased().contains(query)
                    || provider.typeRaw.lowercased().contains(query)

                if !providerMatches {
                    filtered = filtered.filter { model in
                        model.name.lowercased().contains(query) || model.id.lowercased().contains(query)
                    }
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
            if let providerType = ProviderType(rawValue: provider.typeRaw) {
                Image(systemName: iconName(for: providerType))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

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

    private func iconName(for type: ProviderType) -> String {
        switch type {
        case .openai:
            return "sparkles"
        case .anthropic:
            return "person.crop.circle"
        case .xai:
            return "bolt"
        case .fireworks:
            return "flame"
        case .cerebras:
            return "cpu"
        case .gemini:
            return "g.circle"
        case .vertexai:
            return "cloud"
        }
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
                    // Keep trailing alignment stable as favorites toggle.
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
