import SwiftUI

struct ModelPickerSearchField: View {
    @Binding var searchText: String
    let placeholder: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(text: $searchText, prompt: Text(placeholder)) {
                EmptyView()
            }
            .textFieldStyle(.plain)
            .focused($isFocused)
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
        .task {
            // Popover's window needs a tick to become key before
            // first-responder hand-off lands.
            try? await Task.sleep(nanoseconds: 50_000_000)
            isFocused = true
        }
    }
}

struct ModelPickerManagedAgentSummaryCard: View {
    let provider: ProviderConfigEntity
    let selectedAgentID: String?
    let selectedAgentName: String?
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            HStack(alignment: .top, spacing: JinSpacing.small) {
                HStack(spacing: JinSpacing.small) {
                    ProviderIconView(
                        iconID: provider.resolvedProviderIconID,
                        fallbackSystemName: "network",
                        size: 14
                    )
                    .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Managed Agent")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(selectedAgentName ?? "Select an agent")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                ModelPickerHeaderActionButton(systemName: "slider.horizontal.3", helpText: "Agent settings") {
                    onOpenSettings()
                }

                ModelPickerHeaderActionButton(systemName: "arrow.clockwise", helpText: "Refresh agents") {
                    onRefresh()
                }
                .overlay {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .disabled(isRefreshing)
            }

            if let selectedAgentID,
               let selectedAgentName,
               selectedAgentName != selectedAgentID {
                Text(selectedAgentID)
                    .jinTagStyle()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .jinSurface(.subtleStrong, cornerRadius: JinRadius.medium)
    }
}

struct ModelPickerHeaderActionButton: View {
    let systemName: String
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: JinControlMetrics.iconButtonHitSize, height: JinControlMetrics.iconButtonHitSize)
        }
        .buttonStyle(.plain)
        .background(
            Circle()
                .fill(JinSemanticColor.surface.opacity(0.7))
        )
        .overlay(
            Circle()
                .stroke(JinSemanticColor.separator.opacity(0.35), lineWidth: JinStrokeWidth.hairline)
        )
        .help(helpText)
    }
}

struct ModelPickerEmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modelPickerListSurface()
    }
}

struct ModelPickerProviderSectionHeader: View {
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

struct ModelPickerManagedAgentSectionHeader: View {
    var body: some View {
        Text("Agents")
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(nil)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }
}

struct ModelPickerManagedAgentLoadingRow: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        }
        .padding(.vertical, 10)
    }
}

struct ModelPickerManagedAgentEmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }
}

struct ModelPickerManagedAgentRow: View {
    let agent: ClaudeManagedAgentDescriptor
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.system(.body, design: .default))
                        .lineLimit(1)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Text("Current")
                        .jinTagStyle(foreground: .accentColor)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .jinSurface(isSelected ? .selected : .subtle, cornerRadius: JinRadius.small)
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

struct ModelPickerRow: View {
    let model: ModelInfo
    let isSelected: Bool
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onSelect: () -> Void

    var body: some View {
        ZStack {
            selectionBackground
            rowContent
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    private var selectionBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            modelName
            favoriteButton
            selectionIndicator
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }

    private var modelName: some View {
        Text(model.name)
            .font(.system(.body, design: .default))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var favoriteButton: some View {
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
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        if isSelected {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
        } else {
            Color.clear.frame(width: 22, height: 22)
        }
    }
}

extension View {
    func modelPickerListSurface() -> some View {
        background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
        )
    }

    func modelPickerListRowStyle(leading: CGFloat = 8) -> some View {
        listRowInsets(EdgeInsets(top: 2, leading: leading, bottom: 2, trailing: 8))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
