import SwiftUI

struct AddMCPServerCatalogSection: View {
    @Binding var searchText: String
    @Binding var category: MCPServerCatalogCategory
    let items: [MCPServerCatalogItem]
    let onSelect: (AddMCPServerPreset) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 216, maximum: 320), spacing: JinSpacing.medium, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.large) {
            header
            searchField
            categoryChips
            entryRow
            catalogGrid
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text("Choose a server")
                .font(.title2.weight(.semibold))
            Text("Start from a known MCP server, or add your own.")
                .font(.callout)
                .foregroundStyle(JinSemanticColor.textSecondary)
        }
    }

    private var searchField: some View {
        HStack(spacing: JinSpacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(JinSemanticColor.textTertiary)
                .font(.body.weight(.medium))

            TextField("Search servers", text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small + 2)
        .jinSurface(.subtle, cornerRadius: JinRadius.medium)
        .accessibilityLabel("Search MCP servers")
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: JinSpacing.small) {
                ForEach(MCPServerCatalogCategory.allCases) { item in
                    AddMCPServerCategoryChip(
                        title: item.title,
                        isSelected: category == item
                    ) {
                        category = item
                    }
                }
            }
        }
    }

    private var entryRow: some View {
        HStack(spacing: JinSpacing.medium) {
            AddMCPServerEntryButton(
                title: "Custom",
                subtitle: "Command or HTTP",
                systemImage: "plus.square.dashed"
            ) {
                onSelect(.custom)
            }

            AddMCPServerEntryButton(
                title: "Import JSON",
                subtitle: "Claude Desktop config",
                systemImage: "square.and.arrow.down"
            ) {
                onSelect(.importJSON)
            }
        }
    }

    @ViewBuilder
    private var catalogGrid: some View {
        if items.isEmpty {
            Text("No servers match that search.")
                .font(.callout)
                .foregroundStyle(JinSemanticColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, JinSpacing.small)
        } else {
            LazyVGrid(columns: columns, spacing: JinSpacing.medium) {
                ForEach(items) { item in
                    AddMCPServerCatalogCard(item: item) {
                        onSelect(item.preset)
                    }
                }
            }
        }
    }
}

private struct AddMCPServerCategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, JinSpacing.medium)
                .padding(.vertical, 6)
                .jinSurface(isSelected ? .selected : .subtle, cornerRadius: JinRadius.small)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct AddMCPServerEntryButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: JinSpacing.medium) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .jinSurface(.subtle, cornerRadius: JinRadius.small)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(JinSemanticColor.textSecondary)
                }

                Spacer(minLength: 0)
            }
            .padding(JinSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .jinSurface(.raised, cornerRadius: JinRadius.large)
        }
        .buttonStyle(.plain)
    }
}

struct AddMCPServerCatalogCard: View {
    let item: MCPServerCatalogItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: JinSpacing.medium) {
                HStack(alignment: .top, spacing: JinSpacing.small) {
                    AddMCPServerCatalogIcon(item: item, size: 28)
                        .frame(width: 36, height: 36)
                        .jinSurface(.subtle, cornerRadius: JinRadius.small)

                    Spacer(minLength: 0)

                    if let badge = item.transportBadge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(JinSemanticColor.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .jinSurface(.outlined, cornerRadius: JinRadius.small)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(item.summary)
                        .font(.caption)
                        .foregroundStyle(JinSemanticColor.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(JinSpacing.medium)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .jinSurface(.raised, cornerRadius: JinRadius.large)
            .contentShape(RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(item.summary)
    }
}

struct AddMCPServerCatalogIcon: View {
    let item: MCPServerCatalogItem
    var size: CGFloat = 28

    var body: some View {
        if item.iconID != MCPIconCatalog.defaultIconID {
            MCPIconView(iconID: item.iconID, size: size)
        } else if let symbolName = item.symbolName {
            Image(systemName: symbolName)
                .font(.system(size: size * 0.58, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        } else {
            MCPIconView(iconID: item.iconID, size: size)
        }
    }
}
