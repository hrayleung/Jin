import SwiftUI

struct AddMCPServerCatalogSection: View {
    @Binding var searchText: String
    @Binding var category: MCPServerCatalogCategory
    let items: [MCPServerCatalogItem]
    let onSelect: (AddMCPServerPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                JinSearchField(text: $searchText, prompt: "Search servers", focusesOnAppear: true)
                Picker("Category", selection: $category) {
                    ForEach(MCPServerCatalogCategory.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }

            HStack(spacing: 12) {
                Button("Add Custom Server…", systemImage: "plus") { onSelect(.custom) }
                Button("Import JSON…", systemImage: "square.and.arrow.down") { onSelect(.importJSON) }
            }
            .controlSize(.small)
            .padding(.bottom, 4)

            if items.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        AddMCPServerCatalogRow(item: item) { onSelect(item.preset) }
                        if item.id != items.last?.id {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
            }
        }
    }
}

private struct AddMCPServerCatalogRow: View {
    let item: MCPServerCatalogItem
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                AddMCPServerCatalogIcon(item: item, size: 26)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.body.weight(.medium))
                    Text(item.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 12)
                if let badge = item.transportBadge {
                    Text(badge)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHovered ? JinSemanticColor.subtleSurface : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
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
