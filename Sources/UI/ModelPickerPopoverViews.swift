import SwiftUI

struct ModelPickerSearchField: View {
    @Binding var searchText: String
    let placeholder: String

    var body: some View {
        JinSearchField(text: $searchText, prompt: placeholder, focusesOnAppear: true, chrome: .borderless)
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
        .buttonStyle(JinIconButtonStyle(showBackground: false))
        .help(helpText)
        .accessibilityLabel(helpText)
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
    }
}

struct ModelPickerProviderSectionHeader: View {
    let provider: ProviderConfigEntity

    var body: some View {
        Text(provider.name)
            .modelPickerSectionHeading()
    }
}

struct ModelPickerManagedAgentSectionHeader: View {
    var body: some View {
        Text("Agents")
            .modelPickerSectionHeading()
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
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: ModelPickerLayout.labelSpacing) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: ModelPickerLayout.symbolWidth, height: 18)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.system(.body, design: .default))
                        .fontWeight(isSelected ? .medium : .regular)
                        .lineLimit(1)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, ModelPickerLayout.contentInset)
            .frame(minHeight: ModelPickerLayout.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .fill(isHovered ? JinSemanticColor.hoverFill : (isSelected ? JinSemanticColor.controlFill : .clear))
        }
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
    @State private var isHovered = false
    @FocusState private var isFavoriteFocused: Bool

    var body: some View {
        rowContent
            .background(selectionBackground)
            .contentShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
            .onHover { isHovered = $0 }
            .contextMenu {
                Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", action: onToggleFavorite)
            }
    }

    private var selectionBackground: some View {
        RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
            .fill(isHovered ? JinSemanticColor.hoverFill : (isSelected ? JinSemanticColor.controlFill : .clear))
    }

    private var rowContent: some View {
        HStack(spacing: 2) {
            // Separate buttons avoid nesting the favorite action inside a row
            // gesture, and make model selection available to keyboard/VoiceOver.
            Button(action: onSelect) {
                HStack(spacing: ModelPickerLayout.labelSpacing) {
                    selectionIndicator
                    modelName
                }
                .padding(.leading, ModelPickerLayout.contentInset)
                .padding(.vertical, 4)
                .frame(minHeight: ModelPickerLayout.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityAction(named: isFavorite ? "Remove from Favorites" : "Add to Favorites", onToggleFavorite)

            favoriteButton
                .padding(.trailing, 4)
        }
    }

    private var modelName: some View {
        Text(model.name)
            .font(.system(.body, design: .default))
            .fontWeight(isSelected ? .medium : .regular)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var favoriteButton: some View {
        Button {
            onToggleFavorite()
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .opacity(isFavorite || isHovered || isFavoriteFocused ? 1 : 0)
        }
        .buttonStyle(JinIconButtonStyle(showBackground: false, size: 26))
        .focused($isFavoriteFocused)
        .help(isFavorite ? "Unfavorite" : "Favorite")
        .accessibilityLabel(isFavorite ? "Remove \(model.name) from favorites" : "Add \(model.name) to favorites")
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        if isSelected {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: ModelPickerLayout.symbolWidth, height: 18)
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: ModelPickerLayout.symbolWidth, height: 18)
        }
    }
}

extension View {
    func modelPickerListRowStyle(leading: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: leading, bottom: 0, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    func modelPickerSectionHeading() -> some View {
        font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, ModelPickerLayout.headingInset)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
            .selectionDisabled()
    }
}
